# Private Ad Hoc iOS release guide

This workflow prepares a registered-device Ad Hoc IPA. It does not use App Store distribution, TestFlight, or the iOS TestFlight workflow.

## Current verified state

The unsigned Godot 4.6.1 / Xcode 26.3 Release app passed in iOS Unsigned Release #7 on commit `c7376e57fb59ecf1ef390dd2b944ec5e58e76bc3` with arm64, minimum iOS 15.0, the existing bundle identifier, the Release Godot engine, game PCK, and privacy manifest. That run did not sign or install an IPA. The Ad Hoc signing workflow has not been executed; certificate/profile validity, private publication, and physical-device updates remain unverified.

The game repository is public. Its unsigned Actions artifacts are visible to people who can read the repository. The workflow does not upload a signed IPA or signing material to this repository.

## Owner setup checklist

Complete these steps before enabling signed automation:

1. **Create a separate private release repository.** Suggested name: `Binsentt/Theresians-Quest-iOS-Releases`. Set visibility to Private and grant access only to the owner and intended testers/operators. This workflow fails if the destination is public or is the source repository. Do not change the game repository’s visibility as part of this setup.
2. **Protect the release branch.** After this workflow reaches the default branch, create `ios-release` from the approved source. Require pull requests and the Godot runtime checks before changes can reach it. Restrict who can push, disallow force-push and deletion, and do not allow routine gameplay pushes to bypass review. Configure the branch before the first release push.
3. **Configure the `ios-adhoc-release` GitHub environment.** Set a custom deployment branch policy matching exactly `ios-release` (no wildcard branches). Require at least one independent reviewer and enable “Prevent self-review”; the signing job checks both settings. Do not add signing secrets to repository-level secrets; add them to this environment.
4. **Keep these repository variables disabled until separately approved:**
   - `IOS_ADHOC_SIGNING_ENABLED=false`
   - `IOS_ADHOC_RELEASE_REPOSITORY=<owner>/<private-repository>`
   - `IOS_MARKETING_VERSION=<approved major.minor.patch>`
   - `IOS_BUILD_BASE=<integer greater than every previously issued build number>`
5. **Create a least-privilege fine-grained token** for the private destination repository only. Give it Contents read/write (plus the API’s implicit metadata read), an expiration date, and no access to the game repository unless GitHub requires it for your chosen token type. Store it as `IOS_ADHOC_RELEASE_TOKEN` in the protected environment and rotate it on a schedule.
6. **Create Apple signing assets** in the Apple Developer account:
   - Confirm the existing App ID `com.theresiansquest.game` under Team `7A4H2D888M`.
   - Register each intended iPhone UDID under Certificates, Identifiers & Profiles > Devices. Use only devices you have permission to register.
   - Create an Apple Distribution certificate with its private key. Export the certificate and private key as a password-protected PKCS#12 file. Keep the file and password out of chat and source control.
   - Create an **Ad Hoc** provisioning profile for that App ID, the Apple Distribution certificate, and the intended registered iPhones. Download the profile only after the device list is final. The workflow checks the profile’s exact device set, App ID, Team ID, expiration, and distribution entitlements.
7. **Add these environment secrets** without putting their values in source control:
   - `IOS_ADHOC_DISTRIBUTION_CERTIFICATE_BASE64`
   - `IOS_ADHOC_DISTRIBUTION_CERTIFICATE_PASSWORD`
   - `IOS_ADHOC_PROVISIONING_PROFILE_BASE64`
   - `IOS_ADHOC_PROVISIONING_PROFILE_NAME`
   - `IOS_ADHOC_KEYCHAIN_PASSWORD`
   - `IOS_ADHOC_EXPECTED_DEVICE_UDIDS` (comma-separated exact expected UDIDs)
   - `IOS_ADHOC_RELEASE_TOKEN`
8. Confirm the marketing version and build base against the latest IPA already distributed to those devices. The workflow computes `build = IOS_BUILD_BASE + run_number × 100 + run_attempt`; it rejects malformed/overflowing inputs and attempts above 99. Set the base high enough to avoid reusing any prior build number. When replacing/resetting the workflow, re-evaluate the base instead of assuming run numbers continue.
9. Keep signing disabled until all setup is reviewed and the owner separately approves the first signed run.

## First unsigned pipeline check

After the workflow is merged into the default branch and the protected release branch and environment are configured, push only an approved, reviewed source commit to `ios-release` while `IOS_ADHOC_SIGNING_ENABLED=false`. The workflow runs Godot runtime tests, exports the project, builds and validates the unsigned Release app, records the exact source commit/version/build, and uploads unsigned artifacts for CI review. No IPA is produced in this mode.

## First signed Ad Hoc IPA

Only after the owner explicitly authorizes a signed run and all credentials are installed:

1. Review the exact source commit, version, computed build number, private destination, and device set.
2. For a manual release, choose Actions > **iOS Ad Hoc Release**, select `ios-release`, and set `build_signed=true`. A protected-branch push can also request the signed stage once the signing variable is enabled; the environment reviewer must approve that run.
3. The workflow first passes the runtime suite, profile-contract tests, version checks, Godot export, and unsigned Xcode Release build. It then waits for the protected environment approval before accessing Apple credentials.
4. The signed job verifies the environment rule and private destination before importing the certificate/profile. It archives arm64 Release, exports with method `ad-hoc`, checks the signature, Team/bundle/version/build, exact device profile, entitlements, PCK, privacy manifest, and IPA ZIP integrity.
5. The verified IPA, build report, metadata, and changelog are uploaded to a draft release in the private repository. The workflow publishes that private release only after every upload is verified. If a run fails, it does not replace a prior release. Inspect any partial draft in the private repository and resolve it before retrying; each new run gets a distinct build number.
6. Download the IPA from the private repository over an authenticated account and keep its SHA-256 report with the release record.

## Install and update registered iPhones

- Register the UDID before generating the Ad Hoc profile. If devices change, update the expected UDID secret, regenerate the profile, and replace the environment profile secret together.
- Install the first IPA using Xcode’s Devices and Simulators window or Apple Configurator with the iPhone connected. For supported iOS versions, enable Developer Mode when iOS requests it for an app installed outside the App Store.
- An optional over-the-air installation page requires controlled HTTPS hosting, a correctly signed manifest, an authenticated download path, and physical-device testing. This repository does not implement or validate that mechanism. Automatic IPA creation does not guarantee silent installation on unmanaged phones.
- To update an installed copy, install the new IPA over the existing app with the same bundle ID and signing team. **Do not delete the app first**: uninstalling removes its local container. Before broader distribution, physically test that the game opens, old saves load, and pending offline saves/conflict records remain intact after an in-place update.
- Keep build numbers increasing. Preserve bundle ID `com.theresiansquest.game`, the save format, and local conflict/outbox files. A failed build should leave the prior installed copy and prior private release available; distribute a replacement only after a new verified run.

## Future approved game updates

Once the owner has reviewed the workflow and protected `ios-release`, each approved push runs Godot runtime tests and creates a fresh unsigned iOS Release build with source SHA, version/build metadata, and a generated changelog. With signing still disabled it stops at the unsigned artifact. Only after the owner enables the signing variable, configures the private destination/credentials, and approves the protected environment can the same commit produce and publish a verified Ad Hoc IPA to private storage.

Normal pushes to `main` and pull requests do not trigger this workflow. PRs are not automatically signed. The Android Internal Testing workflow is not modified by this proposal.

## Security and recovery notes

- Never add certificates, private keys, passwords, provisioning profiles, device lists, or tokens to commits or workflow output.
- If a credential is exposed, revoke/replace the Apple certificate/profile or GitHub token at its issuer, then update the protected environment.
- A failed preflight must stop before signing. A failed IPA validation must stop before private release creation. A private release upload failure can leave a draft; inspect it manually before rerunning.
- Verify the private repository’s collaborator list and the environment’s branch/reviewer rules during every release review.
- A build and signature check are not proof of successful installation or save preservation. Validate on the actual registered devices before inviting testers.


## Apple references

- [Apple device registration and device limits](https://developer.apple.com/help/account/devices/devices-overview/)
- [Create an Ad Hoc provisioning profile](https://developer.apple.com/help/account/provisioning-profiles/create-an-ad-hoc-provisioning-profile)
- [Distribute to registered devices with Xcode or Apple Configurator](https://developer.apple.com/documentation/xcode/distributing-your-app-to-registered-devices)

