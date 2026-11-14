#!/usr/bin/env python3
"""Fail-closed build-number validation for the private Ad Hoc release history."""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from typing import Any, Callable
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlencode, urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener


PAGE_SIZE = 100
MAX_PAGES = 1000
MAX_PAGE_BYTES = 8 * 1024 * 1024
MAX_METADATA_BYTES = 64 * 1024
MAX_BUILD_NUMBER = 2_147_483_647
VERSION_RE = re.compile(r"[0-9]+\.[0-9]+\.[0-9]+\Z")
TAG_RE = re.compile(
    r"adhoc-v(?P<version>[0-9]+\.[0-9]+\.[0-9]+)-build"
    r"(?P<build>[1-9][0-9]*)-(?P<commit_prefix>[0-9a-f]{7})\Z"
)


class ReleaseHistoryError(ValueError):
    """The destination release history is incomplete or inconsistent."""


def _positive_integer(value: Any, description: str) -> int:
    if isinstance(value, bool):
        raise ReleaseHistoryError(f"{description} must be a positive integer.")
    if isinstance(value, int):
        number = value
        text = str(value)
    elif isinstance(value, str) and re.fullmatch(r"[1-9][0-9]*", value):
        number = int(value)
        text = value
    else:
        raise ReleaseHistoryError(f"{description} must be a canonical positive integer.")
    if number < 1 or number > MAX_BUILD_NUMBER or text != str(number):
        raise ReleaseHistoryError(f"{description} is outside the supported range.")
    return number


def _validate_assets(release: dict[str, Any], label: str) -> None:
    assets = release.get("assets")
    if not isinstance(assets, list):
        raise ReleaseHistoryError(f"{label} has no trustworthy release-asset inventory.")

    ids: set[int] = set()
    names: set[str] = set()
    ipa_count = 0
    for asset in assets:
        if not isinstance(asset, dict):
            raise ReleaseHistoryError(f"{label} contains malformed release asset metadata.")
        asset_id = asset.get("id")
        if isinstance(asset_id, bool) or not isinstance(asset_id, int) or asset_id < 1 or asset_id in ids:
            raise ReleaseHistoryError(f"{label} contains an invalid or duplicate asset ID.")
        ids.add(asset_id)
        name = asset.get("name")
        if not isinstance(name, str) or not name or name in names:
            raise ReleaseHistoryError(f"{label} contains a missing or duplicate asset name.")
        names.add(name)
        size = asset.get("size")
        if isinstance(size, bool) or not isinstance(size, int) or size < 1:
            raise ReleaseHistoryError(f"{label} contains an empty or invalid release asset.")
        if asset.get("state") != "uploaded":
            raise ReleaseHistoryError(f"{label} contains an asset that is not fully uploaded.")
        if name.lower().endswith(".ipa"):
            ipa_count += 1

    required_assets = {"build-metadata.json", "ios-adhoc-build-report.txt", "CHANGELOG.md"}
    missing = required_assets - names
    if missing or ipa_count != 1:
        raise ReleaseHistoryError(f"{label} is incomplete or has an ambiguous IPA asset.")


def _validate_release(release: Any, position: int) -> tuple[int, int, str, int, str, str]:
    label = f"release entry {position}"
    if not isinstance(release, dict):
        raise ReleaseHistoryError(f"{label} is not an object.")

    release_id = release.get("id")
    if isinstance(release_id, bool) or not isinstance(release_id, int) or release_id < 1:
        raise ReleaseHistoryError(f"{label} has a missing or invalid release ID.")

    tag = release.get("tag_name")
    if not isinstance(tag, str):
        raise ReleaseHistoryError(f"{label} has a missing release tag.")
    match = TAG_RE.fullmatch(tag)
    if not match:
        raise ReleaseHistoryError(f"{label} has a malformed Ad Hoc release tag.")
    version = match.group("version")
    build_text = match.group("build")
    build = _positive_integer(build_text, f"{label} build number")
    source_prefix = match.group("commit_prefix")

    name = release.get("name")
    expected_name = f"Theresian's Quest {version} ({build}) Ad Hoc"
    if name != expected_name:
        raise ReleaseHistoryError(f"{label} name does not match its release tag.")
    if release.get("prerelease") is not True:
        raise ReleaseHistoryError(f"{label} is not marked as an Ad Hoc prerelease.")
    if not isinstance(release.get("draft"), bool):
        raise ReleaseHistoryError(f"{label} has no trustworthy draft status.")

    body = release.get("body")
    if not isinstance(body, str):
        raise ReleaseHistoryError(f"{label} has no trustworthy release metadata body.")
    source_lines = re.findall(r"(?m)^Source commit: ([0-9a-f]{40})\s*$", body)
    version_lines = re.findall(r"(?m)^Version: ([0-9]+\.[0-9]+\.[0-9]+) \(([1-9][0-9]*)\)\s*$", body)
    if len(source_lines) != 1 or len(version_lines) != 1:
        raise ReleaseHistoryError(f"{label} has missing or ambiguous source/version metadata.")
    source_commit = source_lines[0]
    if source_commit[:7] != source_prefix:
        raise ReleaseHistoryError(f"{label} tag and source commit do not match.")
    body_version, body_build_text = version_lines[0]
    body_build = _positive_integer(body_build_text, f"{label} body build number")
    if body_version != version or body_build != build:
        raise ReleaseHistoryError(f"{label} tag, name, and body disagree.")
    _validate_assets(release, label)
    metadata_asset = next(asset for asset in release["assets"] if asset["name"] == "build-metadata.json")
    return release_id, build, tag, metadata_asset["id"], source_commit, version


def validate_release_history(
    releases: list[Any],
    candidate_build: str | int,
    *,
    metadata_by_asset_id: dict[int, bytes | str],
) -> tuple[int, int]:
    """Validate every draft/published release and require a strictly higher candidate."""
    candidate = _positive_integer(candidate_build, "Proposed build number")
    if not isinstance(releases, list):
        raise ReleaseHistoryError("GitHub release history response is not a list.")
    if not isinstance(metadata_by_asset_id, dict):
        raise ReleaseHistoryError("Downloaded release metadata inventory is malformed.")

    release_ids: set[int] = set()
    release_tags: set[str] = set()
    build_numbers: set[int] = set()
    asset_ids: set[int] = set()
    highest = 0
    for position, release in enumerate(releases, start=1):
        release_id, build, tag, metadata_asset_id, source_commit, version = _validate_release(release, position)
        if release_id in release_ids:
            raise ReleaseHistoryError("Release history contains a duplicate release ID.")
        if tag in release_tags:
            raise ReleaseHistoryError("Release history contains a duplicate release tag.")
        if build in build_numbers:
            raise ReleaseHistoryError("Release history contains a reused build number.")
        release_ids.add(release_id)
        release_tags.add(tag)
        build_numbers.add(build)
        highest = max(highest, build)
        current_asset_ids = {asset["id"] for asset in release["assets"]}
        if asset_ids.intersection(current_asset_ids):
            raise ReleaseHistoryError("Release history contains an asset ID reused across releases.")
        asset_ids.update(current_asset_ids)
        metadata_bytes = metadata_by_asset_id.get(metadata_asset_id)
        if not isinstance(metadata_bytes, (bytes, str)):
            raise ReleaseHistoryError(f"release entry {position} metadata asset could not be verified.")
        if len(metadata_bytes) > MAX_METADATA_BYTES:
            raise ReleaseHistoryError(f"release entry {position} metadata asset exceeds the size limit.")
        try:
            metadata = json.loads(metadata_bytes)
        except (json.JSONDecodeError, UnicodeDecodeError):
            raise ReleaseHistoryError(f"release entry {position} metadata asset is malformed.") from None
        if not isinstance(metadata, dict):
            raise ReleaseHistoryError(f"release entry {position} metadata asset is not an object.")
        if (
            metadata.get("source_commit") != source_commit
            or metadata.get("marketing_version") != version
            or metadata.get("build_number") != str(build)
            or metadata.get("bundle_id") != "com.theresiansquest.game"
            or metadata.get("distribution") != "ad-hoc"
        ):
            raise ReleaseHistoryError(f"release entry {position} metadata asset contradicts the release record.")

    if candidate <= highest:
        raise ReleaseHistoryError(
            f"Proposed build {candidate} must exceed the highest verified release build {highest}."
        )
    return len(releases), highest


def collect_release_pages(
    fetch_page: Callable[[int, int], Any],
    *,
    page_size: int = PAGE_SIZE,
    max_pages: int = MAX_PAGES,
) -> list[Any]:
    """Collect every release page; malformed, truncated, or unavailable pages fail closed."""
    if isinstance(page_size, bool) or not isinstance(page_size, int) or not 1 <= page_size <= PAGE_SIZE:
        raise ReleaseHistoryError("Release-history page size is invalid.")
    if isinstance(max_pages, bool) or not isinstance(max_pages, int) or max_pages < 1:
        raise ReleaseHistoryError("Release-history page limit is invalid.")

    releases: list[Any] = []
    for page_number in range(1, max_pages + 1):
        try:
            page = fetch_page(page_number, page_size)
        except Exception as error:  # noqa: BLE001 - API errors must stop the release.
            if isinstance(error, ReleaseHistoryError):
                raise
            raise ReleaseHistoryError(f"GitHub release-history request failed on page {page_number}.") from None
        if not isinstance(page, list) or len(page) > page_size:
            raise ReleaseHistoryError(f"GitHub release-history page {page_number} is malformed.")
        releases.extend(page)
        if len(page) < page_size:
            return releases
    raise ReleaseHistoryError("Release history exceeds the configured pagination safety limit.")


class _RejectRedirects(HTTPRedirectHandler):
    def redirect_request(self, request, file_pointer, code, message, headers, new_url):  # noqa: ANN001
        return None


def _fetch_page(api_base: str, repository: str, token: str, page: int, per_page: int) -> list[Any]:
    owner, name = repository.split("/", 1)
    endpoint = (
        f"{api_base.rstrip('/')}/repos/{quote(owner, safe='')}/{quote(name, safe='')}/releases?"
        f"{urlencode({'per_page': per_page, 'page': page})}"
    )
    request = Request(
        endpoint,
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "TheresiansQuest-AdHoc-Release-Preflight",
        },
    )
    opener = build_opener(_RejectRedirects)
    try:
        response = opener.open(request, timeout=30)
        with response:
            if response.status != 200:
                raise ReleaseHistoryError(
                    f"GitHub release-history request failed on page {page} (HTTP {response.status})."
                )
            content_length = response.headers.get("Content-Length")
            if content_length and int(content_length) > MAX_PAGE_BYTES:
                raise ReleaseHistoryError(f"GitHub release-history page {page} exceeds the size limit.")
            payload = response.read(MAX_PAGE_BYTES + 1)
    except HTTPError as error:
        raise ReleaseHistoryError(
            f"GitHub release-history request failed on page {page} (HTTP {error.code})."
        ) from None
    except (URLError, TimeoutError, OSError, ValueError):
        raise ReleaseHistoryError(f"GitHub release-history request failed on page {page}.") from None

    if len(payload) > MAX_PAGE_BYTES:
        raise ReleaseHistoryError(f"GitHub release-history page {page} exceeds the size limit.")
    try:
        data = json.loads(payload)
    except (json.JSONDecodeError, UnicodeDecodeError):
        raise ReleaseHistoryError(f"GitHub release-history page {page} is not valid JSON.") from None
    if not isinstance(data, list):
        raise ReleaseHistoryError(f"GitHub release-history page {page} is not a list.")
    return data


def _download_metadata_asset(api_base: str, repository: str, token: str, asset_id: int) -> bytes:
    owner, name = repository.split("/", 1)
    endpoint = (
        f"{api_base.rstrip('/')}/repos/{quote(owner, safe='')}/{quote(name, safe='')}"
        f"/releases/assets/{asset_id}"
    )
    request = Request(
        endpoint,
        headers={
            "Accept": "application/octet-stream",
            "Authorization": f"Bearer {token}",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "TheresiansQuest-AdHoc-Release-Preflight",
        },
    )
    opener = build_opener(_RejectRedirects)
    try:
        response = opener.open(request, timeout=30)
    except HTTPError as error:
        if error.code not in {301, 302, 303, 307, 308}:
            raise ReleaseHistoryError(
                f"GitHub release metadata request failed (HTTP {error.code})."
            ) from None
        location = error.headers.get("Location", "")
        error.close()
        try:
            redirect = urlsplit(location)
            redirect_port = redirect.port
        except ValueError:
            raise ReleaseHistoryError("GitHub returned an untrusted metadata-asset download location.") from None
        host = (redirect.hostname or "").lower()
        if (
            redirect.scheme != "https"
            or redirect.username
            or redirect.password
            or redirect_port not in (None, 443)
            or redirect.fragment
            or not (host == "githubusercontent.com" or host.endswith(".githubusercontent.com"))
            or not redirect.query
        ):
            raise ReleaseHistoryError("GitHub returned an untrusted metadata-asset download location.") from None
        # The short-lived CDN URL is a capability. Never forward the GitHub token to it.
        request = Request(
            location,
            headers={
                "Accept": "application/octet-stream",
                "User-Agent": "TheresiansQuest-AdHoc-Release-Preflight",
            },
        )
        try:
            response = opener.open(request, timeout=30)
        except (HTTPError, URLError, TimeoutError, OSError):
            raise ReleaseHistoryError("GitHub release metadata asset download failed.") from None
    except (URLError, TimeoutError, OSError):
        raise ReleaseHistoryError("GitHub release metadata request failed.") from None

    with response:
        if response.status != 200:
            raise ReleaseHistoryError("GitHub release metadata asset did not return HTTP 200.")
        content_length = response.headers.get("Content-Length")
        try:
            if content_length and int(content_length) > MAX_METADATA_BYTES:
                raise ReleaseHistoryError("Release metadata asset exceeds the size limit.")
        except ValueError:
            raise ReleaseHistoryError("Release metadata asset has an invalid content length.") from None
        payload = response.read(MAX_METADATA_BYTES + 1)
    if len(payload) > MAX_METADATA_BYTES:
        raise ReleaseHistoryError("Release metadata asset exceeds the size limit.")
    return payload


def fetch_release_history(api_base: str, repository: str, token: str) -> tuple[list[Any], dict[int, bytes]]:
    try:
        parsed = urlsplit(api_base)
        api_port = parsed.port
    except ValueError:
        raise ReleaseHistoryError("GitHub API base URL is malformed.") from None
    if (
        parsed.scheme != "https"
        or (parsed.hostname or "").lower() != "api.github.com"
        or api_port not in (None, 443)
        or parsed.username
        or parsed.password
        or parsed.path not in ("", "/")
        or parsed.query
        or parsed.fragment
    ):
        raise ReleaseHistoryError("GitHub API base must be the official HTTPS api.github.com origin.")
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository):
        raise ReleaseHistoryError("Private release repository must use owner/repository format.")
    if any(part in {".", ".."} for part in repository.split("/")):
        raise ReleaseHistoryError("Private release repository path is invalid.")
    if not token or "\r" in token or "\n" in token:
        raise ReleaseHistoryError("A valid private release token is required.")
    api_base = api_base.rstrip("/")
    releases = collect_release_pages(
        lambda page, size: _fetch_page(api_base, repository, token, page, size)
    )
    metadata_by_asset_id: dict[int, bytes] = {}
    for position, release in enumerate(releases, start=1):
        if not isinstance(release, dict) or not isinstance(release.get("assets"), list):
            raise ReleaseHistoryError(f"release entry {position} has no trustworthy asset inventory.")
        metadata_assets = [
            asset for asset in release["assets"]
            if isinstance(asset, dict) and asset.get("name") == "build-metadata.json"
        ]
        if len(metadata_assets) != 1:
            raise ReleaseHistoryError(f"release entry {position} has no unique build metadata asset.")
        asset_id = metadata_assets[0].get("id")
        if isinstance(asset_id, bool) or not isinstance(asset_id, int) or asset_id < 1:
            raise ReleaseHistoryError(f"release entry {position} has an invalid metadata asset ID.")
        metadata_by_asset_id[asset_id] = _download_metadata_asset(api_base, repository, token, asset_id)
    return releases, metadata_by_asset_id


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", required=True, help="Private release destination as owner/repository")
    parser.add_argument("--marketing-version", required=True)
    parser.add_argument("--build-number", required=True)
    args = parser.parse_args(argv)

    try:
        if not VERSION_RE.fullmatch(args.marketing_version):
            raise ReleaseHistoryError("Marketing version must use major.minor.patch format.")
        candidate = _positive_integer(args.build_number, "Proposed build number")
        api_base = os.environ.get("GITHUB_API_URL", "")
        token = os.environ.get("IOS_ADHOC_RELEASE_TOKEN", "")
        releases, metadata_by_asset_id = fetch_release_history(api_base, args.repository, token)
        count, highest = validate_release_history(
            releases,
            candidate,
            metadata_by_asset_id=metadata_by_asset_id,
        )
    except ReleaseHistoryError as error:
        print(f"::error::{error}", file=sys.stderr)
        return 1
    print(
        f"Verified {count} complete private Ad Hoc release(s); "
        f"proposed build {candidate} exceeds highest existing build {highest}."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
