# 流水线：转码 → OSS → ASR (听悟/火山)

## 文档目的

说明录音保存后（或导入音频后），在 UI 中手动触发的流水线节点：转码、上传 OSS、创建转写任务与轮询结果。

## 关键文件

- `Sources/VoiceMemo/Views/PipelineView.swift`
- `Sources/VoiceMemo/Services/MeetingPipelineManager.swift`
- `Sources/VoiceMemo/Services/Pipeline/PipelineBoard.swift`
- `Sources/VoiceMemo/Services/Pipeline/PipelineNodes.swift`
- `Sources/VoiceMemo/Services/Pipeline/TranscriptParser.swift`
- `Sources/VoiceMemo/Services/OSSService.swift`
- `Sources/VoiceMemo/Services/TranscriptionService.swift` (协议)
- `Sources/VoiceMemo/Services/TingwuService.swift` (阿里云实现)
- `Sources/VoiceMemo/Services/VolcengineService.swift` (字节跳动实现)

## 流水线管理器

应用使用单一流水线管理器：

- **`MeetingPipelineManager`**：处理流水线任务。

内部实现使用了**PipelineBoard（黑板模式）**来编排节点：

- **`PipelineBoard`**：纯内存、强类型的数据结构，用于在节点间传递状态和产物（如路径、URL、TaskID）。它解耦了 Node 与 DB Model (`MeetingTask`)。
- **`PipelineNode`**：协议，定义 `run(board:services:)`。Node 只负责执行业务逻辑并更新 Board，不直接修改 Task。
- **Hydration/Persistence**：`MeetingPipelineManager` 负责在流水线开始前将 `MeetingTask` 转换为 `PipelineBoard`（Hydration），并在每个节点执行后将 Board 的状态同步回 `MeetingTask`（Persistence）。
- 具体的 Node 类（如 `TranscodeNode`, `UploadNode`）定义在 `PipelineNodes.swift` 中。

这样 `PipelineView` 仍可以通过 `transcode()` / `upload()` / `createTask()` / `pollStatus()` 触发，但底层会映射为"从某个 step 开始跑完整链路"。

## 多提供商 ASR 架构

应用通过 `TranscriptionService` 协议支持多个 ASR（自动语音识别）提供商：

- **`TranscriptionService`**：定义转录服务接口的协议
  - `createTask(fileUrl:)`：提交音频文件进行转录
  - `getTaskInfo(taskId:)`：查询任务状态并获取结果
  - `fetchJSON(url:)`：从 URL 获取 JSON 数据的辅助方法

- **`TingwuService`**：阿里云听悟实现
  - 使用 ACS3-HMAC-SHA256 签名认证
  - 端点：`https://tingwu.cn-beijing.aliyuncs.com/openapi/tingwu/v2/tasks`

- **`VolcengineService`**：字节跳动火山引擎实现
  - 使用基于 Header 的认证（X-Api-App-Key, X-Api-Access-Key, X-Api-Resource-Id）
  - 端点：`https://openspeech.bytedance.com/api/v3/auc/bigmodel`
  - 支持自动格式推断和说话人分离

提供商选择由 `SettingsStore.asrProvider` 控制，并通过工厂模式在 `MeetingPipelineManager` 中连接。

## 流水线节点

1. 上传原文件 (Raw) 到 OSS
2. 转码
3. 上传转码文件 (Mixed) 到 OSS
4. 创建转写任务 (ASR)
5. 刷新状态（轮询并拉取结果）

`PipelineView` 为每个步骤提供手动控制按钮，并高亮显示建议的下一步操作。

## 上传原文件 (Raw)

`UploadOriginalNode` → `OSSService.uploadFile()`：

- 目的：在转码前备份原始高保真音频（如 m4a/wav）。
- ObjectKey 规则：
  - `"<ossPrefix><yyyy/MM/dd>/<recordingId>/original.<ext>"`
- 更新：
  - `task.originalFileUrl`
  - `task.status`：`recorded` → `uploadingRaw` → `uploadedRaw`

## 转码

`MeetingPipelineManager.transcode()` 用于触发流水线开始，实际转码由 `TranscodeNode` 执行：

- 输入：`task.localFilePath`（通常是 `...mixed.m4a`）
- 输出：同目录下的 `mixed_48k.m4a`
- 使用 `AVAssetExportSession` + `AVAssetExportPresetAppleM4A`
- 更新：
  - `task.localFilePath` 指向转码后的文件
  - `task.status`：`transcoding` → `transcoded`（失败则 `failed`）

## 上传转码文件 (Mixed) 到 OSS

`UploadNode` → `OSSService.uploadFile()`：

- ObjectKey 规则：
  - `"<ossPrefix><yyyy/MM/dd>/<recordingId>/mixed.m4a"`
- 说明：
  - 本地转码文件名使用 `mixed_48k.m4a`，但 OSS objectKey 仍保持 `mixed.m4a`。
- 返回：
  - `publicUrl = https://<bucket>.<endpointHost>/<objectKey>`
- 更新：
  - `task.ossUrl`
  - `task.status`：`uploading` → `uploaded`

## 创建转写任务

`CreateTaskNode` 根据配置的 ASR Provider 调用对应服务：

### 阿里云听悟 (`TingwuService`)

- 请求：`PUT https://tingwu.cn-beijing.aliyuncs.com/openapi/tingwu/v2/tasks?type=offline`
- 鉴权：ACS3-HMAC-SHA256 (AK/SK)
- 参数：AppKey、FileUrl、功能开关 (Summary, Diarization等)

功能开关影响参数：

- 摘要：`SummarizationEnabled`, `Summarization.Types`
- 关键点/行动项：`MeetingAssistanceEnabled`, `MeetingAssistance.Types`
- 角色分离：`Transcription.DiarizationEnabled` 和 `SpeakerCount`

成功后：
- 保存 `task.tingwuTaskId`
- 状态进入 `polling`

### 字节跳动火山引擎 (`VolcengineService`)

- 接口：V3 BigModel API (`api/v3/auc/bigmodel/submit`)
- 鉴权：Header 鉴权
  - `X-Api-App-Key` (AppID)
  - `X-Api-Access-Key` (AccessToken)
  - `X-Api-Resource-Id` (Cluster ID)
- 流程：
  - 客户端生成 UUID 作为 `X-Api-Request-Id`。
  - 提交任务成功返回 200 OK（无 body）。
  - 默认强制开启说话人分离 (`enable_speaker_info=true`, `ssd_version=200`)。

请求参数：

- `model_name`: "bigmodel"
- `enable_speaker_info`: true (说话人分离)
- `enable_itn`: true (逆文本标准化)
- `enable_punc`: true (标点)
- `ssd_version`: "200"

成功后：
- 返回 200 OK，body 为空
- Task ID 是客户端发送的 `X-Api-Request-Id` 中的 UUID
- 状态进入 `polling`

## 轮询与解析结果

`PollingNode` 调用 `activeTranscriptionService.getTaskInfo(taskId:)`：

- **状态判定**：
  - `Tingwu`：根据返回的 Status 字段 (`SUCCESS`, `COMPLETED`, `FAILED`)。
  - `Volcengine`：查询接口 (`/query`) 返回完整 JSON。若 `text` 和 `utterances` 均为空且无 `duration` 信息，视为 `RUNNING`；否则视为 `SUCCESS`。

- **结果解析 (`TranscriptParser`)**：
  - 采用 **Strategy 模式** 支持多种格式。
  - `TingwuParser`：解析 `Result.Transcription` 中的 `Paragraphs` / `Sentences`。
  - `VolcengineParser`：解析 `result.utterances` 中的 `text` 和 `additions.speaker`。
  - **统一格式**：所有说话人名称均会被格式化为 `Speaker X`（例如 `Speaker 1`, `Speaker Alice`）。

- **保存**：
  - `task.transcript`：纯文本格式的对话记录。
  - `task.rawResponse`：原始 JSON 响应备份。
  - `task.status`：`completed` 或 `failed`。

## 转录解析器

`TranscriptParser` 为不同提供商的响应格式提供统一解析：

- **`TingwuParser`**：解析阿里云听悟格式
  - 处理 `Result.Transcription` 的句子级别片段
  - 从 `SpeakerId` 字段提取说话人信息

- **`VolcengineParser`**：解析字节跳动火山引擎格式
  - 处理 `utterances` 数组及其说话人信息
  - 如果 utterances 不可用，则回退到 `text` 字段
  - 从 `speaker` 字段或 `additions.speaker` 提取说话人

两个解析器都将输出规范化为一致的带说话人标签的文本格式。

## 听悟签名（ACS3-HMAC-SHA256）

`TingwuService.signRequest(_:body:)`：

- 计算 `x-acs-content-sha256`
- Canonicalize method/path/query/headers
- 使用 AccessKeySecret 对 `ACS3-HMAC-SHA256\n<canonicalRequestHash>` 做 HMAC-SHA256
- 写入 `Authorization` header

规范请求构建器在 `Tests/VoiceMemoTests/TingwuSignatureTests.swift` 中测试。

## 火山引擎认证

`VolcengineService` 使用基于 Header 的认证：

- `X-Api-App-Key`：来自设置的 App ID
- `X-Api-Access-Key`：来自 Keychain 的 Access Token
- `X-Api-Resource-Id`：来自设置的 Resource ID（集群 ID）
- `X-Api-Request-Id`：客户端生成的 UUID（用作 Task ID）
- `X-Api-Sequence`：始终为 "-1"

不需要签名计算；认证基于访问令牌。

请求构造在 `Tests/VoiceMemoTests/VolcengineTests.swift` 中测试。
