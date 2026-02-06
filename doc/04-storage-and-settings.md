# Storage and Settings

## Purpose

Explain where data is stored, how settings and secrets are handled, and how logs work.

## Storage Providers

The app uses a `StorageProvider` abstraction with two implementations:

- `SQLiteStorage`: local persistence (default)
- `MySQLStorage`: remote persistence via `mysql-kit`

Provider selection is driven by `SettingsStore.storageType` and wired by `StorageManager`.

## Persistence (SQLite)

### Database location

`SQLiteStorage` attempts to place the DB at:

- Preferred: `~/Library/Application Support/VoiceMemo/db.sqlite3`
- Fallback: `~/Documents/VoiceMemo/db.sqlite3`
- Last resort: `~/Library/Caches/.../tmp/VoiceMemo/db.sqlite3` (temporary directory)

### Schema

Table `meeting_tasks` stores the full task state:

#### Core Fields

| Field | Type | Note |
| :--- | :--- | :--- |
| `id` | TEXT (PK) | Task Unique Identifier (UUID) |
| `created_at` | DATETIME | Task Creation Time |
| `recording_id` | TEXT | Associated Recording ID |
| `original_file_url` | TEXT | OSS URL of Original File (Backup) |
| `local_file_path` | TEXT | Local Original Merged Audio Path |
| `oss_url` | TEXT | Public URL after Uploading (Mixed/Transcoded) |
| `tingwu_task_id` | TEXT | Tingwu Task ID |
| `status` | TEXT | Task Status (recorded, uploadingRaw, uploadedRaw, transcoding, transcoded, uploading, uploaded, created, polling, completed, failed) |
| `title` | TEXT | Task Title |

#### AI Results

| Field | Type | Note |
| :--- | :--- | :--- |
| `transcript` | TEXT | Full Transcription Text |
| `summary` | TEXT | AI Generated Summary |
| `key_points` | TEXT | Key Points Summary |
| `action_items` | TEXT | Action Items |
| `raw_response` | TEXT | Raw JSON Response from Tingwu API |

#### Retry and Error Handling

| Field | Type | Note |
| :--- | :--- | :--- |
| `last_error` | TEXT | Error Message of the Last Failure |
| `failed_step` | TEXT | The Step where the Pipeline Failed |
| `retry_count` | INTEGER | Number of Retries Attempted |
| `last_successful_status` | TEXT | Last Successful Status (for resuming) |

Writes use `insert(or: .replace)` keyed by `id`.

### HistoryStore

`HistoryStore` loads tasks on init and exposes:

- `refresh()` re-fetches tasks ordered by `created_at` descending.
- `deleteTask(at:)` deletes rows by UUID.

## Persistence (MySQL)

`MySQLStorage` uses the same logical schema as SQLite and creates the `meeting_tasks` table via `CREATE TABLE IF NOT EXISTS`.

Connection details come from settings:

- Host / Port / User / Database (UserDefaults)
- Password (Keychain, see below)

## Settings (UserDefaults)

`SettingsStore` persists non-secret configuration via UserDefaults:

- Storage: `storageType` (`local` or `mysql`)
- ASR Provider: `asrProvider` (`tingwu` or `volcengine`)
- MySQL: host/port/user/database
- OSS: region/bucket/prefix/endpoint
- Tingwu: appKey, language
- Volcengine: appId, resourceId
- Appearance: `appTheme` (`system`, `light`, `dark`)
- Feature toggles: summary/key points/action items/role split
- Logging: verbose logging flag

## Secrets (Keychain)

`KeychainHelper` stores secrets under service:

- `cn.mistbit.voicememo.secrets`

Accounts used:

- `aliyun_ak_id`
- `aliyun_ak_secret`
- `volcengine_access_token`
- `mysql_password`

`SettingsStore` never exposes secrets in clear text to the UI; it only provides:

- `hasAccessKeyId` / `hasAccessKeySecret`
- `hasVolcengineAccessToken`
- methods to save/read/clear

## Logs

`SettingsStore.log(_:)`:

- Always prints to stdout.
- Writes to a file only when:
  - verbose logging enabled, or
  - message contains `error` / `failed` / `test` / `system`

Log file:

- `~/Library/Application Support/VoiceMemo/Logs/app.log`

Settings UI provides:

- show current log path
- open log folder
- clear log
