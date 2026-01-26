# Permissions and Signing (macOS)

## Purpose

Explain which permissions are needed, how they map to Info.plist/entitlements, and how signing stability affects repeated system prompts.

## Required Permissions

### Screen Recording

Needed for ScreenCaptureKit to capture system audio.

- Usage string in `Sources/VoiceMemo/Info.plist`:
  - `NSScreenCaptureUsageDescription`
- Grant via:
  - System Settings → Privacy & Security → Screen Recording

### Microphone

Needed for local audio track.

- Usage string in `Sources/VoiceMemo/Info.plist`:
  - `NSMicrophoneUsageDescription`

## Entitlements

File: `VoiceMemo.entitlements`

Current keys:

- `com.apple.security.app-sandbox`
- `com.apple.security.device.audio-input`
- `com.apple.security.device.camera`
- `com.apple.security.files.downloads.read-write`
- `com.apple.security.files.user-selected.read-write`
- `com.apple.security.network.client`
- `com.apple.security.personal-information.photos-library`

Only add entitlements that are required by actual features; extra entitlements increase review and user trust risks.

## Bundle Identifier

The app identity is anchored by Bundle ID:

- `Info.plist` `CFBundleIdentifier`: `cn.mistbit.voicememo`
- Xcode target build setting `PRODUCT_BUNDLE_IDENTIFIER`: `cn.mistbit.voicememo`

If Bundle ID changes, macOS treats the app as a new identity and will re-prompt for privacy permissions.

## Signing Stability and Repeated Prompts

macOS privacy permission grants are tied to the app’s identity and signing.

For stable behavior during development:

- Keep Bundle ID stable.
- Use a stable development Team and automatic signing in Xcode.
- If you use the generated `VoiceMemo.xcodeproj`, re-run `generate_project.py` after dependency changes to keep package references in sync.
  - If Xcode shows `No such module` for a SwiftPM dependency, try `File > Packages > Reset Package Caches` and then clean the build folder.

Packaging script note:

- `package_app.sh` uses ad-hoc signing (`codesign --sign -`).
- Ad-hoc signatures are not stable identities for repeated permission grants; repeated prompts are expected when running differently signed builds.

## Practical Recommendation

- Debug via Xcode with automatic signing and a fixed team.
- Use the packaging script only for quick local distribution/testing; expect permission prompts unless you switch to a stable signing identity.
