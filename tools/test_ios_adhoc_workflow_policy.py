#!/usr/bin/env python3
"""Static safety contracts for the credential-gated Ad Hoc release workflow."""
from __future__ import annotations
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORKFLOWS = ROOT / ".github" / "workflows"

def workflow(name):
    return (WORKFLOWS / name).read_text(encoding="utf-8")

def job(text, name):
    match = re.search(rf"(?ms)^  {re.escape(name)}:\n(.*?)(?=^  [A-Za-z0-9_-]+:\s*$|\Z)", text)
    if not match:
        raise AssertionError(f"Missing workflow job: {name}")
    return match.group(1)

def permissions(text):
    values = []
    lines = text.splitlines()
    for index, line in enumerate(lines):
        match = re.match(r"^( *)permissions:\s*$", line)
        if not match:
            continue
        indent = len(match.group(1))
        for child in lines[index + 1:]:
            if not child.strip():
                continue
            child_indent = len(child) - len(child.lstrip())
            if child_indent <= indent:
                break
            if child_indent == indent + 2:
                value = re.fullmatch(r"[A-Za-z0-9_-]+:\s*(read|none|write)\s*", child.strip())
                if not value:
                    raise AssertionError(f"Unknown permission: {child}")
                values.append(value.group(1))
    return values

class AdHocWorkflowPolicyTests(unittest.TestCase):
    def setUp(self):
        self.adhoc = workflow("ios-adhoc-release.yml")
        self.runtime = workflow("godot-runtime-regression.yml")
        self.unsigned = workflow("ios-unsigned-release.yml")
        self.pr_ci = workflow("ios-adhoc-pr-validation.yml")
        self.signed = job(self.adhoc, "signed-adhoc")

    def test_all_related_token_permissions_are_read_only(self):
        for name, text in (("adhoc", self.adhoc), ("runtime", self.runtime),
                           ("unsigned", self.unsigned), ("pr-ci", self.pr_ci)):
            with self.subTest(workflow=name):
                scopes = permissions(text)
                self.assertTrue(scopes)
                self.assertTrue(set(scopes) <= {"read", "none"}, scopes)

    def test_pr_validation_is_pull_request_only_and_main_scoped(self):
        match = re.search(r"(?ms)^on:\n(.*?)(?=^[A-Za-z][A-Za-z0-9_-]*:\s*$|\Z)", self.pr_ci)
        self.assertIsNotNone(match)
        events = re.findall(r"(?m)^  ([A-Za-z_][A-Za-z0-9_-]*):", match.group(1))
        self.assertEqual(events, ["pull_request"])
        self.assertIn("branches:\n      - main", match.group(1))

    def test_pr_validation_has_no_secrets_or_distribution_operations(self):
        for token in ("secrets.", "vars.", "contents: write", "actions: write",
                      "xcodebuild", "codesign", "upload-artifact", "workflow_dispatch"):
            with self.subTest(token=token):
                self.assertNotIn(token, self.pr_ci)

    def test_pr_validation_pins_actionlint_and_runs_synthetic_tests(self):
        self.assertIn('version="1.7.12"', self.pr_ci)
        self.assertIn("actionlint_${version}_linux_amd64.tar.gz", self.pr_ci)
        self.assertIn("8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8", self.pr_ci)
        self.assertIn("tools.test_ios_adhoc_profile_validation", self.pr_ci)
        self.assertIn("tools.test_ios_adhoc_workflow_policy", self.pr_ci)

    def test_release_workflow_is_limited_to_release_branch_or_manual_run(self):
        self.assertRegex(self.adhoc, r"(?ms)^on:\n  push:\n    branches:\n      - ios-release\n")
        self.assertNotRegex(self.adhoc, r"(?m)^  pull_request:")
        self.assertRegex(self.adhoc, r"(?ms)build_signed:\n.*?default: false")

    def test_signing_requires_all_three_gates(self):
        condition = re.search(r"(?m)^    if: (.+)$", self.signed)
        self.assertIsNotNone(condition)
        for required in ("vars.IOS_ADHOC_SIGNING_ENABLED == 'true'",
                         "inputs.build_signed == true",
                         "needs.signing-gate.result == 'success'",
                         "github.ref == 'refs/heads/ios-release'"):
            self.assertIn(required, condition.group(1))
        self.assertIn("name: ios-adhoc-release", self.signed)

    def test_environment_reviewer_and_branch_are_checked(self):
        self.assertIn('rule.get("type") == "required_reviewers"', self.adhoc)
        self.assertIn('rule.get("prevent_self_review") is True', self.adhoc)
        self.assertIn('names != ["ios-release"]', self.adhoc)

    def test_apple_secrets_only_appear_in_gated_signing_job(self):
        start = self.adhoc.index("  signed-adhoc:")
        self.assertNotIn("${{ secrets.", self.adhoc[:start])
        for match in re.finditer(r"\$\{\{\s*secrets\.([A-Z0-9_]+)", self.adhoc):
            self.assertGreaterEqual(match.start(), start)

    def test_udid_secret_is_step_scoped_not_job_wide(self):
        pre_steps = self.signed.split("    steps:", 1)[0]
        self.assertNotIn("IOS_ADHOC_EXPECTED_DEVICE_UDIDS", pre_steps)
        self.assertIn("IOS_ADHOC_EXPECTED_DEVICE_UDIDS: ${{ secrets.IOS_ADHOC_EXPECTED_DEVICE_UDIDS }}", self.signed)

    def test_private_destination_is_checked_before_import_and_publish(self):
        self.assertLess(self.adhoc.index("Verify the private release repository before importing Apple credentials"),
                        self.adhoc.index("Validate and import Apple Distribution assets"))
        self.assertLess(self.adhoc.index("Validate and import Apple Distribution assets"),
                        self.adhoc.index("Publish verified IPA to the private release repository"))
        self.assertIn('repo.get("private") is not True', self.adhoc)
        self.assertIn('IOS_ADHOC_RELEASE_REPOSITORY" == "$GITHUB_REPOSITORY"', self.adhoc)

    def test_reusable_workflow_calls_have_required_markers(self):
        self.assertIn("reusable_call: true", job(self.adhoc, "runtime-regression"))
        self.assertIn("release_pipeline: true", job(self.adhoc, "unsigned-release"))

if __name__ == "__main__":
    unittest.main(verbosity=2)
