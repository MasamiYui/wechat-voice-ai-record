# 测试

## 文档目的

说明当前测试覆盖范围与运行方式，并强调密钥不应提交到仓库。

## 测试目标

SwiftPM 测试 Target：

- `VoiceMemoTests`

测试文件：

- `Tests/VoiceMemoTests/TingwuSignatureTests.swift`
- `Tests/VoiceMemoTests/TingwuCreateTaskTests.swift`
- `Tests/VoiceMemoTests/OSSUploadTests.swift`
- `Tests/VoiceMemoTests/PipelineBoardTests.swift`
- `Tests/VoiceMemoTests/TranscriptParserTests.swift`

## 覆盖内容

- 听悟请求签名：Canonical Request 构造与 hash 校验。
- 创建听悟任务：请求 body 构造（受功能开关影响）。
- OSS 上传连通性（需要真实凭证）。
- PipelineBoard：通道状态更新与日期路径格式化。
- TranscriptParser：转写结果解析（覆盖多种返回结构）。

## 运行方式

在仓库根目录执行：

```bash
swift test
```

## 凭证策略

不要把真实凭证硬编码提交到仓库。

需要凭证的测试使用占位符，不填写会自动 skip：

- `YOUR_ACCESS_KEY_ID`
- `YOUR_ACCESS_KEY_SECRET`
- `YOUR_TINGWU_APPKEY`
- `YOUR_PUBLIC_OSS_FILE_URL`
- `YOUR_BUCKET_NAME`

推荐流程：

- Git 中保留占位符。
- 本地临时填写、跑测试、再把文件恢复后再提交。
