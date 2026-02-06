# VoiceMemo 文档

- 从这里开始：01-architecture-overview.zh-CN.md
- English entry: README.md

## 架构概览

VoiceMemo 采用**多提供商 ASR 架构**，通过 `TranscriptionService` 协议支持可插拔的转写服务。当前支持的提供商：

- **阿里云听悟**：功能完整的 ASR 服务，支持智能摘要生成
- **火山引擎（字节跳动）**：备选 ASR 提供商，支持 V3 API

详见 [01-architecture-overview.zh-CN.md](01-architecture-overview.zh-CN.md)。

## 目录

- 00-doc-conventions.zh-CN.md
- 01-architecture-overview.zh-CN.md
- 02-audio-capture-and-merge.zh-CN.md
- 03-pipeline-asr-oss.zh-CN.md
- 04-storage-and-settings.zh-CN.md
- 05-permissions-and-signing.zh-CN.md
- 06-testing.zh-CN.md
- 08-import-guide.zh-CN.md
- 09-security-and-audit.zh-CN.md
