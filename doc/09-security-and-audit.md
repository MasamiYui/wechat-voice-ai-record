# Security and Audit Notes

## Purpose

Provide a security-focused overview of VoiceMemo: what data is collected, where it is stored, what leaves the device, and what to verify during audits.

## Scope / Non-goals

- Scope: local macOS app runtime, local persistence, network egress, secrets handling, and logging behavior.
- Non-goals: Alibaba Cloud service-side behavior and third-party infrastructure guarantees.

## Data Inventory

### Audio Data

- Remote/system audio and local microphone audio are recorded and stored as files.
- A merged file is generated after recording (`mixed.m4a`).
- Default output locations and naming are described in the project README.

### Meeting Content (Derived)

- Transcription results and meeting minutes (summary, key points, action items) may be persisted as text in storage.
- Raw Tingwu JSON response may be persisted for debugging and compatibility.

### Settings

Non-secret configuration is stored in UserDefaults. See: `doc/04-storage-and-settings.md`.

Current notable keys:

- `storageType`: `local` / `mysql`
- `appTheme`: `system` / `light` / `dark`

### Secrets

Secrets are stored in Keychain, not in UserDefaults. See: `doc/04-storage-and-settings.md`.

Accounts:

- `aliyun_ak_id`
- `aliyun_ak_secret`
- `mysql_password`

## Permissions and Entitlements

Permissions required for core functionality are documented in: `doc/05-permissions-and-signing.md`.

Audit focus:

- Screen Recording permission is required to capture system/app audio (ScreenCaptureKit).
- Microphone permission is required to capture local audio.
- Entitlements should match implemented features; avoid adding unused entitlements.

## Network Egress

The app may initiate outbound connections for:

- OSS upload (audio file hosting for Tingwu ingestion).
- Tingwu API requests (create/poll transcription tasks).
- MySQL (optional remote storage when enabled).

Audit focus:

- Ensure endpoints are user-configurable where appropriate (e.g., OSS endpoint).
- Verify no secrets are sent to logs or persisted as plain text.

## Logging and PII

Logging behavior is implemented in `Sources/VoiceMemo/Services/SettingsStore.swift` (`log(_:)`) and described in `doc/04-storage-and-settings.md`.

Audit focus:

- Logs are stored under Application Support when enabled or when the message matches specific keywords.
- Avoid logging raw credentials, request signatures, or full authorization headers.
- Treat transcripts and meeting minutes as sensitive content; avoid writing them to logs.

## Theme Mode (System / Light / Dark)

Theme selection is exposed in Settings and persisted as `appTheme` in UserDefaults.

Runtime behavior:

- The app applies the selected appearance at launch and when the setting changes.
- When `appTheme == system`, the app listens for system theme change notifications and re-applies the system appearance.

Audit focus:

- The theme feature does not expand permissions, does not access user data, and does not produce network egress.
- System theme change handling uses a notification observer that is removed on termination to avoid lifetime leaks.

Relevant code paths:

- `Sources/VoiceMemo/Services/SettingsStore.swift`: `AppTheme`, `appTheme` persistence
- `Sources/VoiceMemo/VoiceMemoApp.swift`: theme application and system theme observer forwarding
- `Sources/VoiceMemo/Views/SettingsView.swift`: UI control

## Verification Checklist

- Secrets are only in Keychain; no secrets in UserDefaults or repository.
- With verbose logging enabled, ensure logs do not contain credentials, signatures, or authorization headers.
- Confirm audio and derived text data persistence is limited to documented locations and storage backends.
- Confirm required permissions match actual runtime behavior (no unused entitlements).
- Confirm theme change observer is registered once and removed on termination.
