# Architecture Overview

## Purpose

This document explains how the app is structured end-to-end: UI, recording, pipeline, storage, and cloud integrations.

## Scope / Non-goals

- Scope: macOS app runtime flow from recording to Tingwu results.
- Non-goals: Alibaba Cloud service-side behavior details.

## Key Directories

- `Sources/VoiceMemo/`
  - `VoiceMemoApp.swift`: app entry and AppDelegate activation policy.
  - `ContentView.swift`: app shell, navigation, and state wiring.
  - `AudioRecorder.swift`: dual-track audio capture and local merge (supports both mixed and separated modes).
  - `Models/MeetingTask.swift`: persisted task model and status state machine.
  - `Services/`
    - `SettingsStore.swift`: user configuration, feature toggles, logging.
    - `KeychainHelper.swift`: secret storage (RAM AK/Secret) in Keychain.
    - `OSSService.swift`: upload audio to OSS.
    - `TingwuService.swift`: create Tingwu offline task + poll task info.
    - `MeetingPipelineManager.swift`: pipeline manager (orchestrates transcode/upload/create/poll and persistence).
    - `Storage/StorageProvider.swift`: storage abstraction used by the pipeline.
    - `Storage/SQLiteStorage.swift`: local SQLite persistence for task history.
    - `Storage/MySQLStorage.swift`: MySQL persistence for task history.
    - `Storage/StorageManager.swift`: switches providers based on settings and supports sync.
    - `HistoryStore.swift`: observable wrapper for history list.
  - `Views/`: SwiftUI screens (recording, pipeline, results, settings, history).

## Runtime Components

- UI layer (SwiftUI)
  - `ContentView` builds a `NavigationSplitView` with:
    - Sidebar: `HistoryView` (Search, Import Audio, New Recording, task history)
    - Detail: `RecordingView` or `ResultView` depending on selection
  - `RecordingView` embeds `PipelineView` for the latest task.
- Domain model
  - `MeetingTask` represents a recording + cloud task lifecycle.
- Storage
  - Storage is abstracted by `StorageProvider` and selected by `StorageManager` (SQLite by default, MySQL optional).
- Cloud integrations
  - OSS for file hosting, Tingwu for transcription/summarization.

## High-level Flow

```mermaid
flowchart TD
  A[RecordingView] --> B[AudioRecorder.startRecording]
  B --> C[System audio via ScreenCaptureKit]
  B --> D[Mic audio via AVCaptureSession]
  C --> E[remote.m4a]
  D --> F[local.m4a]
  
  E --> G1{Recognition Mode}
  F --> G1
  
  G1 -->|Mixed Mode| H1[Merge with AVMutableComposition]
  H1 --> H2[mixed.m4a]
  H2 --> I1[Create MeetingTask]
  I1 --> J1[MeetingPipelineManager]
  
  G1 -->|Separated Mode| I2[Create MeetingTask]
  I2 --> J1
  
  J1 --> K[Transcode/Upload/Tingwu/Poll]
  
  K --> O[Persist transcript/summary/aligned results]
  O --> P[ResultView export Markdown]
```

## Status State Machine

Defined in `Models/MeetingTask.swift`:

- `recorded`: merged audio saved, task created locally
- `transcoding` → `transcoded`
- `uploading` → `uploaded`
- `created`: used as a transient “creating task” state in pipeline manager
- `polling` → `completed`
- `failed`: any step error

## External Dependencies

Declared in `Package.swift`:

- `ScreenCaptureKit` + `AVFoundation`: audio capture and export.
- `SQLite.swift`: local persistence.
- `mysql-kit`: optional MySQL persistence.
- `alibabacloud-oss-swift-sdk-v2`: OSS uploads.
- `CryptoKit`: Tingwu request signing (ACS3-HMAC-SHA256).
