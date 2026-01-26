# VoiceMemo

A professional, high-fidelity audio recording utility for macOS, specifically designed to capture real-time WeChat voice conversations using the native **ScreenCaptureKit** and **AVFoundation** frameworks.

Read this in Chinese: [README_CN.md](README_CN.md)

## Features

- **Dual-Track Recording**: Simultaneously captures system audio (remote voice) and microphone input (local voice).
- **Automatic Merging**: Intelligently mixes both tracks into a single high-quality audio file post-recording.
- **Intelligent App Detection**: Automatically filters and prioritizes WeChat for seamless capture.
- **Native Performance**: Built with SwiftUI and ScreenCaptureKit for optimal performance and low CPU overhead.
- **Privacy-First**: Operates locally on your machine with clear permission handling.
- **Meeting Minutes (Alibaba Cloud Tingwu + OSS)**: Manual pipeline to transcribe audio and generate structured minutes (summary, key points, action items), with Markdown export.
- **Storage Backends (SQLite/MySQL)**: Store history locally or in MySQL, with optional local-to-MySQL sync.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for full release history.

## Recognition Modes

The app now supports two recognition modes to cater to different meeting scenarios:

- **Mixed Mode (Default)**: Combines all audio sources into a single track. This is suitable for general recordings and simpler transcription needs.
- **Dual-Speaker Separated Mode**: Specifically designed for 1-on-1 calls. It treats System Audio as Speaker 2 (Remote) and Microphone as Speaker 1 (Local). Each track is recognized independently, providing better speaker identification and alignment in the final minutes.

## Requirements

- **OS**: macOS 13.0 (Ventura) or later.
- **Hardware**: Any Mac supporting macOS 13.0+.
- **Development**: Xcode 14.1+ for building and signing.

## Architecture

```mermaid
flowchart LR
  subgraph Local["Local (macOS app)"]
    A["AudioRecorder<br/>ScreenCaptureKit + AVFoundation"] -->|Mixed Mode| B["Merge Tracks<br/>remote + mic"]
    A -->|Separated Mode| C["MeetingTask"]
    B --> C
    C --> D["MeetingPipelineManager<br/>State machine"]
    D -->|Transcode| E["AVAssetExportSession<br/>mixed_48k.m4a"]
    D -->|Persist| SM["StorageManager<br/>StorageProvider"]
    D -->|Config| S["SettingsStore"]
    S --> K["KeychainHelper<br/>AK/SK"]
    SM -->|Local| J1["SQLiteStorage<br/>SQLite"]
    SM -->|Remote| J2["MySQLStorage<br/>mysql-kit"]
    J1 --> V["SwiftUI Views<br/>SettingsView / PipelineView / ResultView"]
    J2 --> V
  end

  subgraph Cloud["Alibaba Cloud"]
    F["OSSService<br/>PutObject"] --> G["OSS Bucket<br/>Public URL"]
    T["TingwuService<br/>CreateTask / GetTaskInfo"] --> R["Tingwu Offline ASR<br/>Minutes JSON"]
  end

  D -->|Upload| F
  G -->|FileUrl| T
  T -->|Result| D
```

## Project Structure

- `Sources/`: Core Swift implementation.
- `Package.swift`: Swift Package Manager configuration.
- `package_app.sh`: Automated build and ad-hoc signing script.
- `Info.plist`: Application configuration and permission strings.

## Getting Started

### 1. Build and Run (recommended)

Due to macOS security requirements (ScreenCaptureKit needs specific entitlements and signing), we provide a convenience script for local execution:

```bash
chmod +x package_app.sh
./package_app.sh
open VoiceMemo.app
```

### 2. Permissions

When you first start recording, macOS will request the following permissions:
- **Screen Recording**: Required by ScreenCaptureKit to capture system/app audio.
- **Microphone**: Required to capture your own voice.

Please grant these permissions in **System Settings > Privacy & Security**.

### 3. Configure Tingwu + OSS (optional)

Open Settings in the app and configure:
- Alibaba Cloud AccessKeyId / AccessKeySecret (stored in Keychain)
- Tingwu AppKey
- OSS bucket / region / prefix

### 4. Audio Outputs

Recorded audio files are saved to:

- `~/Downloads/VoiceMemoRecordings/`

Filenames:

- `recording-<timestamp>-remote.m4a`: Remote/system audio.
- `recording-<timestamp>-local.m4a`: Local microphone audio.
- `recording-<timestamp>-mixed.m4a`: Merged conversation (Mixed mode).

Imported audio files are copied into the app sandbox:

- `~/Library/Application Support/VoiceMemo/recordings/` (filename: `<uuid>.<ext>`)

### 5. Generate minutes

After a recording completes, the latest task appears in the pipeline UI. Trigger the steps manually:
- Transcode → Upload → Create Task → Refresh Status
- View Result → Export Markdown

### 6. Import audio (optional)

Use the sidebar action **Import Audio** to create a meeting task from an existing audio file, then run the same pipeline steps as above.

For detailed instructions on import modes (Meeting vs Dictation), please refer to the [Audio Import Guide](doc/08-import-guide.md).

## Development

To open the project in Xcode for debugging:

```bash
python3 generate_project.py
xed VoiceMemo.xcodeproj
```

Ensure you configure **Signing & Capabilities** with your Development Team to run the app with full permissions.

## Roadmap

- [x] Dual-track recording (Remote + Local)
- [x] Automatic audio merging
- [x] Audio Import (Support for external files)
- [x] Alibaba Cloud Tingwu offline transcription + minutes generation
- [x] OSS upload integration
- [x] Manual pipeline UI (transcode/upload/create/poll)
- [ ] Speaker diarization (cloud-based)
- [ ] Real-time transcription UI

## Contact

sherlock.yin1994@gmail.com

## License

[MIT License](LICENSE)
