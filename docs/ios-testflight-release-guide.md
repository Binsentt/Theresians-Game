# Theresian's Quest iOS TestFlight Release Guide

Source snapshot: `main` at `f333035c75a1ae9e1f77325ab13db67b33f0092e` (2026-11-02).

This guide records the manual release path and static QA findings. No Apple credentials were accessed, no signed build or upload was run, and no physical-device test is claimed.

## Release invariants

- Keep the bundle ID `com.theresiansquest.game`, Team ID `7A4H2D888M`, and displayed name `Theresian's Quest`.
- The CI-generated distribution build targets iOS 15.0 or later. The committed preset still says 14.0; the iOS TestFlight workflow changes this only in its temporary CI copy.
- Use the `iOS TestFlight` workflow on `main`. It is `workflow_dispatch` only; pushes to `main` do not sign or upload to TestFlight.
- Godot 4.6.1, its matching iOS Release template, Xcode 26.3, and iOS 26.2 SDK/runtime are verified by the workflow before export/build.
- Keep saves under the existing app identity. Never change the bundle ID for an update, and test an update over an installed copy instead of uninstalling it.

## One-time Apple and GitHub setup

1. In Apple Developer account, verify Team ID `7A4H2D888M` and register or confirm the explicit App ID `com.theresiansquest.game`.
2. Use an Apple Distribution certificate with its matching private key, exported as a password-protected PKCS#12 file. Create an App Store Connect provisioning profile for that exact App ID and certificate; record its exact profile name.
3. In App Store Connect, confirm the app record exists for the same bundle ID and the account agreements are current. Choose the first marketing version to ship.
4. Create an App Store Connect team API key with an upload-capable role. Secure the downloaded private key; it must not be committed or pasted into chat.
5. In GitHub repository Settings > Environments, configure `ios-appstore-release`, restrict deployment to `main`, and add an independent required reviewer. Put the signing and upload credentials in this environment so its approval gates access.
6. Add these environment secrets: `IOS_DISTRIBUTION_CERTIFICATE_BASE64`, `IOS_DISTRIBUTION_CERTIFICATE_PASSWORD`, `IOS_PROVISIONING_PROFILE_BASE64`, `IOS_PROVISIONING_PROFILE_NAME`, `IOS_KEYCHAIN_PASSWORD`, `APPSTORE_ISSUER_ID`, `APPSTORE_KEY_ID`, and `APPSTORE_API_PRIVATE_KEY`.
7. Add repository Actions variables `IOS_MARKETING_VERSION` and `IOS_BUILD_BASE`. Keep `IOS_SIGNING_ENABLED` and `IOS_TESTFLIGHT_UPLOAD_ENABLED` false until the release is fully prepared and explicitly approved.

## First signed IPA and TestFlight upload

The intended first release is one sequential manual run after setup is complete:

1. Confirm the current `main` commit, version, build-number base, required secrets, and protected environment. Confirm the two release gates are enabled only for the approved release window.
2. Open Actions > iOS TestFlight, select `main`, and run with `build_signed=true` and `upload_testflight=true`.
3. Approve the `ios-appstore-release` environment when prompted. The workflow exports Godot's Xcode project, verifies PCK/privacy references, archives Release arm64, checks that the Release Godot engine is linked, signs and exports the IPA, then validates bundle/version/build/signature/entitlements/resources before upload. A failed check stops later steps.
4. Review the workflow summary and verified IPA artifact. Upload acceptance is not the same as Apple processing completion; check App Store Connect > TestFlight > Build Uploads until the build is processed and review any warnings/errors.

Do not use an ordinary push or rerun as a release mechanism. The workflow is manual-only, and TestFlight upload is blocked on attempts after the first.

## Version and build numbers

Set `IOS_MARKETING_VERSION` to the planned numeric `major.minor.patch` value. Check App Store Connect build history for that version and set `IOS_BUILD_BASE` above its highest uploaded build number. The workflow computes:

`build number = IOS_BUILD_BASE + (GitHub run number × 100) + run attempt`

Use the next iOS TestFlight workflow run number at dispatch time; unsigned/manual validation runs also advance that number. Do not reuse a build number. If a release run fails, start a new run after fixing the cause rather than rerunning an upload attempt. If Apple is still processing an accepted upload, wait for its status before starting another release.

## Internal testers and future updates

In App Store Connect > TestFlight, create an internal group, add eligible App Store Connect users, and attach the processed build. Enable automatic distribution for that group if testers should receive each later approved build automatically. Apple makes the processed build available to the group; the GitHub workflow does not assign groups or publish on every push. Keep release creation manual and approved. For each update, select the intended version, use a unique build number, run the workflow on `main`, then confirm processing and group availability.

Before testing an update, create a save on the device, install the new build over the existing app, and verify load/resume. Do not uninstall the app during this preservation check.

## Physical-device QA checklist

This is a checklist for a future test; it has not been run.

- [ ] Install and launch on supported iOS 15+ iPhone hardware; also test iPad if it is in the intended device family.
- [ ] Verify launch screen, app icon/name, landscape layout, safe areas, touch controls, audio, pause/resume, and return from background.
- [ ] Start mathematics encounters at representative difficulty levels; test correct and incorrect answers, completion, retry, and resulting progress.
- [ ] Follow scene transitions through menus, world/interior scenes, encounters, and return paths without a blank or stuck scene.
- [ ] Create a save, quit/relaunch, load it, and verify location, quest/task state, and settings. Repeat after installing an update over the same app.
- [ ] Test login/session setup, progress fetch/commit, and sync on a stable network. Test offline interruption, reconnect, retry, and duplicate-event behavior.
- [ ] Verify progress remains associated with the correct test student/parent profile and is not mixed between accounts.
- [ ] Use approved synthetic test accounts for production-backed testing; do not submit real student data from a debug build.

## Static QA findings to resolve before distribution

- `Data/api_config.json` points to `https://theresiansquest.com` and sets `production_qa_enabled` to true. In debug builds this selects the production endpoint unless local QA is explicitly requested; normal remote-sync writes are not disabled in that mode. Use only approved synthetic accounts for production-backed checks.
- `THERESIANS_QA_LOCAL=1` selects the local QA profile, whose URL is `127.0.0.1`. On an iPhone, that address means the phone itself, not a development Mac. No network endpoint was contacted during this review.
- The privacy manifest declares tracking false and required-reason APIs, but has no collected-data entries. The game source sends student/parent identifiers, session fields, and gameplay/progression data to the configured API. The repository does not establish backend retention, access, or privacy purposes, so the manifest and App Store privacy answers need an owner/privacy review before upload. The declared disk-space/file-timestamp reasons also need to be checked against actual app and Godot-template API use. No privacy declaration was changed here.

## Failed release recovery and Android preservation

- Read the first failed step and full logs. A failed archive, signature, or IPA verification must stop before upload.
- For a new upload attempt, correct the cause and start a new manual workflow run so it gets a new run number. Do not rerun an upload attempt; the workflow blocks uploads on reruns to avoid duplicates.
- After upload acceptance, wait for Apple's processing result before deciding whether another build is needed.
- Android Internal Testing remains a separate workflow. Run #19 succeeded after the PR #14 merge; this guide does not change Android presets, workflows, or signing.

## References

- [Godot 4.6 iOS export guide](https://docs.godotengine.org/en/4.6/tutorials/export/exporting_for_ios.html)
- [Godot iOS export options](https://docs.godotengine.org/en/4.6/classes/class_editorexportplatformios.html)
- [Apple required-reason API privacy manifest guidance](https://developer.apple.com/documentation/technotes/tn3183-adding-required-reason-api-entries-to-your-privacy-manifest)
- [Apple privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)
- [Apple upload builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds)
- [Apple internal TestFlight testers](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers)
