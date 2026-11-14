"""Offline tests for the signed Ad Hoc build-number history guard."""
from __future__ import annotations

import json
import re
import unittest
from email.message import Message
from unittest.mock import Mock, patch
from urllib.error import HTTPError

from tools.ios_adhoc_release_history import (
    ReleaseHistoryError,
    collect_release_pages,
    fetch_release_history,
    _download_metadata_asset,
    validate_release_history,
)


def release(release_id: int, build: int, *, draft: bool = False, **overrides):
    version = "1.2.3"
    commit = f"{release_id:07x}" + "0" * 33
    value = {
        "id": release_id,
        "tag_name": f"adhoc-v{version}-build{build}-{commit[:7]}",
        "name": f"Theresian's Quest {version} ({build}) Ad Hoc",
        "body": f"Release notes\n\nSource commit: {commit}\nVersion: {version} ({build})\n",
        "draft": draft,
        "prerelease": True,
        "assets": [
            {"id": release_id * 10 + 1, "name": "Theresians-Quest.ipa", "size": 123, "state": "uploaded"},
            {"id": release_id * 10 + 2, "name": "build-metadata.json", "size": 45, "state": "uploaded"},
            {"id": release_id * 10 + 3, "name": "ios-adhoc-build-report.txt", "size": 67, "state": "uploaded"},
            {"id": release_id * 10 + 4, "name": "CHANGELOG.md", "size": 89, "state": "uploaded"},
        ],
    }
    value.update(overrides)
    return value


def validate(releases, candidate, metadata_overrides=None):
    metadata_by_asset_id = {}
    for item in releases:
        tag = re.fullmatch(r"adhoc-v([0-9]+\.[0-9]+\.[0-9]+)-build([1-9][0-9]*)-[0-9a-f]{7}", item["tag_name"])
        metadata_asset = next((asset for asset in item.get("assets", []) if asset.get("name") == "build-metadata.json"), None)
        if tag is None or metadata_asset is None:
            continue
        source = re.findall(r"(?m)^Source commit: ([0-9a-f]{40})\s*$", item.get("body", ""))
        metadata = {
            "source_commit": source[0] if source else "0" * 40,
            "marketing_version": tag.group(1),
            "build_number": tag.group(2),
            "bundle_id": "com.theresiansquest.game",
            "distribution": "ad-hoc",
        }
        metadata.update((metadata_overrides or {}).get(metadata_asset["id"], {}))
        metadata_by_asset_id[metadata_asset["id"]] = json.dumps(metadata).encode()
    return validate_release_history(releases, candidate, metadata_by_asset_id=metadata_by_asset_id)


class ReleaseHistoryTests(unittest.TestCase):
    def test_first_release_is_allowed_only_with_empty_history(self):
        self.assertEqual(validate([], 1), (0, 0))

    def test_build_50_is_rejected_when_existing_release_200_has_no_latest_pointer(self):
        with self.assertRaisesRegex(ReleaseHistoryError, "must exceed.*200"):
            validate([release(1, 200)], 50)

    def test_build_201_is_allowed_when_existing_release_200_has_no_latest_pointer(self):
        self.assertEqual(validate([release(1, 200)], 201), (1, 200))

    def test_drafts_are_part_of_release_history(self):
        with self.assertRaisesRegex(ReleaseHistoryError, "highest verified release build 200"):
            validate([release(1, 200, draft=True)], 200)

    def test_multiple_releases_require_build_above_the_highest(self):
        history = [release(1, 50), release(2, 200), release(3, 120, draft=True)]
        self.assertEqual(validate(history, 201), (3, 200))
        with self.assertRaisesRegex(ReleaseHistoryError, "highest verified release build 200"):
            validate(history, 199)

    def test_duplicate_build_number_is_rejected_even_when_tags_differ(self):
        with self.assertRaisesRegex(ReleaseHistoryError, "reused build number"):
            validate([release(1, 200), release(2, 200)], 201)

    def test_duplicate_release_id_or_tag_is_rejected(self):
        item = release(1, 200)
        duplicate_id = release(2, 201)
        duplicate_id["id"] = 1
        with self.assertRaisesRegex(ReleaseHistoryError, "duplicate release ID"):
            validate([item, duplicate_id], 202)
        with self.assertRaisesRegex(ReleaseHistoryError, "duplicate release tag"):
            duplicate_tag = dict(item, id=2, assets=[
                {**asset, "id": 20 + asset["id"] % 10}
                for asset in item["assets"]
            ])
            validate([item, duplicate_tag], 202)

    def test_asset_ids_cannot_be_reused_across_release_records(self):
        first = release(1, 200)
        second = release(2, 201)
        second["assets"][0]["id"] = first["assets"][0]["id"]
        with self.assertRaisesRegex(ReleaseHistoryError, "reused across releases"):
            validate([first, second], 202)

    def test_malformed_or_inconsistent_metadata_fails_closed(self):
        malformed_tag = release(1, 200, tag_name="broken-tag")
        with self.assertRaisesRegex(ReleaseHistoryError, "malformed Ad Hoc release tag"):
            validate([malformed_tag], 201)

        inconsistent_name = release(1, 200, name="Theresian's Quest 1.2.3 (199) Ad Hoc")
        with self.assertRaisesRegex(ReleaseHistoryError, "name does not match"):
            validate([inconsistent_name], 201)

        inconsistent_body = release(1, 200, body="Source commit: 0000000000000000000000000000000000000001\nVersion: 1.2.3 (200)\n")
        with self.assertRaisesRegex(ReleaseHistoryError, "tag and source commit do not match"):
            validate([inconsistent_body], 201)

        ambiguous_body = release(1, 200, body=release(1, 200)["body"] * 2)
        with self.assertRaisesRegex(ReleaseHistoryError, "missing or ambiguous source/version"):
            validate([ambiguous_body], 201)

    def test_downloaded_build_metadata_must_match_release_history(self):
        item = release(1, 200)
        asset_id = item["assets"][1]["id"]
        for changes in (
            {"build_number": "199"},
            {"marketing_version": "1.2.4"},
            {"source_commit": "f" * 40},
            {"bundle_id": "com.other.game"},
            {"distribution": "app-store"},
        ):
            with self.subTest(changes=changes):
                with self.assertRaisesRegex(ReleaseHistoryError, "metadata asset contradicts"):
                    validate([item], 201, {asset_id: changes})

    def test_partial_corrupt_or_unuploaded_release_is_not_ignored(self):
        for item in (
            release(1, 200, assets=[]),
            release(1, 200, assets=[{"id": 11, "name": "app.ipa", "size": 1, "state": "new"}]),
            release(1, 200, assets=[{"id": 11, "name": "app.ipa", "size": 1, "state": "uploaded"}]),
            release(1, 200, assets=[
                {"id": 11, "name": "a.ipa", "size": 1, "state": "uploaded"},
                {"id": 12, "name": "b.ipa", "size": 1, "state": "uploaded"},
                *release(1, 200)["assets"][1:],
            ]),
        ):
            with self.subTest(assets=item["assets"]):
                with self.assertRaises(ReleaseHistoryError):
                    validate([item], 201)

    def test_malformed_candidate_or_response_is_rejected(self):
        for candidate in (0, "0", "01", "-1", "1.5", True, "2147483648"):
            with self.subTest(candidate=candidate):
                with self.assertRaises(ReleaseHistoryError):
                    validate([], candidate)
        for history in (None, {}, "[]"):
            with self.subTest(history=history):
                with self.assertRaises(ReleaseHistoryError):
                    validate_release_history(history, 1, metadata_by_asset_id={})

    def test_pagination_collects_every_page_including_exact_page_boundary(self):
        first_page = [release(index, index + 1) for index in range(1, 101)]
        second_page = [release(101, 102)]
        requests = []

        def fetch(page, size):
            requests.append((page, size))
            return {1: first_page, 2: second_page}[page]

        result = collect_release_pages(fetch, page_size=100, max_pages=3)
        self.assertEqual(len(result), 101)
        self.assertEqual(requests, [(1, 100), (2, 100)])
        self.assertEqual(validate(result, 103), (101, 102))

    def test_api_failure_malformed_page_and_page_limit_fail_closed(self):
        def failed(_page, _size):
            raise OSError("private token should never appear in this error")

        with self.assertRaisesRegex(ReleaseHistoryError, "request failed on page 1") as caught:
            collect_release_pages(failed)
        self.assertNotIn("private token", str(caught.exception))
        with self.assertRaisesRegex(ReleaseHistoryError, "is malformed"):
            collect_release_pages(lambda _page, _size: {})
        with self.assertRaisesRegex(ReleaseHistoryError, "pagination safety limit"):
            collect_release_pages(lambda _page, size: [None] * size, page_size=1, max_pages=2)

    def test_history_api_requires_official_https_origin_and_valid_repository_token(self):
        for api, repository, token in (
            ("http://api.github.com", "owner/releases", "token"),
            ("https://evil.example", "owner/releases", "token"),
            ("https://api.github.com/path", "owner/releases", "token"),
            ("https://api.github.com", "owner/../releases", "token"),
            ("https://api.github.com", "owner/releases", ""),
        ):
            with self.subTest(api=api, repository=repository):
                with self.assertRaises(ReleaseHistoryError):
                    fetch_release_history(api, repository, token)

    def test_metadata_asset_redirect_never_forwards_private_token(self):
        headers = Message()
        headers["Location"] = "https://release-assets.githubusercontent.com/file?signature=synthetic"
        redirect = HTTPError("https://api.github.com/asset", 302, "redirect", headers, None)

        class Response:
            status = 200
            headers = {"Content-Length": "2"}

            def __enter__(self):
                return self

            def __exit__(self, *_args):
                return False

            @staticmethod
            def read(_limit):
                return b"{}"

        opener = Mock()
        opener.open.side_effect = [redirect, Response()]
        with patch("tools.ios_adhoc_release_history.build_opener", return_value=opener):
            self.assertEqual(
                _download_metadata_asset("https://api.github.com", "owner/releases", "synthetic-secret", 12),
                b"{}",
            )
        second_request = opener.open.call_args_list[1].args[0]
        self.assertIsNone(second_request.get_header("Authorization"))
        self.assertIn("synthetic-secret", opener.open.call_args_list[0].args[0].get_header("Authorization"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
