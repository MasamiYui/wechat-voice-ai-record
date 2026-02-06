# 安全与审计说明

## 文档目的

从“安全审计”的视角，说明 VoiceMemo 会处理哪些数据、数据存放在哪里、哪些数据会离开本机、以及审计时应重点核查哪些点。

## 范围 / 非目标

- 范围：macOS 客户端运行时行为、本地持久化、网络出站、密钥管理与日志行为。
- 非目标：阿里云服务端内部实现与第三方基础设施保障。

## 数据清单

### 音频数据

- 应用会录制系统/应用音频与本地麦克风音频，并落盘为文件。
- 录音结束后会生成混合后的音频文件（`mixed.m4a`）。
- 默认输出路径与命名规则见项目根目录 README。

### 派生内容（会议文本）

- 转写文本与会议纪要（摘要/要点/行动项）可能以文本形式持久化到存储。
- 听悟接口返回的原始 JSON 可能被保存用于排障与兼容。

### 配置项（UserDefaults）

非密钥配置由 UserDefaults 保存，详见：`doc/04-storage-and-settings.zh-CN.md`。

当前重要 Key：

- `storageType`：`local` / `mysql`
- `appTheme`：`system` / `light` / `dark`

### 密钥（Keychain）

密钥存储在 Keychain，不存放在 UserDefaults，详见：`doc/04-storage-and-settings.zh-CN.md`。

accounts：

- `aliyun_ak_id`
- `aliyun_ak_secret`
- `volc_access_token`
- `mysql_password`

## 权限与 Entitlements

权限与签名相关说明见：`doc/05-permissions-and-signing.zh-CN.md`。

审计关注点：

- 屏幕录制权限用于 ScreenCaptureKit 采集系统/应用音频。
- 麦克风权限用于采集本地音轨。
- Entitlements 应与实际功能匹配，避免引入未使用的权限项扩大权限面。

## 网络出站

应用可能发起的出站连接包括：

- OSS 上传（提供音频文件 URL 供 ASR 使用）。
- 听悟 API 请求（创建/轮询离线任务并拉取结果）- 使用阿里云提供商时。
- 火山引擎 API 请求（创建/轮询离线任务并拉取结果）- 使用字节跳动提供商时。
- MySQL（当开启远程存储时）。

审计关注点：

- 必要的网络目标应尽量可配置（例如 OSS endpoint）。
- 禁止把密钥以明文写入日志或持久化到非 Keychain 的位置。
- 火山引擎使用 `openspeech.bytedance.com` 域名进行 API 请求。

## 日志与隐私信息

日志行为由 `Sources/VoiceMemo/Services/SettingsStore.swift`（`log(_:)`）实现，并在 `doc/04-storage-and-settings.zh-CN.md` 中说明。

审计关注点：

- 日志仅在启用 verbose 或消息命中指定关键字时落盘，落盘位置为 Application Support 下的 Logs。
- 避免在日志中输出 AK/SK、签名串、Authorization header 等敏感信息。
- 将转写文本与会议纪要视为敏感内容，避免写入日志。

## 主题模式（自动/浅色/深色）

主题选择在 Settings 中暴露，并以 `appTheme` 保存到 UserDefaults。

运行时行为：

- 应用启动和配置项变更时应用主题外观。
- 当 `appTheme == system` 时，监听系统主题变更通知，并重新应用系统外观。

审计关注点：

- 主题功能不新增权限、不访问用户数据、不会产生网络出站。
- 系统主题变更监听使用通知观察者，并在应用退出时移除，避免生命周期泄漏。

相关代码路径：

- `Sources/VoiceMemo/Services/SettingsStore.swift`：`AppTheme`、`appTheme` 持久化
- `Sources/VoiceMemo/VoiceMemoApp.swift`：主题应用与系统主题通知转发
- `Sources/VoiceMemo/Views/SettingsView.swift`：设置页 UI

## 审计检查清单

- 密钥只存在 Keychain：UserDefaults、日志、仓库均不应出现明文密钥。
- 开启 verbose 日志后，确认日志不包含凭证、签名串、Authorization header。
- 确认音频与派生文本只写入文档说明的位置与存储后端。
- 确认权限申请与 Entitlements 与实际功能一致（无多余权限项）。
- 确认主题变更观察者只注册一次，并在退出时移除。
