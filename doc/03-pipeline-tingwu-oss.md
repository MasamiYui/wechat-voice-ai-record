# Processing Pipeline: Transcode → OSS → Tingwu

## Purpose

Document the manual pipeline executed from the UI after a recording is saved (or after an audio file is imported).

## Key Files

- `Sources/VoiceMemo/Views/PipelineView.swift`
- `Sources/VoiceMemo/Services/MeetingPipelineManager.swift`
- `Sources/VoiceMemo/Services/OSSService.swift`
- `Sources/VoiceMemo/Services/TingwuService.swift`

## Pipeline Managers

The app uses a single pipeline manager:

- **`MeetingPipelineManager`**: Handles both "Mixed" and "Separated" mode tasks. Mode-specific behavior is selected via `MeetingTask.mode` (e.g. upload/create/poll for one file vs two files).

Internally, `MeetingPipelineManager` runs the pipeline via a small node abstraction:

- `PipelineNode` (step-based execution)
- `PipelineContext` (task + services + settings)

This keeps the UI-facing API stable (e.g. `transcode()`, `upload()`) while allowing the implementation to be composed and resumed from any step.

## Pipeline Steps (Mixed Mode)

1. Upload Raw (Original) to OSS
2. Transcode
3. Upload (Mixed) to OSS
4. Create Tingwu task
5. Poll status and fetch results

`PipelineView` provides manual control buttons for each step, highlighting the next recommended action.

## Upload Raw (Original)

`UploadOriginalNode` → `OSSService.uploadFile()`:

- Purpose: Backup the original high-fidelity audio (e.g., m4a/wav) before transcoding.
- Object key format:
  - `"<ossPrefix><yyyy/MM/dd>/<recordingId>/original.<ext>"`
- Updates:
  - `task.originalFileUrl`
  - `task.status`: `recorded` → `uploadingOriginal` → `uploadedOriginal`

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

## Create Tingwu Task

`CreateTaskNode` → `TingwuService.createTask()`:

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

## Poll and Parse Results

`PollingNode`:

- Calls `TingwuService.getTaskInfo(taskId:)`
- On `SUCCESS` / `COMPLETED`:
  - Persists raw `Data` object (pretty JSON) into `task.rawResponse`
  - Extracts:
    - Transcript:
      - `Result.Transcription` URL → fetch JSON → `Paragraphs`/`Sentences`
    - Summary / key points / action items:
      - `Result.Summarization` URL or inline object
      - `Result.MeetingAssistance` URL or inline object
  - Sets `task.status = completed`
- On `FAILED`:
  - Sets `task.status = failed` and stores a message in `task.lastError`
- While running:
  - The node throws a retryable error (`"Task running"`); the manager retries with a 2s delay.
  - Current retry policy: max 60 attempts (about 2 minutes).

## Separated Mode (Dual-Speaker)

In `MeetingTask.mode == separated`, the manager runs two single-track pipelines concurrently:

- Speaker 1 (Local mic): `speaker1AudioPath` → `ossUrl` → `tingwuTaskId` → `speaker1Transcript`
- Speaker 2 (Remote system audio): `speaker2AudioPath` → `speaker2OssUrl` → `speaker2TingwuTaskId` → `speaker2Transcript`

Each track uses the same node chain with a `targetSpeaker` argument. Upload object keys become:

- `"<ossPrefix><yyyy/MM/dd>/<recordingId>/speaker1.m4a"`
- `"<ossPrefix><yyyy/MM/dd>/<recordingId>/speaker2.m4a"`

### Alignment (Current)

After both tracks finish (or partially finish), `MeetingPipelineManager.tryAlign()` currently produces a simple merged `task.transcript` by concatenating speaker transcripts with headers. `alignedConversation` remains reserved for future timestamp alignment.

### Failure Tracking and Retry

- Mixed mode uses `task.failedStep` and `task.lastError`.
- Separated mode uses per-speaker fields:
  - `task.speaker1Status` / `task.speaker2Status`
  - `task.speaker1FailedStep` / `task.speaker2FailedStep`
- UI retry entry points:
  - `MeetingPipelineManager.retry()` retries from the recorded failure step.
  - `MeetingPipelineManager.retry(speaker:)` retries only a specific speaker track.

## Tingwu Signing (ACS3-HMAC-SHA256)

`TingwuService.signRequest(_:body:)`:

- Computes `x-acs-content-sha256` from body (or empty body for GET)
- Canonicalizes method/path/query/headers
- Signs `ACS3-HMAC-SHA256\n<canonicalRequestHash>` with HMAC-SHA256 using AccessKeySecret
- Sets `Authorization` header:
  - `ACS3-HMAC-SHA256 Credential=<akId>,SignedHeaders=<...>,Signature=<...>`

The canonical request builder is tested in `Tests/VoiceMemoTests/TingwuSignatureTests.swift`.
