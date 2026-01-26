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

## 流水线节点 (混合模式)

1. 转码
2. 上传 OSS
3. 创建听悟任务
4. 刷新状态（轮询并拉取结果）

`PipelineView` 根据 `MeetingTask.status` 决定展示哪个按钮。

## 转码

`MeetingPipelineManager.transcode()`：

- 输入：`task.localFilePath`（通常是 `...mixed.m4a`）
- 输出：同目录下的 `mixed_48k.m4a`
- 使用 `AVAssetExportSession` + `AVAssetExportPresetAppleM4A`
- 更新：
  - `task.localFilePath` 指向转码后的文件
  - 成功：`task.status = transcoded`
  - 失败：`task.status = failed`

## 上传 OSS

`MeetingPipelineManager.upload()` → `OSSService.uploadFile()`：

- ObjectKey 规则：
  - `"<ossPrefix><yyyy/MM/dd>/<recordingId>/mixed.m4a"`
- 返回：
  - `publicUrl = https://<bucket>.<endpointHost>/<objectKey>`
- 更新：
  - `task.ossUrl`
  - `task.status = uploaded`

## 创建听悟任务

`MeetingPipelineManager.createTask()` → `TingwuService.createTask()`：

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

`MeetingPipelineManager.pollStatus()`：

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

## 听悟签名（ACS3-HMAC-SHA256）

`TingwuService.signRequest(_:body:)`：

- 计算 `x-acs-content-sha256`（PUT 用 body，GET 用空 body）
- Canonicalize method/path/query/headers
- 使用 AccessKeySecret 对 `ACS3-HMAC-SHA256\n<canonicalRequestHash>` 做 HMAC-SHA256
- 写入 `Authorization`：
  - `ACS3-HMAC-SHA256 Credential=<akId>,SignedHeaders=<...>,Signature=<...>`

Canonical Request 的构造在 `Tests/VoiceMemoTests/TingwuSignatureTests.swift` 中有测试用例。
