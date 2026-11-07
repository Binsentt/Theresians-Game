#!/usr/bin/env python3
"""Synthetic-only regression tests for Ad Hoc profile validation."""

import unittest
import plistlib
from tempfile import TemporaryDirectory
from datetime import datetime, timedelta, timezone
from pathlib import Path

from .ios_adhoc_profile_validation import (
    ProfileValidationError,
    validate_profile,
    validate_profile_file,
)


class AdHocProfileValidationTests(unittest.TestCase):
    bundle = "com.theresiansquest.game"
    team = "7A4H2D888M"
    device_a = "A" * 40
    device_b = "B" * 40

    def profile(self):
        return {
            "UUID": "00000000-1111-2222-3333-444444444444",
            "Name": "Synthetic Ad Hoc Profile",
            "TeamIdentifier": [self.team],
            "ApplicationIdentifierPrefix": ["A1B2C3D4E5"],
            "Platform": ["iOS"],
            "ExpirationDate": datetime.now(timezone.utc) + timedelta(days=10),
            "DeveloperCertificates": [b"synthetic-certificate"],
            "ProvisionedDevices": [self.device_a, self.device_b],
            "Entitlements": {
                "application-identifier": "A1B2C3D4E5." + self.bundle,
                "get-task-allow": False,
            },
        }

    def validate(self, profile=None, expected=None):
        return validate_profile(
            profile if profile is not None else self.profile(),
            self.bundle,
            self.team,
            expected if expected is not None else self.device_a + "," + self.device_b,
        )

    def test_valid_profile_accepts_expected_registered_devices(self):
        result = self.validate()
        self.assertEqual(result["eligible_device_count"], 2)
        self.assertEqual(result["expected_device_count"], 2)

    def test_wrong_team_is_rejected(self):
        profile = self.profile()
        profile["TeamIdentifier"] = ["0000000000"]
        with self.assertRaises(ProfileValidationError):
            self.validate(profile)

    def test_wrong_bundle_identifier_is_rejected(self):
        profile = self.profile()
        profile["Entitlements"]["application-identifier"] = "A1B2C3D4E5.com.other.app"
        with self.assertRaises(ProfileValidationError):
            self.validate(profile)

    def test_profile_without_devices_is_rejected(self):
        profile = self.profile()
        profile["ProvisionedDevices"] = []
        with self.assertRaises(ProfileValidationError):
            self.validate(profile)

    def test_unregistered_expected_device_is_rejected(self):
        with self.assertRaises(ProfileValidationError):
            self.validate(expected="C" * 40)

    def test_malformed_expected_udid_is_rejected(self):
        with self.assertRaises(ProfileValidationError):
            self.validate(expected="not-a-udid")

    def test_profile_with_unapproved_extra_device_is_rejected(self):
        with self.assertRaises(ProfileValidationError):
            self.validate(expected=self.device_a)

    def test_empty_expected_device_list_is_rejected(self):
        with self.assertRaises(ProfileValidationError):
            self.validate(expected="")

    def test_malformed_profile_device_is_rejected(self):
        profile = self.profile()
        profile["ProvisionedDevices"] = [self.device_a, "not-a-udid"]
        with self.assertRaises(ProfileValidationError):
            self.validate(profile)

    def test_wildcard_application_identifier_is_rejected(self):
        profile = self.profile()
        profile["Entitlements"]["application-identifier"] = "A1B2C3D4E5.com.theresiansquest.*"
        with self.assertRaises(ProfileValidationError):
            self.validate(profile)

    def test_profile_without_distribution_certificate_is_rejected(self):
        profile = self.profile()
        profile["DeveloperCertificates"] = []
        with self.assertRaises(ProfileValidationError):
            self.validate(profile)

    def test_missing_expiration_is_rejected(self):
        profile = self.profile()
        profile.pop("ExpirationDate")
        with self.assertRaises(ProfileValidationError):
            self.validate(profile)

    def test_invalid_application_prefix_is_rejected(self):
        profile = self.profile()
        profile["ApplicationIdentifierPrefix"] = ["OTHERPREFIX"]
        with self.assertRaises(ProfileValidationError):
            self.validate(profile)

    def test_wrong_platform_shape_is_rejected(self):
        profile = self.profile()
        profile["Platform"] = "iOS"
        with self.assertRaises(ProfileValidationError):
            self.validate(profile)

    def test_malformed_entitlements_are_rejected(self):
        profile = self.profile()
        profile["Entitlements"] = []
        with self.assertRaises(ProfileValidationError):
            self.validate(profile)

    def test_duplicate_profile_devices_are_rejected(self):
        profile = self.profile()
        profile["ProvisionedDevices"] = [self.device_a, self.device_a]
        with self.assertRaises(ProfileValidationError):
            self.validate(profile)

    def test_team_identifier_requires_exact_list_entry(self):
        profile = self.profile()
        profile["TeamIdentifier"] = "prefix-" + self.team + "-suffix"
        with self.assertRaises(ProfileValidationError):
            self.validate(profile)

    def test_valid_decoded_profile_file_is_accepted(self):
        with TemporaryDirectory() as directory:
            path = Path(directory) / "profile.plist"
            with path.open("wb") as stream:
                plistlib.dump(self.profile(), stream)
            result = validate_profile_file(
                path, self.bundle, self.team, self.device_a + "," + self.device_b
            )
            self.assertEqual(result["eligible_device_count"], 2)

    def test_malformed_decoded_profile_file_fails_closed(self):
        with TemporaryDirectory() as directory:
            path = Path(directory) / "profile.plist"
            path.write_bytes(b"not a plist")
            with self.assertRaises(ProfileValidationError):
                validate_profile_file(
                    path, self.bundle, self.team, self.device_a
                )

    def test_expired_profile_is_rejected(self):
        profile = self.profile()
        profile["ExpirationDate"] = datetime.now(timezone.utc) - timedelta(days=1)
        with self.assertRaises(ProfileValidationError):
            self.validate(profile)

    def test_development_profile_is_rejected(self):
        profile = self.profile()
        profile["Entitlements"]["get-task-allow"] = True
        with self.assertRaises(ProfileValidationError):
            self.validate(profile)

    def test_enterprise_profile_is_rejected(self):
        profile = self.profile()
        profile["ProvisionsAllDevices"] = True
        with self.assertRaises(ProfileValidationError):
            self.validate(profile)

    def test_duplicate_expected_devices_are_rejected(self):
        with self.assertRaises(ProfileValidationError):
            self.validate(expected=self.device_a + "," + self.device_a)

    def test_non_ios_profile_is_rejected(self):
        profile = self.profile()
        profile["Platform"] = ["macOS"]
        with self.assertRaises(ProfileValidationError):
            self.validate(profile)


if __name__ == "__main__":
    unittest.main(verbosity=2)
