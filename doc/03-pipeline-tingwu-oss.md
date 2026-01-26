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

## Pipeline Steps (Mixed Mode)

1. Transcode
2. Upload to OSS
3. Create Tingwu task
4. Poll status and fetch results

`PipelineView` decides which button to show based on `MeetingTask.status`.

## Transcode

`MeetingPipelineManager.transcode()`:

- Input: `task.localFilePath` (typically `...mixed.m4a`)
- Output: `mixed_48k.m4a` in the same folder
- Uses `AVAssetExportSession` with preset `AVAssetExportPresetAppleM4A`
- Updates:
  - `task.localFilePath` to the transcoded file
  - `task.status` to `transcoded` on success, `failed` on error

## Upload to OSS

`MeetingPipelineManager.upload()` → `OSSService.uploadFile()`:

- Object key format:
  - `"<ossPrefix><yyyy/MM/dd>/<recordingId>/mixed.m4a"`
- Returns:
  - `publicUrl` computed as `https://<bucket>.<endpointHost>/<objectKey>`
- Updates:
  - `task.ossUrl`
  - `task.status = uploaded`

## Create Tingwu Task

`MeetingPipelineManager.createTask()` → `TingwuService.createTask()`:

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

`MeetingPipelineManager.pollStatus()`:

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

## Tingwu Signing (ACS3-HMAC-SHA256)

`TingwuService.signRequest(_:body:)`:

- Computes `x-acs-content-sha256` from body (or empty body for GET)
- Canonicalizes method/path/query/headers
- Signs `ACS3-HMAC-SHA256\n<canonicalRequestHash>` with HMAC-SHA256 using AccessKeySecret
- Sets `Authorization` header:
  - `ACS3-HMAC-SHA256 Credential=<akId>,SignedHeaders=<...>,Signature=<...>`

The canonical request builder is tested in `Tests/VoiceMemoTests/TingwuSignatureTests.swift`.
