# 流水线：转码 → OSS → 听悟

## 文档目的

说明录音保存后（或导入音频后），在 UI 中手动触发的流水线节点：转码、上传 OSS、创建听悟任务与轮询结果。

## 关键文件

- `Sources/VoiceMemo/Views/PipelineView.swift`
- `Sources/VoiceMemo/Services/MeetingPipelineManager.swift`
- `Sources/VoiceMemo/Services/OSSService.swift`
- `Sources/VoiceMemo/Services/TingwuService.swift`

## 流水线管理器

应用使用单一流水线管理器：

- **`MeetingPipelineManager`**：同时支持“混合模式”和“分离模式”。具体行为由 `MeetingTask.mode` 决定（例如：单文件 vs 双文件的上传/创建/轮询）。

内部实现使用了简单的节点抽象来编排与续跑：

- `PipelineNode`（按 step 执行）
- `PipelineContext`（task + services + settings）

这样 `PipelineView` 仍可以通过 `transcode()` / `upload()` / `createTask()` / `pollStatus()` 触发，但底层会映射为“从某个 step 开始跑完整链路”。

## 流水线节点 (混合模式)

1. 上传原文件 (Raw) 到 OSS
2. 转码
3. 上传转码文件 (Mixed) 到 OSS
4. 创建听悟任务
5. 刷新状态（轮询并拉取结果）

`PipelineView` 为每个步骤提供手动控制按钮，并高亮显示建议的下一步操作。

## 上传原文件 (Raw)

`UploadOriginalNode` → `OSSService.uploadFile()`：

- 目的：在转码前备份原始高保真音频（如 m4a/wav）。
- ObjectKey 规则：
  - `"<ossPrefix><yyyy/MM/dd>/<recordingId>/original.<ext>"`
- 更新：
  - `task.originalFileUrl`
  - `task.status`：`recorded` → `uploadingOriginal` → `uploadedOriginal`

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

## 创建听悟任务

`CreateTaskNode` → `TingwuService.createTask()`：

- 前置条件：
  - `task.ossUrl` 为可公网访问的 URL
  - `settings.tingwuAppKey` 已配置
  - Keychain 中有阿里云 AK/Secret
- 请求：
  - `PUT https://tingwu.cn-beijing.aliyuncs.com/openapi/tingwu/v2/tasks?type=offline`
  - header `x-acs-action: CreateTask`
  - JSON body 包含 `AppKey`、`Input.FileUrl`、`Input.SourceLanguage` 与 `Parameters`

功能开关会影响参数：

- 总结：`SummarizationEnabled`、`Summarization.Types`
- 重点/行动项：`MeetingAssistanceEnabled`、`MeetingAssistance.Types`
- 角色区分：`Transcription.DiarizationEnabled` 与 `SpeakerCount`

成功后：

- 保存 `task.tingwuTaskId`
- 状态进入 `polling`

## 轮询与解析结果

`PollingNode`：

- 调用 `TingwuService.getTaskInfo(taskId:)`
- 当状态为 `SUCCESS` / `COMPLETED`：
  - 将 `Data` 对象（pretty JSON）保存到 `task.rawResponse`
  - 解析：
    - 转写文本：
      - `Result.Transcription` URL → 拉取 JSON → 解析 `Paragraphs`/`Sentences`
    - 总结/重点/行动项：
      - `Result.Summarization` URL 或内联对象
      - `Result.MeetingAssistance` URL 或内联对象
  - 设置 `task.status = completed`
- 当状态为 `FAILED`：
  - 设置 `task.status = failed` 并写入 `task.lastError`
- 运行中：
  - Node 会抛出可重试错误（`"Task running"`），由管理器以 2s 间隔重试。
  - 当前策略：最多 60 次（约 2 分钟）。

## 分离模式（双人分轨）

当 `MeetingTask.mode == separated` 时，管理器会并发跑两条单路流水线：

- Speaker 1（本地麦克风）：`speaker1AudioPath` → `ossUrl` → `tingwuTaskId` → `speaker1Transcript`
- Speaker 2（远端系统音频）：`speaker2AudioPath` → `speaker2OssUrl` → `speaker2TingwuTaskId` → `speaker2Transcript`

两条链路复用同一组 Node，通过 `targetSpeaker` 参数区分。上传 objectKey 变为：

- `"<ossPrefix><yyyy/MM/dd>/<recordingId>/speaker1.m4a"`
- `"<ossPrefix><yyyy/MM/dd>/<recordingId>/speaker2.m4a"`

### 对齐（当前实现）

`MeetingPipelineManager.tryAlign()` 目前只做“拼接”合并：将两路 transcript 按 speaker 加标题后拼到 `task.transcript`，用于展示。`alignedConversation` 仍保留给后续按时间轴对齐实现。

### 失败追踪与重试

- 混合模式：使用 `task.failedStep` 与 `task.lastError`。
- 分离模式：使用 speaker 维度字段：
  - `task.speaker1Status` / `task.speaker2Status`
  - `task.speaker1FailedStep` / `task.speaker2FailedStep`
- UI 侧重试入口：
  - `MeetingPipelineManager.retry()`：从失败 step 续跑
  - `MeetingPipelineManager.retry(speaker:)`：仅重试某一路 speaker

## 听悟签名（ACS3-HMAC-SHA256）

`TingwuService.signRequest(_:body:)`：

- 计算 `x-acs-content-sha256`（PUT 用 body，GET 用空 body）
- Canonicalize method/path/query/headers
- 使用 AccessKeySecret 对 `ACS3-HMAC-SHA256\n<canonicalRequestHash>` 做 HMAC-SHA256
- 写入 `Authorization`：
  - `ACS3-HMAC-SHA256 Credential=<akId>,SignedHeaders=<...>,Signature=<...>`

Canonical Request 的构造在 `Tests/VoiceMemoTests/TingwuSignatureTests.swift` 中有测试用例。
