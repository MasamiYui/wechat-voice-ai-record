# VoiceMemo Docs

- Start here: 01-architecture-overview.md
- 中文入口: README.zh-CN.md

## Architecture Overview

VoiceMemo uses a **multi-provider ASR architecture** that supports pluggable transcription services via the `TranscriptionService` protocol. Currently supported providers:

- **Alibaba Cloud Tingwu**: Full-featured ASR with intelligent summary generation
- **Volcengine (ByteDance)**: Alternative ASR provider with V3 API support

See [01-architecture-overview.md](01-architecture-overview.md) for detailed architecture information.

## Index

- 00-doc-conventions.md
- 01-architecture-overview.md
- 02-audio-capture-and-merge.md
- 03-pipeline-asr-oss.md
- 04-storage-and-settings.md
- 05-permissions-and-signing.md
- 06-testing.md
- 08-import-guide.md
- 09-security-and-audit.md
