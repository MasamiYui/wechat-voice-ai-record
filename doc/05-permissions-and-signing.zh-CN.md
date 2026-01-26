# 权限与签名（macOS）

## 文档目的

说明应用需要哪些权限、它们如何映射到 Info.plist/entitlements，以及“签名与身份不稳定”为什么会导致重复弹窗。

## 必要权限

### 屏幕录制

ScreenCaptureKit 采集系统音频需要屏幕录制权限。

- `Sources/VoiceMemo/Info.plist` 中的说明文案：
  - `NSScreenCaptureUsageDescription`
- 授权路径：
  - 系统设置 → 隐私与安全性 → 屏幕录制

### 麦克风

采集本地麦克风需要麦克风权限。

- `Sources/VoiceMemo/Info.plist`：
  - `NSMicrophoneUsageDescription`

## Entitlements

文件：`VoiceMemo.entitlements`

当前包含：

- `com.apple.security.app-sandbox`
- `com.apple.security.device.audio-input`
- `com.apple.security.device.camera`
- `com.apple.security.files.downloads.read-write`
- `com.apple.security.files.user-selected.read-write`
- `com.apple.security.network.client`
- `com.apple.security.personal-information.photos-library`

仅添加真实功能需要的 entitlement，避免扩大权限面导致不必要的风险与用户不信任。

## Bundle Identifier

应用身份的核心是 Bundle ID：

- `Info.plist` 的 `CFBundleIdentifier`：`cn.mistbit.voicememo`
- Xcode target 的 `PRODUCT_BUNDLE_IDENTIFIER`：`cn.mistbit.voicememo`

Bundle ID 变化会被 macOS 视为新应用身份，从而重新弹窗授权。

## 签名稳定性与重复弹窗

macOS 隐私权限授权与“应用身份 + 签名”绑定。

要让授权稳定复用：

- Bundle ID 固定不变
- Xcode 中固定 Team，并使用 Automatic signing
- 如果使用生成的 `VoiceMemo.xcodeproj`，在依赖变更后请重新运行 `generate_project.py`，保证 SwiftPM 依赖引用一致
  - 若 Xcode 出现 `No such module`，可尝试 `File > Packages > Reset Package Caches`，再 Clean Build Folder

打包脚本说明：

- `package_app.sh` 使用 ad-hoc 签名（`codesign --sign -`）
- ad-hoc 签名不具备稳定身份，换一种方式运行/签名后重复弹窗是预期现象

## 实践建议

- 调试：优先使用 Xcode + 自动签名 + 固定 Team。
- 打包脚本：适合快速本地运行/分发测试；若要减少弹窗，需要改为稳定签名策略。
