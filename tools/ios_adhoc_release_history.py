#!/usr/bin/env python3
"""Fail-closed build-number validation against private GitHub release history."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
from dataclasses import dataclass
from typing import Any, Callable
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qs, quote, urlencode, urljoin, urlsplit, urlunsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener


MAX_BUILD_NUMBER = 2_147_483_647
PAGE_SIZE = 100
MAX_PAGES = 10_000
MAX_RESPONSE_BYTES = 16 * 1024 * 1024
MAX_ASSET_BYTES = 1024 * 1024
TRUSTED_ASSET_REDIRECT_HOSTS = frozenset({
    "github-releases.githubusercontent.com",
    "objects.githubusercontent.com",
    "release-assets.githubusercontent.com",
})
REPOSITORY_PATTERN = re.compile(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+")
VERSION_PATTERN = r"[0-9]+\.[0-9]+\.[0-9]+"
NAME_PATTERN = re.compile(
    rf"Theresian's Quest (?P<version>{VERSION_PATTERN}) "
    r"\((?P<build>[1-9][0-9]*)\) Ad Hoc"
)
TAG_PATTERN = re.compile(
    rf"adhoc-v(?P<version>{VERSION_PATTERN})-build"
    r"(?P<build>[1-9][0-9]*)-(?P<commit>[0-9a-f]{7})"
)
BODY_VERSION_PATTERN = re.compile(
    rf"^Version: (?P<version>{VERSION_PATTERN}) "
    r"\((?P<build>[1-9][0-9]*)\)$",
    re.MULTILINE,
)
BODY_COMMIT_PATTERN = re.compile(r"^Source commit: (?P<commit>[0-9a-f]{40})$", re.MULTILINE)
SHA256_PATTERN = re.compile(r"sha256:([0-9a-f]{64})")
HEX_SHA256_PATTERN = re.compile(r"[0-9a-f]{64}")
METADATA_FIELDS = frozenset({
    "repository",
    "source_commit",
    "godot_version",
    "marketing_version",
    "build_number",
    "bundle_id",
    "team_id",
    "minimum_ios_version",
    "distribution",
})
BUILD_REPORT_FIELDS = frozenset({
    "source_commit",
    "godot_version",
    "xcode_version",
    "ios_sdk",
    "bundle_id",
    "team_id",
    "marketing_version",
    "build_number",
    "minimum_ios_version",
    "architecture",
    "godot_engine",
    "distribution",
    "registered_device_count",
    "pck_sha256",
    "privacy_manifest_sha256",
    "ipa_file",
    "ipa_size_bytes",
    "ipa_sha256",
})
EXPECTED_METADATA_FIELD_VALUES = {
    "godot_version": "4.6.1",
    "distribution": "ad-hoc",
}


class ReleaseHistoryError(ValueError):
    """The private release history cannot safely reserve a new build number."""


@dataclass(frozen=True)
class ParsedRelease:
    index: int
    raw: dict[str, Any]
    release_id: int
    version: str
    build: int
    tag: str
    source_commit: str
    draft: bool


def _parse_build_number(value: str | int) -> int:
    text = str(value)
    if not re.fullmatch(r"[1-9][0-9]*", text):
        raise ReleaseHistoryError("Proposed build number must be a canonical positive decimal integer.")
    if len(text) > 10:
        raise ReleaseHistoryError("Proposed build number exceeds Apple's supported integer limit.")
    number = int(text, 10)
    if number > MAX_BUILD_NUMBER:
        raise ReleaseHistoryError("Proposed build number exceeds Apple's supported integer limit.")
    return number


def _parse_record_build(value: str, index: int) -> int:
    if len(value) > 10:
        raise ReleaseHistoryError(f"Release history entry {index} has an unsupported build number.")
    build = int(value, 10)
    if build > MAX_BUILD_NUMBER:
        raise ReleaseHistoryError(f"Release history entry {index} has an unsupported build number.")
    return build


def _required_int(value: Any, field: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value < 1:
        raise ReleaseHistoryError(f"Release history contains a malformed {field}.")
    return value


def _parse_release(release: Any, index: int) -> ParsedRelease:
    if not isinstance(release, dict):
        raise ReleaseHistoryError(f"Release history entry {index} is not an object.")

    release_id = _required_int(release.get("id"), "release ID")
    name = release.get("name")
    tag = release.get("tag_name")
    body = release.get("body")
    if not isinstance(name, str) or not isinstance(tag, str) or not isinstance(body, str):
        raise ReleaseHistoryError(f"Release history entry {index} has missing identity or provenance fields.")

    name_match = NAME_PATTERN.fullmatch(name)
    tag_match = TAG_PATTERN.fullmatch(tag)
    if not name_match or not tag_match:
        raise ReleaseHistoryError(
            f"Release history entry {index} does not match the required Ad Hoc release naming contract."
        )

    name_version = name_match.group("version")
    name_build = _parse_record_build(name_match.group("build"), index)
    tag_version = tag_match.group("version")
    tag_build = _parse_record_build(tag_match.group("build"), index)
    if (name_version, name_build) != (tag_version, tag_build):
        raise ReleaseHistoryError(f"Release history entry {index} has inconsistent name and tag metadata.")
    if name_build > MAX_BUILD_NUMBER:
        raise ReleaseHistoryError(f"Release history entry {index} has an unsupported build number.")

    versions = BODY_VERSION_PATTERN.findall(body)
    commits = BODY_COMMIT_PATTERN.findall(body)
    if len(versions) != 1 or len(commits) != 1:
        raise ReleaseHistoryError(f"Release history entry {index} has malformed or ambiguous body metadata.")
    body_version = versions[0][0]
    body_build = _parse_record_build(versions[0][1], index)
    if (body_version, body_build) != (name_version, name_build):
        raise ReleaseHistoryError(f"Release history entry {index} has inconsistent body metadata.")
    source_commit = commits[0]
    if not source_commit.startswith(tag_match.group("commit")):
        raise ReleaseHistoryError(f"Release history entry {index} has inconsistent source-commit metadata.")

    if not isinstance(release.get("draft"), bool):
        raise ReleaseHistoryError(f"Release history entry {index} has no trustworthy draft state.")
    if not isinstance(release.get("prerelease"), bool) or release["prerelease"] is not True:
        raise ReleaseHistoryError(f"Release history entry {index} is not marked as an Ad Hoc prerelease.")

    return ParsedRelease(
        index=index,
        raw=release,
        release_id=release_id,
        version=name_version,
        build=name_build,
        tag=tag,
        source_commit=source_commit,
        draft=release["draft"],
    )


def _asset_digest(asset: dict[str, Any], index: int, name: str) -> str:
    digest = asset.get("digest")
    match = SHA256_PATTERN.fullmatch(digest) if isinstance(digest, str) else None
    if not match:
        raise ReleaseHistoryError(
            f"Release history entry {index} asset {name!r} has no usable SHA-256 digest."
        )
    return match.group(1)


def _asset_size(asset: dict[str, Any], index: int, name: str) -> int:
    size = asset.get("size")
    if isinstance(size, bool) or not isinstance(size, int) or size < 1:
        raise ReleaseHistoryError(
            f"Release history entry {index} asset {name!r} has a missing or invalid positive size."
        )
    return size


def _required_assets(release: ParsedRelease) -> tuple[dict[str, Any], dict[str, Any], dict[str, Any]]:
    assets = release.raw.get("assets")
    if not isinstance(assets, list):
        raise ReleaseHistoryError(f"Release history entry {release.index} has malformed asset metadata.")
    if release.draft and not assets:
        raise ReleaseHistoryError(
            f"Draft release history entry {release.index} is incomplete; inspect and resolve it manually before signing."
        )

    folded_names: set[str] = set()
    asset_ids: set[int] = set()
    for asset in assets:
        if not isinstance(asset, dict):
            raise ReleaseHistoryError(f"Release history entry {release.index} has malformed asset metadata.")
        name = asset.get("name")
        if (
            not isinstance(name, str)
            or not name
            or name != name.strip()
            or "/" in name
            or "\\" in name
        ):
            raise ReleaseHistoryError(f"Release history entry {release.index} has malformed asset metadata.")
        if name.casefold() in folded_names:
            raise ReleaseHistoryError(
                f"Release history entry {release.index} contains ambiguous or duplicate asset names."
            )
        folded_names.add(name.casefold())
        asset_id = _required_int(asset.get("id"), "asset ID")
        if asset_id in asset_ids:
            raise ReleaseHistoryError(
                f"Release history entry {release.index} contains a duplicate asset ID."
            )
        asset_ids.add(asset_id)
        if asset.get("state") != "uploaded":
            status = "draft" if release.draft else "published"
            raise ReleaseHistoryError(
                f"{status.title()} release history entry {release.index} contains an asset that is not uploaded."
            )
        _asset_size(asset, release.index, name)

    ipa_assets = [asset for asset in assets if asset["name"].casefold().endswith(".ipa")]
    metadata_assets = [asset for asset in assets if asset["name"].casefold() == "build-metadata.json"]
    report_assets = [
        asset for asset in assets if asset["name"].casefold() == "ios-adhoc-build-report.txt"
    ]
    if len(ipa_assets) != 1 or len(metadata_assets) != 1 or len(report_assets) != 1:
        status = "draft" if release.draft else "published"
        raise ReleaseHistoryError(
            f"{status.title()} release history entry {release.index} lacks one unambiguous IPA, "
            "build-metadata.json, or ios-adhoc-build-report.txt asset."
        )
    for asset, expected_name in (
        (metadata_assets[0], "build-metadata.json"),
        (report_assets[0], "ios-adhoc-build-report.txt"),
    ):
        if asset["name"] != expected_name:
            raise ReleaseHistoryError(
                f"Release history entry {release.index} has an unexpected asset name for {expected_name}."
            )
    return ipa_assets[0], metadata_assets[0], report_assets[0]


def _reject_duplicate_json_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ReleaseHistoryError("Release build-metadata.json contains a duplicate field.")
        result[key] = value
    return result


def _reject_json_constant(_value: str) -> None:
    raise ReleaseHistoryError("Release build-metadata.json contains a non-standard JSON value.")


def _verified_asset_bytes(
    release: ParsedRelease,
    asset: dict[str, Any],
    asset_loader: Callable[[dict[str, Any], dict[str, Any]], bytes],
) -> bytes:
    name = asset["name"]
    expected_size = _asset_size(asset, release.index, name)
    expected_digest = _asset_digest(asset, release.index, name)
    if expected_size > MAX_ASSET_BYTES:
        raise ReleaseHistoryError(
            f"Release history entry {release.index} asset {name!r} exceeds the safe download limit."
        )
    try:
        content = asset_loader(release.raw, asset)
    except Exception:
        # Hide URLs, signed redirect queries, response bodies, and credentials from errors.
        raise ReleaseHistoryError(
            f"Release history entry {release.index} asset {name!r} could not be retrieved safely."
        ) from None
    if not isinstance(content, bytes) or len(content) > MAX_ASSET_BYTES:
        raise ReleaseHistoryError(
            f"Release history entry {release.index} asset {name!r} returned an invalid or oversized download."
        )
    if len(content) != expected_size:
        raise ReleaseHistoryError(
            f"Release history entry {release.index} asset {name!r} size does not match the API record."
        )
    if hashlib.sha256(content).hexdigest() != expected_digest:
        raise ReleaseHistoryError(
            f"Release history entry {release.index} asset {name!r} SHA-256 does not match the API digest."
        )
    return content


def _decode_metadata(content: bytes, release: ParsedRelease) -> dict[str, Any]:
    try:
        text = content.decode("utf-8")
        payload = json.loads(
            text,
            object_pairs_hook=_reject_duplicate_json_keys,
            parse_constant=_reject_json_constant,
        )
    except ReleaseHistoryError:
        raise
    except (UnicodeDecodeError, json.JSONDecodeError, ValueError):
        raise ReleaseHistoryError(
            f"Release history entry {release.index} build-metadata.json is malformed."
        ) from None
    if not isinstance(payload, dict) or set(payload) != METADATA_FIELDS:
        raise ReleaseHistoryError(
            f"Release history entry {release.index} build-metadata.json does not match the publisher schema."
        )
    if any(not isinstance(value, str) for value in payload.values()):
        raise ReleaseHistoryError(
            f"Release history entry {release.index} build-metadata.json has malformed field types."
        )
    return payload


def _decode_build_report(content: bytes, release: ParsedRelease) -> dict[str, str]:
    try:
        text = content.decode("utf-8")
    except UnicodeDecodeError:
        raise ReleaseHistoryError(
            f"Release history entry {release.index} build report is not valid UTF-8."
        ) from None
    fields: dict[str, str] = {}
    for line in text.splitlines():
        if not line or "=" not in line:
            raise ReleaseHistoryError(
                f"Release history entry {release.index} build report is malformed."
            )
        key, value = line.split("=", 1)
        if not key or key in fields:
            raise ReleaseHistoryError(
                f"Release history entry {release.index} build report contains duplicate or empty fields."
            )
        fields[key] = value
    if set(fields) != BUILD_REPORT_FIELDS or any(not value for value in fields.values()):
        raise ReleaseHistoryError(
            f"Release history entry {release.index} build report does not match the publisher schema."
        )
    return fields


def _validate_release_assets(
    release: ParsedRelease,
    *,
    asset_loader: Callable[[dict[str, Any], dict[str, Any]], bytes],
    expected_repository: str,
    expected_bundle_id: str,
    expected_team_id: str,
    expected_minimum_ios_version: str,
) -> None:
    ipa_asset, metadata_asset, report_asset = _required_assets(release)
    ipa_digest = _asset_digest(ipa_asset, release.index, ipa_asset["name"])
    metadata_bytes = _verified_asset_bytes(release, metadata_asset, asset_loader)
    report_bytes = _verified_asset_bytes(release, report_asset, asset_loader)
    metadata = _decode_metadata(metadata_bytes, release)
    report = _decode_build_report(report_bytes, release)

    expected_metadata = {
        "repository": expected_repository,
        "source_commit": release.source_commit,
        "godot_version": EXPECTED_METADATA_FIELD_VALUES["godot_version"],
        "marketing_version": release.version,
        "build_number": str(release.build),
        "bundle_id": expected_bundle_id,
        "team_id": expected_team_id,
        "minimum_ios_version": expected_minimum_ios_version,
        "distribution": EXPECTED_METADATA_FIELD_VALUES["distribution"],
    }
    if metadata != expected_metadata:
        raise ReleaseHistoryError(
            f"Release history entry {release.index} build-metadata.json conflicts with release identity, "
            "tag, source commit, or the protected publisher configuration."
        )

    expected_report = {
        "source_commit": release.source_commit,
        "godot_version": EXPECTED_METADATA_FIELD_VALUES["godot_version"],
        "bundle_id": expected_bundle_id,
        "team_id": expected_team_id,
        "marketing_version": release.version,
        "build_number": str(release.build),
        "minimum_ios_version": expected_minimum_ios_version,
        "architecture": "arm64",
        "godot_engine": "Release",
        "distribution": "Ad Hoc",
        "ipa_file": ipa_asset["name"],
        "ipa_size_bytes": str(_asset_size(ipa_asset, release.index, ipa_asset["name"])),
        "ipa_sha256": ipa_digest,
    }
    if any(report[field] != value for field, value in expected_report.items()):
        raise ReleaseHistoryError(
            f"Release history entry {release.index} build report conflicts with the IPA or release identity."
        )
    for field in ("pck_sha256", "privacy_manifest_sha256"):
        if not HEX_SHA256_PATTERN.fullmatch(report[field]):
            raise ReleaseHistoryError(
                f"Release history entry {release.index} build report has an invalid {field}."
            )
    if not re.fullmatch(r"[1-9][0-9]*", report["registered_device_count"]):
        raise ReleaseHistoryError(
            f"Release history entry {release.index} build report has an invalid device count."
        )


def validate_release_history(
    proposed_build: str | int,
    releases: Any,
    *,
    asset_loader: Callable[[dict[str, Any], dict[str, Any]], bytes] | None = None,
    expected_repository: str | None = None,
    expected_bundle_id: str | None = None,
    expected_team_id: str | None = None,
    expected_minimum_ios_version: str | None = None,
) -> int:
    """Validate every draft and published record before reserving a new build."""
    proposed = _parse_build_number(proposed_build)
    if not isinstance(releases, list):
        raise ReleaseHistoryError("Private release history response is not a release list.")

    release_ids: set[int] = set()
    release_tags: set[str] = set()
    build_numbers: set[int] = set()
    parsed_releases: list[ParsedRelease] = []
    for index, release in enumerate(releases, start=1):
        parsed = _parse_release(release, index)
        if parsed.release_id in release_ids:
            raise ReleaseHistoryError("Private release history contains a duplicate release ID.")
        if parsed.tag in release_tags:
            raise ReleaseHistoryError("Private release history contains a duplicate release tag.")
        if parsed.build in build_numbers:
            raise ReleaseHistoryError("Private release history contains a duplicate build number.")
        release_ids.add(parsed.release_id)
        release_tags.add(parsed.tag)
        build_numbers.add(parsed.build)
        parsed_releases.append(parsed)

    if parsed_releases:
        if not callable(asset_loader):
            raise ReleaseHistoryError("Private release history assets cannot be verified safely.")
        expected_values = (
            expected_repository,
            expected_bundle_id,
            expected_team_id,
            expected_minimum_ios_version,
        )
        if any(not isinstance(value, str) or not value for value in expected_values):
            raise ReleaseHistoryError("Protected source and iOS publisher identity are unavailable.")
        if not REPOSITORY_PATTERN.fullmatch(expected_repository or ""):
            raise ReleaseHistoryError("Protected source repository identity is malformed.")
        for parsed in parsed_releases:
            _validate_release_assets(
                parsed,
                asset_loader=asset_loader,
                expected_repository=expected_repository or "",
                expected_bundle_id=expected_bundle_id or "",
                expected_team_id=expected_team_id or "",
                expected_minimum_ios_version=expected_minimum_ios_version or "",
            )

    highest = max(build_numbers, default=0)
    if proposed <= highest:
        raise ReleaseHistoryError(
            f"Proposed build number {proposed} must be greater than the highest private release build {highest}."
        )
    return highest


class _RejectRedirects(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):  # noqa: ANN001
        return None


def _http_fetch_page(url: str, token: str) -> tuple[int, dict[str, str], bytes]:
    request = Request(
        url,
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "Theresians-Quest-Ad-Hoc-release-history-check",
        },
    )
    opener = build_opener(_RejectRedirects())
    try:
        with opener.open(request, timeout=30) as response:
            status = response.status
            headers = dict(response.headers.items())
            body = response.read(MAX_RESPONSE_BYTES + 1)
    except HTTPError as error:
        # Do not include response bodies, URLs, or request headers in logs.
        raise ReleaseHistoryError(f"GitHub release-history API returned HTTP {error.code}.") from None
    except (URLError, TimeoutError, OSError):
        raise ReleaseHistoryError("GitHub release-history API request failed.") from None
    if len(body) > MAX_RESPONSE_BYTES:
        raise ReleaseHistoryError("GitHub release-history API response exceeded the safety limit.")
    return status, headers, body


def _header(headers: Any, name: str) -> str | None:
    if not isinstance(headers, dict):
        raise ReleaseHistoryError("GitHub release-history API returned malformed headers.")
    for key, value in headers.items():
        if isinstance(key, str) and key.lower() == name.lower():
            if not isinstance(value, str):
                raise ReleaseHistoryError("GitHub release-history API returned malformed headers.")
            return value
    return None


def _http_fetch_asset_response(url: str, token: str | None) -> tuple[int, dict[str, str], bytes]:
    headers = {
        "Accept": "application/octet-stream",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "Theresians-Quest-Ad-Hoc-release-history-check",
    }
    if token is not None:
        headers["Authorization"] = f"Bearer {token}"
    request = Request(url, headers=headers)
    opener = build_opener(_RejectRedirects())
    try:
        with opener.open(request, timeout=30) as response:
            status = response.status
            response_headers = dict(response.headers.items())
            content = response.read(MAX_ASSET_BYTES + 1)
    except HTTPError as error:
        if error.code in (301, 302, 303, 307, 308):
            # The caller validates Location and makes any asset-host request unauthenticated.
            return error.code, dict(error.headers.items()), b""
        raise ReleaseHistoryError(
            f"GitHub release asset API returned HTTP {error.code}."
        ) from None
    except (URLError, TimeoutError, OSError):
        raise ReleaseHistoryError("GitHub release asset API request failed.") from None
    if len(content) > MAX_ASSET_BYTES:
        raise ReleaseHistoryError("GitHub release asset exceeded the safe download limit.")
    return status, response_headers, content


def _trusted_asset_redirect(location: str, api_url: str) -> str | None:
    try:
        target = urljoin(api_url, location)
        target_parts = urlsplit(target)
        api_parts = urlsplit(api_url)
    except ValueError:
        return None
    if (
        target_parts.scheme != "https"
        or not target_parts.hostname
        or target_parts.username
        or target_parts.password
        or target_parts.fragment
    ):
        return None
    same_api_origin = (target_parts.scheme, target_parts.netloc) == (api_parts.scheme, api_parts.netloc)
    trusted_github_asset_host = (
        target_parts.hostname.lower() in TRUSTED_ASSET_REDIRECT_HOSTS
        and target_parts.port in (None, 443)
    )
    if same_api_origin or trusted_github_asset_host:
        return target
    return None


def fetch_release_asset(
    api_url: str,
    repository: str,
    token: str,
    asset: Any,
    *,
    fetcher: Callable[[str, str | None], tuple[int, Any, Any]] | None = None,
) -> bytes:
    """Download one small private release asset without forwarding auth on redirects."""
    if not isinstance(api_url, str) or not isinstance(repository, str) or not isinstance(token, str):
        raise ReleaseHistoryError("Private release asset API configuration is malformed.")
    try:
        api = urlsplit(api_url)
    except ValueError:
        raise ReleaseHistoryError("GitHub API URL is malformed.") from None
    if api.scheme != "https" or not api.hostname or api.username or api.password or api.query or api.fragment:
        raise ReleaseHistoryError("GitHub API URL must be an HTTPS API origin.")
    if not REPOSITORY_PATTERN.fullmatch(repository) or any(
        segment in (".", "..") for segment in repository.split("/")
    ):
        raise ReleaseHistoryError("Private release repository must use owner/repository format.")
    if not token.strip():
        raise ReleaseHistoryError("Private release-history token is missing.")
    if not isinstance(asset, dict):
        raise ReleaseHistoryError("Private release asset metadata is malformed.")
    asset_id = _required_int(asset.get("id"), "asset ID")
    asset_name = asset.get("name")
    if not isinstance(asset_name, str) or not asset_name:
        raise ReleaseHistoryError("Private release asset metadata is malformed.")
    if asset_name not in {"build-metadata.json", "ios-adhoc-build-report.txt"}:
        raise ReleaseHistoryError("Only the expected small release metadata assets can be downloaded.")
    if asset.get("state") != "uploaded":
        raise ReleaseHistoryError("Private release metadata asset is not uploaded.")
    asset_size = _asset_size(asset, 0, asset_name)
    asset_digest = _asset_digest(asset, 0, asset_name)
    if asset_size > MAX_ASSET_BYTES:
        raise ReleaseHistoryError("Private release metadata asset exceeds the safe download limit.")

    endpoint_path = f"{api.path.rstrip('/')}/repos/{quote(repository, safe='/')}/releases/assets/{asset_id}"
    request_url = urlunsplit((api.scheme, api.netloc, endpoint_path, "", ""))
    request_asset = fetcher or _http_fetch_asset_response
    try:
        status, headers, body = request_asset(request_url, token)
        if status == 302:
            location = _header(headers, "Location")
            trusted_url = _trusted_asset_redirect(location, api_url) if location else None
            if trusted_url is None:
                raise ReleaseHistoryError("GitHub release asset returned an untrusted redirect.")
            status, headers, body = request_asset(trusted_url, None)
        if status != 200:
            raise ReleaseHistoryError("GitHub release asset download returned an unexpected response.")
    except ReleaseHistoryError:
        raise
    except Exception:
        # Do not expose URLs, signed redirect queries, headers, response bodies, or tokens.
        raise ReleaseHistoryError("GitHub release asset download failed.") from None

    if not isinstance(body, bytes) or len(body) > MAX_ASSET_BYTES:
        raise ReleaseHistoryError("GitHub release asset returned an invalid or oversized download.")
    content_length = _header(headers, "Content-Length")
    if content_length is not None:
        if not re.fullmatch(r"[0-9]+", content_length) or int(content_length, 10) != len(body):
            raise ReleaseHistoryError("GitHub release asset content length is inconsistent.")
    if len(body) != asset_size:
        raise ReleaseHistoryError("GitHub release asset size does not match the API record.")
    if hashlib.sha256(body).hexdigest() != asset_digest:
        raise ReleaseHistoryError("GitHub release asset SHA-256 does not match the API digest.")
    return body


def _next_link(link_header: str | None) -> str | None:
    if link_header is None:
        return None
    links: list[tuple[str, str]] = []
    for item in link_header.split(","):
        match = re.fullmatch(r"\s*<([^<>]+)>\s*;(.*)\s*", item)
        if not match:
            raise ReleaseHistoryError("GitHub release-history pagination header is malformed.")
        target, parameters = match.groups()
        relations = []
        for parameter in parameters.split(";"):
            key, separator, value = parameter.strip().partition("=")
            if not separator:
                raise ReleaseHistoryError("GitHub release-history pagination header is malformed.")
            if key.strip().lower() == "rel":
                relations = value.strip().strip('"').split()
        if not relations:
            raise ReleaseHistoryError("GitHub release-history pagination relation is missing.")
        links.extend((target, relation.lower()) for relation in relations)
    next_links = [target for target, relation in links if relation == "next"]
    if len(next_links) > 1:
        raise ReleaseHistoryError("GitHub release-history pagination header has duplicate next links.")
    return next_links[0] if next_links else None


def _decode_release_page(body: Any) -> list[Any]:
    if isinstance(body, bytes):
        if len(body) > MAX_RESPONSE_BYTES:
            raise ReleaseHistoryError("GitHub release-history API response exceeded the safety limit.")
        try:
            body = body.decode("utf-8")
        except UnicodeDecodeError:
            raise ReleaseHistoryError("GitHub release-history API returned invalid JSON text.") from None
    if isinstance(body, str):
        try:
            body = json.loads(body)
        except (json.JSONDecodeError, ValueError):
            raise ReleaseHistoryError("GitHub release-history API returned invalid JSON.") from None
    if not isinstance(body, list):
        raise ReleaseHistoryError("GitHub release-history API did not return a release list.")
    if len(body) > PAGE_SIZE:
        raise ReleaseHistoryError("GitHub release-history API exceeded the requested page size.")
    return body


def fetch_release_history(
    api_url: str,
    repository: str,
    token: str,
    *,
    fetcher: Callable[[str, str], tuple[int, Any, Any]] | None = None,
) -> list[Any]:
    """Fetch all authenticated release pages; injected fetchers keep tests offline."""
    if not isinstance(api_url, str) or not isinstance(repository, str) or not isinstance(token, str):
        raise ReleaseHistoryError("Private release-history API configuration is malformed.")
    try:
        api = urlsplit(api_url)
    except ValueError:
        raise ReleaseHistoryError("GitHub API URL is malformed.") from None
    if api.scheme != "https" or not api.hostname or api.username or api.password or api.query or api.fragment:
        raise ReleaseHistoryError("GitHub API URL must be a root HTTPS API origin.")
    if not REPOSITORY_PATTERN.fullmatch(repository) or any(
        segment in (".", "..") for segment in repository.split("/")
    ):
        raise ReleaseHistoryError("Private release repository must use owner/repository format.")
    if not token.strip():
        raise ReleaseHistoryError("Private release-history token is missing.")

    api_path = api.path.rstrip("/")
    endpoint_path = f"{api_path}/repos/{quote(repository, safe='/')}/releases"
    origin = (api.scheme, api.netloc)
    request_page = fetcher or _http_fetch_page
    releases: list[Any] = []
    page_number = 1

    while page_number <= MAX_PAGES:
        query = urlencode({"per_page": PAGE_SIZE, "page": page_number})
        request_url = urlunsplit((api.scheme, api.netloc, endpoint_path, query, ""))
        try:
            status, headers, raw_body = request_page(request_url, token)
        except ReleaseHistoryError:
            raise
        except Exception:
            raise ReleaseHistoryError("GitHub release-history API request failed.") from None
        if status != 200:
            raise ReleaseHistoryError(f"GitHub release-history API returned HTTP {status}.")
        records = _decode_release_page(raw_body)
        if not records:
            if _next_link(_header(headers, "Link")) is not None:
                raise ReleaseHistoryError("GitHub release-history pagination is inconsistent.")
            return releases
        releases.extend(records)

        next_url = _next_link(_header(headers, "Link"))
        if len(records) < PAGE_SIZE:
            if next_url is not None:
                raise ReleaseHistoryError("GitHub release-history pagination is inconsistent.")
            return releases
        if next_url is None:
            # A full page may be the exact end of the collection. Probe the next
            # page explicitly so a missing Link header cannot silently truncate it.
            page_number += 1
            continue
        try:
            next_parts = urlsplit(next_url)
            next_query = parse_qs(next_parts.query, strict_parsing=True)
        except ValueError:
            raise ReleaseHistoryError("GitHub release-history next page is malformed.") from None
        if (
            (next_parts.scheme, next_parts.netloc) != origin
            or next_parts.path != endpoint_path
            or next_parts.fragment
            or next_parts.username
            or next_parts.password
            or set(next_query) != {"per_page", "page"}
            or next_query.get("per_page") != [str(PAGE_SIZE)]
            or next_query.get("page") != [str(page_number + 1)]
        ):
            raise ReleaseHistoryError("GitHub release-history next page is not the expected repository page.")
        page_number += 1

    raise ReleaseHistoryError("GitHub release-history exceeded the maximum safe page count.")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("build_number", help="Proposed positive CFBundleVersion")
    args = parser.parse_args(argv)

    token = os.environ.get("IOS_ADHOC_RELEASE_TOKEN", "")
    repository = os.environ.get("IOS_ADHOC_RELEASE_REPOSITORY", "")
    api_url = os.environ.get("GITHUB_API_URL", "")
    source_repository = os.environ.get("GITHUB_REPOSITORY", "")
    bundle_id = os.environ.get("IOS_BUNDLE_ID", "")
    team_id = os.environ.get("IOS_TEAM_ID", "")
    minimum_ios_version = os.environ.get("IOS_MIN_IOS_VERSION", "")
    try:
        releases = fetch_release_history(api_url, repository, token)
        highest = validate_release_history(
            args.build_number,
            releases,
            asset_loader=lambda _release, asset: fetch_release_asset(
                api_url, repository, token, asset
            ),
            expected_repository=source_repository,
            expected_bundle_id=bundle_id,
            expected_team_id=team_id,
            expected_minimum_ios_version=minimum_ios_version,
        )
    except ReleaseHistoryError as error:
        print(f"::error::Ad Hoc release-history validation failed: {error}", file=sys.stderr)
        return 1
    proposed = int(args.build_number, 10)
    print(
        f"Validated {len(releases)} private release record(s); highest build is {highest}; "
        f"proposed build {proposed} is strictly higher."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
