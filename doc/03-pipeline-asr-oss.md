# Processing Pipeline: Transcode → OSS → ASR

## Purpose

Document the manual pipeline executed from the UI after a recording is saved (or after an audio file is imported).

## Key Files

- `Sources/VoiceMemo/Views/PipelineView.swift`
- `Sources/VoiceMemo/Services/MeetingPipelineManager.swift`
- `Sources/VoiceMemo/Services/Pipeline/PipelineBoard.swift`
- `Sources/VoiceMemo/Services/Pipeline/PipelineNodes.swift`
- `Sources/VoiceMemo/Services/Pipeline/TranscriptParser.swift`
- `Sources/VoiceMemo/Services/OSSService.swift`
- `Sources/VoiceMemo/Services/TranscriptionService.swift` (Protocol)
- `Sources/VoiceMemo/Services/TingwuService.swift` (Alibaba Cloud implementation)
- `Sources/VoiceMemo/Services/VolcengineService.swift` (ByteDance implementation)

## Pipeline Managers

The app uses a single pipeline manager:

- **`MeetingPipelineManager`**: Handles the pipeline tasks.

Internally, `MeetingPipelineManager` uses a **PipelineBoard (Blackboard Pattern)** to orchestrate nodes:

- **`PipelineBoard`**: A pure in-memory, strongly-typed data structure used to pass state and artifacts (e.g., paths, URLs, TaskIDs) between nodes. It decouples Nodes from the DB Model (`MeetingTask`).
- **`PipelineNode`**: A protocol defining `run(board:services:)`. Nodes are only responsible for executing business logic and updating the Board, not modifying the Task directly.
- **Hydration/Persistence**: `MeetingPipelineManager` handles converting `MeetingTask` to `PipelineBoard` (Hydration) before the pipeline starts, and syncing the Board's state back to `MeetingTask` (Persistence) after each node executes.
- Concrete Node classes (e.g. `TranscodeNode`, `UploadNode`) are defined in `PipelineNodes.swift`.

This keeps the UI-facing API stable (e.g. `transcode()`, `upload()`) while allowing the implementation to be composed and resumed from any step.

## Multi-Provider ASR Architecture

The app supports multiple ASR (Automatic Speech Recognition) providers through the `TranscriptionService` protocol:

- **`TranscriptionService`**: Protocol defining the interface for transcription services
  - `createTask(fileUrl:)`: Submit an audio file for transcription
  - `getTaskInfo(taskId:)`: Query task status and retrieve results
  - `fetchJSON(url:)`: Helper to fetch JSON data from URLs

- **`TingwuService`**: Alibaba Cloud Tingwu implementation
  - Uses ACS3-HMAC-SHA256 signature authentication
  - Endpoint: `https://tingwu.cn-beijing.aliyuncs.com/openapi/tingwu/v2/tasks`

- **`VolcengineService`**: ByteDance Volcengine implementation
  - Uses header-based authentication (X-Api-App-Key, X-Api-Access-Key, X-Api-Resource-Id)
  - Endpoint: `https://openspeech.bytedance.com/api/v3/auc/bigmodel`
  - Supports auto format inference and speaker diarization

Provider selection is controlled by `SettingsStore.asrProvider` and wired in `MeetingPipelineManager` via factory pattern.

## Pipeline Steps

1. Upload Raw (Original) to OSS
2. Transcode
3. Upload (Mixed) to OSS
4. Create ASR task (Tingwu or Volcengine)
5. Poll status and fetch results

`PipelineView` provides manual control buttons for each step, highlighting the next recommended action.

## Upload Raw (Original)

`UploadOriginalNode` → `OSSService.uploadFile()`:

- Purpose: Backup the original high-fidelity audio (e.g., m4a/wav) before transcoding.
- Object key format:
  - `"<ossPrefix><yyyy/MM/dd>/<recordingId>/original.<ext>"`
- Updates:
  - `task.originalFileUrl`
  - `task.status`: `recorded` → `uploadingRaw` → `uploadedRaw`

## Transcode

`MeetingPipelineManager.transcode()` triggers the full pipeline start. The actual work is performed by `TranscodeNode`.

- Input: `task.localFilePath` (typically `...mixed.m4a`)
- Output: `mixed_48k.m4a` in the same folder
- Uses `AVAssetExportSession` with preset `AVAssetExportPresetAppleM4A`
- Updates:
  - `task.localFilePath` to the transcoded file
  - `task.status`: `transcoding` → `transcoded` (or `failed`)

## Upload (Mixed) to OSS

`UploadNode` → `OSSService.uploadFile()`:

- Object key format:
  - `"<ossPrefix><yyyy/MM/dd>/<recordingId>/mixed.m4a"`
- Notes:
  - Local transcoded filename uses `mixed_48k.m4a`, but the OSS object key remains `mixed.m4a`.
- Returns:
  - `publicUrl` computed as `https://<bucket>.<endpointHost>/<objectKey>`
- Updates:
  - `task.ossUrl`
  - `task.status`: `uploading` → `uploaded`

## Create ASR Task

`CreateTaskNode` → `activeTranscriptionService.createTask()`:

The active service is selected based on `settings.asrProvider`:

### Alibaba Cloud Tingwu

- Requires:
  - `task.ossUrl` is a publicly accessible URL
  - `settings.tingwuAppKey` set
  - Aliyun AK/Secret present in Keychain
- Sends request:
  - `PUT https://tingwu.cn-beijing.aliyuncs.com/openapi/tingwu/v2/tasks?type=offline`
  - header `x-acs-action: CreateTask`
  - JSON body contains `AppKey`, `Input.FileUrl`, `Input.SourceLanguage`, and `Parameters`

Feature toggles influence parameters:

- Summary: `SummarizationEnabled`, `Summarization.Types`
- Key points / actions: `MeetingAssistanceEnabled`, `MeetingAssistance.Types`
- Role split: `Transcription.DiarizationEnabled` and `SpeakerCount`

On success:

- Saves `task.tingwuTaskId`
- Moves status to `polling`

### ByteDance Volcengine

- Requires:
  - `task.ossUrl` is a publicly accessible URL
  - `settings.volcAppId`, `settings.volcResourceId` set
  - Access Token present in Keychain
- Sends request:
  - `POST https://openspeech.bytedance.com/api/v3/auc/bigmodel/submit`
  - Headers: `X-Api-App-Key`, `X-Api-Access-Key`, `X-Api-Resource-Id`, `X-Api-Request-Id`
  - JSON body contains `user.uid`, `audio.url`, `audio.format`, and `request` parameters

Request parameters:

- `model_name`: "bigmodel"
- `enable_speaker_info`: true (for speaker diarization)
- `enable_itn`: true (inverse text normalization)
- `enable_punc`: true (punctuation)
- `ssd_version`: "200"

On success:

- Returns 200 OK with empty body
- Task ID is the client-generated `requestId` sent in `X-Api-Request-Id` header
- Moves status to `polling`

## Poll and Parse Results

`PollingNode`:

- Calls `activeTranscriptionService.getTaskInfo(taskId:)`
- On `SUCCESS` / `COMPLETED`:
  - Persists raw `Data` object (pretty JSON) into `task.rawResponse`
  - Extracts:
    - Uses **`TranscriptParser`** to unify transcript result parsing across providers.
    - Transcript: Provider-specific format → `TranscriptParser` parses to text.
    - Summary / key points / action items:
      - Tingwu: `Result.Summarization` URL or inline object, `Result.MeetingAssistance` URL or inline object
      - Volcengine: Currently supports transcript only (summary features may be added later)
  - Sets `task.status = completed`
- On `FAILED`:
  - Sets `task.status = failed` and stores a message in `task.lastError`
- While running:
  - The node throws a retryable error (`"Task running"`); the manager retries with a 2s delay.
  - Current retry policy: max 60 attempts (about 2 minutes).

## Transcript Parser

`TranscriptParser` provides unified parsing for different provider response formats:

- **`TingwuParser`**: Parses Alibaba Cloud Tingwu format
  - Handles `Result.Transcription` with sentence-level segments
  - Extracts speaker information from `SpeakerId` field

- **`VolcengineParser`**: Parses ByteDance Volcengine format
  - Handles `utterances` array with speaker information
  - Falls back to `text` field if utterances not available
  - Extracts speaker from `speaker` field or `additions.speaker`

Both parsers normalize output to a consistent text format with speaker labels.

## Tingwu Signing (ACS3-HMAC-SHA256)

`TingwuService.signRequest(_:body:)`:

- Computes `x-acs-content-sha256` from body (or empty body for GET)
- Canonicalizes method/path/query/headers
- Signs `ACS3-HMAC-SHA256\n<canonicalRequestHash>` with HMAC-SHA256 using AccessKeySecret
- Sets `Authorization` header:
  - `ACS3-HMAC-SHA256 Credential=<akId>,SignedHeaders=<...>,Signature=<...>`

The canonical request builder is tested in `Tests/VoiceMemoTests/TingwuSignatureTests.swift`.

## Volcengine Authentication

`VolcengineService` uses header-based authentication:

- `X-Api-App-Key`: App ID from settings
- `X-Api-Access-Key`: Access Token from Keychain
- `X-Api-Resource-Id`: Resource ID (cluster ID) from settings
- `X-Api-Request-Id`: Client-generated UUID (used as Task ID)
- `X-Api-Sequence`: Always "-1"

No signature calculation is required; authentication is based on the access token.

The request construction is tested in `Tests/VoiceMemoTests/VolcengineTests.swift`.
