# Processing Pipeline: Transcode → OSS → Tingwu

## Purpose

Document the manual pipeline executed from the UI after a recording is saved (or after an audio file is imported).

## Key Files

- `Sources/VoiceMemo/Views/PipelineView.swift`
- `Sources/VoiceMemo/Services/MeetingPipelineManager.swift`
- `Sources/VoiceMemo/Services/Pipeline/PipelineBoard.swift`
- `Sources/VoiceMemo/Services/Pipeline/PipelineNodes.swift`
- `Sources/VoiceMemo/Services/Pipeline/TranscriptParser.swift`
- `Sources/VoiceMemo/Services/OSSService.swift`
- `Sources/VoiceMemo/Services/TingwuService.swift`

## Pipeline Managers

The app uses a single pipeline manager:

- **`MeetingPipelineManager`**: Handles the pipeline tasks.

Internally, `MeetingPipelineManager` uses a **PipelineBoard (Blackboard Pattern)** to orchestrate nodes:

- **`PipelineBoard`**: A pure in-memory, strongly-typed data structure used to pass state and artifacts (e.g., paths, URLs, TaskIDs) between nodes. It decouples Nodes from the DB Model (`MeetingTask`).
- **`PipelineNode`**: A protocol defining `run(board:services:)`. Nodes are only responsible for executing business logic and updating the Board, not modifying the Task directly.
- **Hydration/Persistence**: `MeetingPipelineManager` handles converting `MeetingTask` to `PipelineBoard` (Hydration) before the pipeline starts, and syncing the Board's state back to `MeetingTask` (Persistence) after each node executes.
- Concrete Node classes (e.g. `TranscodeNode`, `UploadNode`) are defined in `PipelineNodes.swift`.

This keeps the UI-facing API stable (e.g. `transcode()`, `upload()`) while allowing the implementation to be composed and resumed from any step.

## Pipeline Steps

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
    - Uses **`TranscriptParser`** to unify transcript result parsing.
    - Transcript: `Result.Transcription` URL → fetch JSON → `TranscriptParser` parses to text.
    - Summary / key points / action items:
      - `Result.Summarization` URL or inline object
      - `Result.MeetingAssistance` URL or inline object
  - Sets `task.status = completed`
- On `FAILED`:
  - Sets `task.status = failed` and stores a message in `task.lastError`
- While running:
  - The node throws a retryable error (`"Task running"`); the manager retries with a 2s delay.
  - Current retry policy: max 60 attempts (about 2 minutes).

## Tingwu Signing (ACS3-HMAC-SHA256)

`TingwuService.signRequest(_:body:)`:

- Computes `x-acs-content-sha256` from body (or empty body for GET)
- Canonicalizes method/path/query/headers
- Signs `ACS3-HMAC-SHA256\n<canonicalRequestHash>` with HMAC-SHA256 using AccessKeySecret
- Sets `Authorization` header:
  - `ACS3-HMAC-SHA256 Credential=<akId>,SignedHeaders=<...>,Signature=<...>`

The canonical request builder is tested in `Tests/VoiceMemoTests/TingwuSignatureTests.swift`.
