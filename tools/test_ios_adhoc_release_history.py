#!/usr/bin/env python3
"""Offline tests for the fail-closed private Ad Hoc release history guard."""
from __future__ import annotations

import copy
import hashlib
import json
import unittest
from urllib.parse import parse_qs, urlsplit

from tools.ios_adhoc_release_history import (
    ReleaseHistoryError,
    fetch_release_asset,
    fetch_release_history,
    validate_release_history,
)


SOURCE_REPOSITORY = "Binsentt/Theresians-Game"
BUNDLE_ID = "com.theresiansquest.game"
TEAM_ID = "7A4H2D888M"
MINIMUM_IOS_VERSION = "15.0"
SOURCE_COMMIT = "abcdef0" + "a" * 33
IPA_SHA256 = "f" * 64
IPA_SIZE = 12345
ASSET_CONTENTS: dict[int, bytes] = {}


def _asset(asset_id: int, name: str, content: bytes, *, digest: str | None = None) -> dict:
    return {
        "id": asset_id,
        "name": name,
        "state": "uploaded",
        "size": len(content),
        "digest": digest or f"sha256:{hashlib.sha256(content).hexdigest()}",
    }


def _metadata(
    build: int,
    version: str,
    commit: str,
    *,
    overrides: dict | None = None,
) -> bytes:
    payload = {
        "repository": SOURCE_REPOSITORY,
        "source_commit": commit,
        "godot_version": "4.6.1",
        "marketing_version": version,
        "build_number": str(build),
        "bundle_id": BUNDLE_ID,
        "team_id": TEAM_ID,
        "minimum_ios_version": MINIMUM_IOS_VERSION,
        "distribution": "ad-hoc",
    }
    if overrides:
        payload.update(overrides)
    return (json.dumps(payload, indent=2) + "\n").encode("utf-8")


def _build_report(
    build: int,
    version: str,
    commit: str,
    ipa_name: str,
    *,
    overrides: dict | None = None,
) -> bytes:
    fields = {
        "source_commit": commit,
        "godot_version": "4.6.1",
        "xcode_version": "26.3",
        "ios_sdk": "26.2",
        "bundle_id": BUNDLE_ID,
        "team_id": TEAM_ID,
        "marketing_version": version,
        "build_number": str(build),
        "minimum_ios_version": MINIMUM_IOS_VERSION,
        "architecture": "arm64",
        "godot_engine": "Release",
        "distribution": "Ad Hoc",
        "registered_device_count": "1",
        "pck_sha256": "1" * 64,
        "privacy_manifest_sha256": "2" * 64,
        "ipa_file": ipa_name,
        "ipa_size_bytes": str(IPA_SIZE),
        "ipa_sha256": IPA_SHA256,
    }
    if overrides:
        fields.update(overrides)
    return ("".join(f"{key}={value}\n" for key, value in fields.items())).encode("utf-8")


def release(
    build: int,
    *,
    draft: bool = False,
    version: str = "1.2.3",
    name_build: int | None = None,
    tag_build: int | None = None,
    body_build: int | None = None,
    release_id: int | None = None,
    tag_version: str | None = None,
    body_version: str | None = None,
    prerelease: bool = True,
    assets: list[dict] | None = None,
    name: str | None = None,
    body: str | None = None,
    tag_name: str | None = None,
    source_commit: str = SOURCE_COMMIT,
    body_commit: str | None = None,
    tag_commit: str | None = None,
    metadata_overrides: dict | None = None,
    metadata_bytes: bytes | None = None,
    report_overrides: dict | None = None,
) -> dict:
    record_id = release_id or build
    name_build = build if name_build is None else name_build
    tag_build = build if tag_build is None else tag_build
    body_build = build if body_build is None else body_build
    tag_version = version if tag_version is None else tag_version
    body_version = version if body_version is None else body_version
    tag_commit = source_commit[:7] if tag_commit is None else tag_commit
    body_commit = source_commit if body_commit is None else body_commit
    ipa_name = "TheresiansQuest-iOS-AdHoc.ipa"
    metadata_id = record_id * 10 + 1
    report_id = record_id * 10 + 2
    ipa_id = record_id * 10 + 3
    changelog_id = record_id * 10 + 4

    metadata_payload = (
        _metadata(build, version, source_commit, overrides=metadata_overrides)
        if metadata_bytes is None
        else metadata_bytes
    )
    report_payload = _build_report(
        build, version, source_commit, ipa_name, overrides=report_overrides
    )
    ASSET_CONTENTS[metadata_id] = metadata_payload
    ASSET_CONTENTS[report_id] = report_payload

    ipa_asset = _asset(ipa_id, ipa_name, b"synthetic-ipa", digest=f"sha256:{IPA_SHA256}")
    ipa_asset["size"] = IPA_SIZE
    default_assets = [
        ipa_asset,
        _asset(report_id, "ios-adhoc-build-report.txt", report_payload),
        _asset(metadata_id, "build-metadata.json", metadata_payload),
        _asset(changelog_id, "CHANGELOG.md", b"Synthetic release notes\n"),
    ]
    return {
        "id": record_id,
        "tag_name": tag_name or f"adhoc-v{tag_version}-build{tag_build}-{tag_commit}",
        "name": name or f"Theresian's Quest {version} ({name_build}) Ad Hoc",
        "body": body if body is not None else (
            f"Synthetic release notes\n\nSource commit: {body_commit}\n"
            f"Version: {body_version} ({body_build})\n"
        ),
        "draft": draft,
        "prerelease": prerelease,
        "assets": default_assets if assets is None else assets,
    }


def _asset_loader(_release: dict, asset: dict) -> bytes:
    try:
        return ASSET_CONTENTS[asset["id"]]
    except KeyError:
        raise ReleaseHistoryError("Synthetic release asset was not available.") from None


def validate(proposed: str | int, releases: list[dict], *, asset_loader=_asset_loader) -> int:
    return validate_release_history(
        proposed,
        releases,
        asset_loader=asset_loader,
        expected_repository=SOURCE_REPOSITORY,
        expected_bundle_id=BUNDLE_ID,
        expected_team_id=TEAM_ID,
        expected_minimum_ios_version=MINIMUM_IOS_VERSION,
    )


class ReleaseHistoryValidationTests(unittest.TestCase):
    def setUp(self):
        ASSET_CONTENTS.clear()

    def test_accepts_uploaded_assets_and_matching_publisher_metadata(self):
        record = release(140)
        self.assertEqual(validate("141", [record]), 140)

    def test_complete_draft_is_valid_and_reserves_its_build(self):
        records = [release(125), release(140, draft=True)]
        self.assertEqual(validate("141", records), 140)

    def test_empty_private_history_is_valid_but_does_not_claim_external_history(self):
        self.assertEqual(validate("1", []), 0)

    def test_rejects_build_equal_to_or_below_any_release(self):
        for proposed in ("140", "139"):
            with self.subTest(proposed=proposed), self.assertRaises(ReleaseHistoryError):
                validate(proposed, [release(140, draft=True)])

    def test_rejects_duplicate_build_numbers_even_when_tags_differ(self):
        second = release(150, release_id=11)
        second["tag_name"] = "adhoc-v1.2.3-build150-1234567"
        second["body"] = second["body"].replace("abcdef0", "1234567", 1)
        second["assets"][2]["id"] += 1
        with self.assertRaisesRegex(ReleaseHistoryError, "duplicate build number"):
            validate("200", [release(150, release_id=10), second])

    def test_rejects_malformed_or_inconsistent_release_identity(self):
        cases = [
            release(150, name_build=151),
            release(150, tag_build=151),
            release(150, body_build=151),
            release(150, tag_version="1.2.4"),
            release(150, body_version="1.2.4"),
            release(150, prerelease=False),
            release(150, name="unrelated"),
            release(150, tag_name="adhoc-broken"),
            release(150, body="release notes without provenance"),
            release(150, tag_commit="1234567"),
        ]
        for record in cases:
            with self.subTest(record=record), self.assertRaises(ReleaseHistoryError):
                validate("200", [record])

    def test_rejects_duplicate_release_ids_and_tags(self):
        with self.assertRaisesRegex(ReleaseHistoryError, "duplicate"):
            validate("200", [release(150, release_id=7), release(151, release_id=7)])
        duplicate_tag = release(150, release_id=8)
        duplicate_tag["tag_name"] = release(150, release_id=7)["tag_name"]
        with self.assertRaisesRegex(ReleaseHistoryError, "duplicate"):
            validate("200", [release(150, release_id=7), duplicate_tag])

    def test_rejects_unuploaded_asset(self):
        record = release(150)
        record["assets"][2]["state"] = "starter"
        with self.assertRaisesRegex(ReleaseHistoryError, "uploaded"):
            validate("200", [record])

    def test_rejects_zero_or_missing_asset_size(self):
        for mutation in ("zero", "missing"):
            with self.subTest(mutation=mutation):
                record = release(150)
                if mutation == "zero":
                    record["assets"][2]["size"] = 0
                else:
                    del record["assets"][2]["size"]
                with self.assertRaisesRegex(ReleaseHistoryError, "size"):
                    validate("200", [record])

    def test_rejects_duplicate_required_asset_names_case_insensitively(self):
        record = release(150)
        duplicate = copy.deepcopy(record["assets"][2])
        duplicate["id"] += 100
        duplicate["name"] = "BUILD-METADATA.JSON"
        record["assets"].append(duplicate)
        with self.assertRaisesRegex(ReleaseHistoryError, "duplicate"):
            validate("200", [record])

    def test_rejects_duplicate_asset_ids(self):
        record = release(150)
        record["assets"][0]["id"] = record["assets"][2]["id"]
        with self.assertRaisesRegex(ReleaseHistoryError, "duplicate asset ID"):
            validate("200", [record])

    def test_rejects_missing_expected_ipa_metadata_or_build_report(self):
        for missing_name in (
            "TheresiansQuest-iOS-AdHoc.ipa",
            "build-metadata.json",
            "ios-adhoc-build-report.txt",
        ):
            with self.subTest(missing_name=missing_name):
                record = release(150)
                record["assets"] = [
                    asset for asset in record["assets"] if asset["name"] != missing_name
                ]
                with self.assertRaises(ReleaseHistoryError):
                    validate("200", [record])

    def test_rejects_metadata_build_version_and_source_sha_mismatches(self):
        cases = [
            {"build_number": "151"},
            {"marketing_version": "1.2.4"},
            # Same tag prefix but a different full SHA must still be rejected.
            {"source_commit": "abcdef0" + "b" * 33},
            {"repository": "attacker/other-repo"},
            {"godot_version": "4.5.0"},
            {"bundle_id": "com.attacker.app"},
            {"team_id": "0000000000"},
            {"minimum_ios_version": "14.0"},
            {"distribution": "app-store"},
        ]
        for overrides in cases:
            with self.subTest(overrides=overrides):
                record = release(150, metadata_overrides=overrides)
                with self.assertRaises(ReleaseHistoryError):
                    validate("200", [record])

    def test_rejects_build_report_that_does_not_bind_the_uploaded_ipa(self):
        cases = [
            {"source_commit": "abcdef0" + "b" * 33},
            {"marketing_version": "1.2.4"},
            {"build_number": "151"},
            {"distribution": "App Store"},
            {"ipa_file": "different.ipa"},
            {"ipa_size_bytes": str(IPA_SIZE + 1)},
            {"ipa_sha256": "0" * 64},
        ]
        for overrides in cases:
            with self.subTest(overrides=overrides):
                record = release(150, report_overrides=overrides)
                with self.assertRaises(ReleaseHistoryError):
                    validate("200", [record])

    def test_rejects_missing_or_unexpected_metadata_fields(self):
        record = release(150, metadata_overrides={"unexpected": "value"})
        with self.assertRaises(ReleaseHistoryError):
            validate("200", [record])
        ASSET_CONTENTS.clear()
        record = release(151)
        asset = record["assets"][2]
        payload = json.loads(ASSET_CONTENTS[asset["id"]])
        del payload["source_commit"]
        ASSET_CONTENTS[asset["id"]] = json.dumps(payload).encode("utf-8")
        asset["size"] = len(ASSET_CONTENTS[asset["id"]])
        asset["digest"] = f"sha256:{hashlib.sha256(ASSET_CONTENTS[asset['id']]).hexdigest()}"
        with self.assertRaises(ReleaseHistoryError):
            validate("200", [record])

    def test_rejects_malformed_metadata_and_duplicate_json_keys(self):
        for payload in (b"", b"{not json", b'{"build_number":"1","build_number":"2"}'):
            with self.subTest(payload=payload):
                record = release(150, metadata_bytes=payload)
                with self.assertRaises(ReleaseHistoryError):
                    validate("200", [record])

    def test_rejects_wrong_metadata_asset_digest(self):
        record = release(150)
        record["assets"][2]["digest"] = "sha256:" + "0" * 64
        with self.assertRaisesRegex(ReleaseHistoryError, "digest"):
            validate("200", [record])

    def test_rejects_missing_metadata_asset_digest(self):
        record = release(150)
        del record["assets"][2]["digest"]
        with self.assertRaisesRegex(ReleaseHistoryError, "digest"):
            validate("200", [record])

    def test_rejects_metadata_download_failure_without_leaking_credentials(self):
        token = "private-token-must-not-appear"

        def fail(_record: dict, _asset: dict) -> bytes:
            raise ReleaseHistoryError("metadata download failed")

        with self.assertRaises(ReleaseHistoryError) as caught:
            validate("200", [release(150)], asset_loader=fail)
        self.assertNotIn(token, str(caught.exception))

    def test_rejects_incomplete_draft_and_requires_manual_recovery(self):
        record = release(150, draft=True, assets=[])
        with self.assertRaisesRegex(ReleaseHistoryError, "Draft"):
            validate("200", [record])

    def test_rejects_malformed_proposed_build_number(self):
        for proposed in ("0", "-1", "01", "abc", "2147483648"):
            with self.subTest(proposed=proposed), self.assertRaises(ReleaseHistoryError):
                validate(proposed, [])


class ReleaseHistoryApiTests(unittest.TestCase):
    def setUp(self):
        ASSET_CONTENTS.clear()

    def test_fetches_every_release_page_and_includes_drafts(self):
        page_one = [release(number + 1, release_id=number + 1) for number in range(100)]
        page_two = [release(101, draft=True, release_id=101)]
        base = "https://api.github.com/repos/acme/private-releases/releases"
        calls: list[str] = []

        def fetch(url: str, token: str):
            calls.append(url)
            self.assertEqual(token, "test-secret-never-logged")
            page = parse_qs(urlsplit(url).query)["page"][0]
            if page == "1":
                link = f'<{base}?per_page=100&page=2>; rel="next", <{base}?per_page=100&page=1>; rel="first"'
                return 200, {"Link": link}, page_one
            return 200, {}, page_two

        result = fetch_release_history(
            "https://api.github.com", "acme/private-releases",
            "test-secret-never-logged", fetcher=fetch,
        )
        self.assertEqual(len(calls), 2)
        self.assertEqual([parse_qs(urlsplit(url).query)["page"][0] for url in calls], ["1", "2"])
        self.assertEqual(len(result), 101)
        self.assertTrue(result[-1]["draft"])
        self.assertEqual(validate("102", result), 101)

    def test_fails_closed_on_http_and_json_api_errors_without_echoing_token(self):
        token = "secret-test-token"
        for response in (
            (503, {}, []),
            (200, {}, b"not-json"),
            (200, {}, {"message": "not a release list"}),
        ):
            with self.subTest(response=response):
                with self.assertRaises(ReleaseHistoryError) as caught:
                    fetch_release_history(
                        "https://api.github.com", "acme/private-releases", token,
                        fetcher=lambda _url, _token: response,
                    )
                self.assertNotIn(token, str(caught.exception))

    def test_probes_after_a_full_page_and_rejects_untrusted_pagination_links(self):
        complete_page = [release(number + 1, release_id=number + 1) for number in range(100)]
        base = "https://api.github.com/repos/acme/private-releases/releases"
        calls: list[str] = []

        def empty_followup(url: str, _token: str):
            calls.append(url)
            return (200, {}, complete_page) if len(calls) == 1 else (200, {}, [])

        result = fetch_release_history(
            "https://api.github.com", "acme/private-releases", "token", fetcher=empty_followup
        )
        self.assertEqual(len(result), 100)
        self.assertEqual(parse_qs(urlsplit(calls[1]).query)["page"], ["2"])

        with self.assertRaises(ReleaseHistoryError):
            fetch_release_history(
                "https://api.github.com", "acme/private-releases", "token",
                fetcher=lambda _url, _token: (
                    200,
                    {"Link": '<https://attacker.example/leak?per_page=100&page=2>; rel="next"'},
                    complete_page,
                ),
            )

    def test_does_not_accept_partial_history_when_a_later_page_fails(self):
        page_one = [release(number + 1, release_id=number + 1) for number in range(100)]
        base = "https://api.github.com/repos/acme/private-releases/releases"
        calls = 0

        def fetch(_url: str, _token: str):
            nonlocal calls
            calls += 1
            if calls == 1:
                return 200, {"Link": f'<{base}?per_page=100&page=2>; rel="next"'}, page_one
            return 502, {}, b"private error payload"

        with self.assertRaises(ReleaseHistoryError):
            fetch_release_history(
                "https://api.github.com", "acme/private-releases", "token", fetcher=fetch
            )
        self.assertEqual(calls, 2)

    def test_fails_closed_on_invalid_repository_or_api_origin(self):
        for api_url, repository in (
            ("http://api.github.com", "acme/private-releases"),
            ("https://api.github.com", "acme/private/releases"),
        ):
            with self.subTest(api_url=api_url, repository=repository), self.assertRaises(ReleaseHistoryError):
                fetch_release_history(api_url, repository, "token", fetcher=lambda *_args: (200, {}, []))


class ReleaseAssetApiTests(unittest.TestCase):
    def setUp(self):
        ASSET_CONTENTS.clear()

    def test_follows_one_trusted_redirect_without_forwarding_token(self):
        payload = b'{"metadata":"synthetic"}'
        asset = _asset(42, "build-metadata.json", payload)
        calls: list[tuple[str, str | None]] = []
        signed_url = "https://release-assets.githubusercontent.com/signed?token=temporary"

        def fetch(url: str, token: str | None):
            calls.append((url, token))
            if len(calls) == 1:
                return 302, {"Location": signed_url}, b""
            return 200, {"Content-Length": str(len(payload))}, payload

        result = fetch_release_asset(
            "https://api.github.com", "acme/private-releases", "private-token", asset, fetcher=fetch
        )
        self.assertEqual(result, payload)
        self.assertEqual(calls, [
            ("https://api.github.com/repos/acme/private-releases/releases/assets/42", "private-token"),
            (signed_url, None),
        ])

    def test_rejects_untrusted_redirect_without_logging_url_or_token(self):
        asset = _asset(42, "build-metadata.json", b"{}");
        token = "private-token-do-not-log"
        location = "https://attacker.example/steal?token=secret-query"

        with self.assertRaises(ReleaseHistoryError) as caught:
            fetch_release_asset(
                "https://api.github.com", "acme/private-releases", token, asset,
                fetcher=lambda _url, _token: (302, {"Location": location}, b""),
            )
        self.assertNotIn(token, str(caught.exception))
        self.assertNotIn(location, str(caught.exception))

    def test_rejects_a_second_redirect(self):
        asset = _asset(42, "build-metadata.json", b"{}");
        calls = 0

        def fetch(_url: str, _token: str | None):
            nonlocal calls
            calls += 1
            return 302, {"Location": "https://objects.githubusercontent.com/again"}, b""

        with self.assertRaises(ReleaseHistoryError):
            fetch_release_asset("https://api.github.com", "acme/private-releases", "token", asset, fetcher=fetch)
        self.assertEqual(calls, 2)

    def test_rejects_download_size_and_digest_mismatches(self):
        payload = b'{"metadata":"synthetic"}'
        for asset in (
            _asset(42, "build-metadata.json", payload, digest="sha256:" + "0" * 64),
            {**_asset(42, "build-metadata.json", payload), "size": len(payload) + 1},
        ):
            with self.subTest(asset=asset), self.assertRaises(ReleaseHistoryError):
                fetch_release_asset(
                    "https://api.github.com", "acme/private-releases", "token", asset,
                    fetcher=lambda _url, _token: (200, {}, payload),
                )

    def test_rejects_missing_digest_and_oversized_download(self):
        payload = b"x" * (1024 * 1024 + 1)
        asset = {"id": 42, "name": "build-metadata.json", "state": "uploaded", "size": 1}
        with self.assertRaises(ReleaseHistoryError):
            fetch_release_asset(
                "https://api.github.com", "acme/private-releases", "token", asset,
                fetcher=lambda _url, _token: (200, {}, payload),
            )

    def test_rejects_api_failure_and_unexpected_content_length(self):
        payload = b'{"metadata":"synthetic"}'
        asset = _asset(42, "build-metadata.json", payload)
        for response in ((503, {}, b"private body"), (200, {"Content-Length": "1"}, payload)):
            with self.subTest(response=response), self.assertRaises(ReleaseHistoryError):
                fetch_release_asset(
                    "https://api.github.com", "acme/private-releases", "token", asset,
                    fetcher=lambda _url, _token: response,
                )


if __name__ == "__main__":
    unittest.main(verbosity=2)
