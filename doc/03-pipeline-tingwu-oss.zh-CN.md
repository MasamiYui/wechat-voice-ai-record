# 流水线：转码 → OSS → 听悟

## 文档目的

说明录音保存后（或导入音频后），在 UI 中手动触发的流水线节点：转码、上传 OSS、创建听悟任务与轮询结果。

## 关键文件

- `Sources/VoiceMemo/Views/PipelineView.swift`
- `Sources/VoiceMemo/Services/MeetingPipelineManager.swift`
- `Sources/VoiceMemo/Services/Pipeline/PipelineBoard.swift`
- `Sources/VoiceMemo/Services/Pipeline/PipelineNodes.swift`
- `Sources/VoiceMemo/Services/Pipeline/TranscriptParser.swift`
- `Sources/VoiceMemo/Services/OSSService.swift`
- `Sources/VoiceMemo/Services/TingwuService.swift`

## 流水线管理器

应用使用单一流水线管理器：

- **`MeetingPipelineManager`**：处理流水线任务。

内部实现使用了**PipelineBoard（黑板模式）**来编排节点：

- **`PipelineBoard`**：纯内存、强类型的数据结构，用于在节点间传递状态和产物（如路径、URL、TaskID）。它解耦了 Node 与 DB Model (`MeetingTask`)。
- **`PipelineNode`**：协议，定义 `run(board:services:)`。Node 只负责执行业务逻辑并更新 Board，不直接修改 Task。
- **Hydration/Persistence**：`MeetingPipelineManager` 负责在流水线开始前将 `MeetingTask` 转换为 `PipelineBoard`（Hydration），并在每个节点执行后将 Board 的状态同步回 `MeetingTask`（Persistence）。
- 具体的 Node 类（如 `TranscodeNode`, `UploadNode`）定义在 `PipelineNodes.swift` 中。

这样 `PipelineView` 仍可以通过 `transcode()` / `upload()` / `createTask()` / `pollStatus()` 触发，但底层会映射为“从某个 step 开始跑完整链路”。

## 流水线节点

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
    - 使用 **`TranscriptParser`** 统一处理转写结果解析。
    - 转写文本：`Result.Transcription` URL → 拉取 JSON → `TranscriptParser` 解析为文本。
    - 总结/重点/行动项：
      - `Result.Summarization` URL 或内联对象
      - `Result.MeetingAssistance` URL 或内联对象
  - 设置 `task.status = completed`
- 当状态为 `FAILED`：
  - 设置 `task.status = failed` 并写入 `task.lastError`
- 运行中：
  - Node 会抛出可重试错误（`"Task running"`），由管理器以 2s 间隔重试。
  - 当前策略：最多 60 次（约 2 分钟）。

## 听悟签名（ACS3-HMAC-SHA256）

`TingwuService.signRequest(_:body:)`：

- 计算 `x-acs-content-sha256`（PUT 用 body，GET 用空 body）
- Canonicalize method/path/query/headers
- 使用 AccessKeySecret 对 `ACS3-HMAC-SHA256\n<canonicalRequestHash>` 做 HMAC-SHA256
- 写入 `Authorization`：
  - `ACS3-HMAC-SHA256 Credential=<akId>,SignedHeaders=<...>,Signature=<...>`

Canonical Request 的构造在 `Tests/VoiceMemoTests/TingwuSignatureTests.swift` 中有测试用例。
