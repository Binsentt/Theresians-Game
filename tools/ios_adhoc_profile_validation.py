#!/usr/bin/env python3
"""Fail-closed validation for an Apple Ad Hoc provisioning profile."""

from __future__ import annotations

import argparse
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


class ProfileValidationError(ValueError):
    pass


UDID_PATTERN = re.compile(r"[A-Fa-f0-9]{40}")
BUNDLE_PATTERN = re.compile(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+")


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise ProfileValidationError(message)


def parse_expected_udids(raw: str) -> set[str]:
    values = [item.strip().upper() for item in raw.split(",") if item.strip()]
    _require(bool(values), "Expected registered-device UDIDs were not configured.")
    _require(all(UDID_PATTERN.fullmatch(item) for item in values),
             "Expected device list contains a malformed UDID.")
    _require(len(set(values)) == len(values),
             "Expected device list contains duplicate UDIDs.")
    return set(values)


def validate_profile(
    profile: dict[str, Any],
    expected_bundle_id: str,
    expected_team_id: str,
    expected_udids: str,
    now: datetime | None = None,
) -> dict[str, Any]:
    _require(BUNDLE_PATTERN.fullmatch(expected_bundle_id) is not None,
             "Expected bundle identifier is malformed.")
    _require(re.fullmatch(r"[A-Z0-9]{10}", expected_team_id) is not None,
             "Expected Apple Team ID is malformed.")
    _require(isinstance(profile, dict), "Provisioning profile root is not a dictionary.")
    team_identifiers = profile.get("TeamIdentifier")
    _require(isinstance(team_identifiers, list) and expected_team_id in team_identifiers,
             "Provisioning profile TeamIdentifier does not match the expected team.")
    platforms = profile.get("Platform")
    _require(isinstance(platforms, list) and "iOS" in platforms,
             "Provisioning profile is not an iOS profile.")

    expiration = profile.get("ExpirationDate")
    _require(isinstance(expiration, datetime),
             "Provisioning profile has no valid expiration date.")
    if expiration.tzinfo is None:
        expiration = expiration.replace(tzinfo=timezone.utc)
    current = now or datetime.now(timezone.utc)
    if current.tzinfo is None:
        current = current.replace(tzinfo=timezone.utc)
    _require(expiration > current, "Provisioning profile is expired.")

    entitlements = profile.get("Entitlements")
    _require(isinstance(entitlements, dict),
             "Provisioning profile entitlements are missing or malformed.")
    app_id = entitlements.get("application-identifier")
    suffix = "." + expected_bundle_id
    _require(isinstance(app_id, str) and app_id.endswith(suffix) and "*" not in app_id,
             "Provisioning profile application identifier does not exactly match the bundle ID.")
    prefix = app_id[: -len(suffix)]
    prefixes = profile.get("ApplicationIdentifierPrefix")
    _require(isinstance(prefixes, list) and prefix in prefixes,
             "Provisioning profile application identifier prefix is invalid.")
    _require(entitlements.get("get-task-allow") is False,
             "Ad Hoc distribution profile must set get-task-allow=false.")
    _require(profile.get("ProvisionsAllDevices") is not True,
             "Enterprise-wide profiles are not accepted for Ad Hoc distribution.")

    devices = profile.get("ProvisionedDevices")
    _require(isinstance(devices, list) and bool(devices),
             "Ad Hoc profile contains no registered devices.")
    _require(all(isinstance(device, str) and UDID_PATTERN.fullmatch(device)
                 for device in devices),
             "Ad Hoc profile contains a malformed registered-device identifier.")
    eligible = {device.upper() for device in devices}
    _require(len(eligible) == len(devices),
             "Ad Hoc profile contains duplicate registered-device identifiers.")
    expected = parse_expected_udids(expected_udids)
    _require(expected == eligible,
             "Ad Hoc profile registered-device set does not exactly match the configured eligible devices.")
    certificates = profile.get("DeveloperCertificates")
    _require(isinstance(certificates, list) and bool(certificates)
             and all(isinstance(cert, bytes) and bool(cert) for cert in certificates),
             "Ad Hoc profile contains no valid distribution certificates.")

    uuid = profile.get("UUID")
    name = profile.get("Name")
    _require(isinstance(uuid, str) and bool(uuid), "Ad Hoc profile UUID is missing.")
    _require(isinstance(name, str) and bool(name), "Ad Hoc profile name is missing.")
    return {
        "uuid": uuid,
        "name": name,
        "eligible_device_count": len(eligible),
        "expected_device_count": len(expected),
        "expiration": expiration.isoformat(),
    }


def validate_profile_file(
    profile_path: str | Path,
    expected_bundle_id: str,
    expected_team_id: str,
    expected_udids: str,
) -> dict[str, Any]:
    import plistlib

    path = Path(profile_path)
    if not path.is_file() or path.stat().st_size == 0:
        raise ProfileValidationError("Provisioning profile file is missing or empty.")
    try:
        with path.open("rb") as stream:
            profile = plistlib.load(stream)
    except Exception as error:
        raise ProfileValidationError("Provisioning profile is not a valid decoded plist.") from error
    return validate_profile(profile, expected_bundle_id, expected_team_id, expected_udids)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("profile_path")
    parser.add_argument("bundle_id")
    parser.add_argument("team_id")
    args = parser.parse_args()
    expected_udids = __import__("os").environ.get("IOS_ADHOC_EXPECTED_DEVICE_UDIDS", "")
    try:
        result = validate_profile_file(
            args.profile_path, args.bundle_id, args.team_id, expected_udids
        )
    except ProfileValidationError as error:
        print(f"Ad Hoc profile validation failed: {error}", file=sys.stderr)
        return 1
    print(
        "Ad Hoc profile valid; "
        f"eligible_devices={result['eligible_device_count']}; "
        f"configured_devices={result['expected_device_count']}; "
        f"expires={result['expiration']}."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
