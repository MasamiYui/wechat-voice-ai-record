# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Multi-Provider ASR Architecture**: Refactored ASR pipeline to support pluggable providers via `TranscriptionService` protocol.
- **Volcengine Integration**: Added support for ByteDance Volcengine ASR service as an alternative to Alibaba Cloud Tingwu.
  - V3 API implementation with header-based authentication (`X-Api-App-Key`, `X-Api-Access-Key`, `X-Api-Resource-Id`).
  - Support for `utterances` and `text` result formats.
  - Settings UI for configuring Volcengine App ID, Resource ID, and Access Token.
- **Theme Mode**: Support for System (Auto) / Light / Dark appearance in Settings.
- **Security and Audit Documentation**: Added comprehensive security and audit notes (doc/09-security-and-audit.md).

### Changed
- **Task Info UI**: Redesigned the Task Info section in Result View with a grid layout, status indicators, and copy functionality for Task Key.
- **ASR Provider Identification**: Added logic to automatically infer and display the ASR provider (Volcengine/Tingwu) for existing tasks based on raw data.

## [1.1.0] - 2026-01-26

### Added
- **Audio Import**: Support for importing external audio files directly into the pipeline for transcription and summarization.
- **Enhanced Sidebar UI**: Modernized the sidebar with clear sections (Actions/History), improved button styles, and refined list items.

### Fixed
- **Log Display**: Fixed a race condition where logs were not displaying correctly in the "Show Log" view.

## [1.0.0] - 2026-01-22

### Added
- **Dual-Track Recording**: Simultaneously capture system audio (WeChat/Remote) and microphone input (Local).
- **Automatic Audio Merging**: Intelligent mixing of remote and local tracks into a single `mixed.m4a` file.
- **AI Meeting Minutes Pipeline**:
  - Integration with **Alibaba Cloud OSS** for audio storage.
  - Integration with **Alibaba Cloud Tingwu** for ASR and intelligent summary generation.
  - Support for manual pipeline triggers: Transcode, Upload, Create Task, and Result Retrieval.
- **Persistence**: SQLite-based history management for recordings and AI tasks.
- **Security**: Keychain integration for sensitive Alibaba Cloud credentials (AK/SK).
- **Modern UI**: SwiftUI-based interface with dedicated views for Recording, History, Settings, and AI Pipeline.
- **Developer Tools**: `package_app.sh` script for automated building and ad-hoc signing.
- **Comprehensive Documentation**: Detailed architecture and module-specific docs in English and Chinese.
