# 存储与配置

## 文档目的

说明数据存在哪里、配置和密钥如何管理、日志如何落盘，便于后续扩展与排障。

## 存储实现（StorageProvider）

应用通过 `StorageProvider` 抽象存储能力，目前有两种实现：

- `SQLiteStorage`：本地存储（默认）
- `MySQLStorage`：远程 MySQL 存储（基于 `mysql-kit`）

具体使用哪一种由 `SettingsStore.storageType` 决定，并由 `StorageManager` 负责切换。

## 持久化（SQLite）

### 数据库路径

`SQLiteStorage` 会按优先级尝试：

- 首选：`~/Library/Application Support/VoiceMemo/db.sqlite3`
- 兜底：`~/Documents/VoiceMemo/db.sqlite3`
- 最后手段：临时目录下 `.../tmp/VoiceMemo/db.sqlite3`

### 表结构

表 `meeting_tasks` 保存完整任务状态：

#### 核心字段

| 字段名 | 类型 | 说明 |
| :--- | :--- | :--- |
| `id` | TEXT (PK) | 任务唯一标识 (UUID) |
| `created_at` | DATETIME | 任务创建时间 |
| `recording_id` | TEXT | 关联录音文件的 ID |
| `original_file_url` | TEXT | 原始音频 OSS URL (备份) |
| `local_file_path` | TEXT | 本地原始合成音频路径 |
| `oss_url` | TEXT | 上传后的公网 URL (混合/转码后) |
| `tingwu_task_id` | TEXT | 听悟任务 ID |
| `status` | TEXT | 任务状态 (recorded, uploadingOriginal, uploadedOriginal, transcoding, transcoded, uploading, uploaded, created, polling, completed, failed) |
| `title` | TEXT | 任务标题 |

#### AI 处理结果

| 字段名 | 类型 | 说明 |
| :--- | :--- | :--- |
| `transcript` | TEXT | 完整转写文本 |
| `summary` | TEXT | AI 生成的内容摘要 |
| `key_points` | TEXT | 关键点总结 |
| `action_items` | TEXT | 待办事项/行动点 |
| `raw_response` | TEXT | 听悟接口返回的原始 JSON 响应 |

#### 双人分离识别模式 (Separated Mode)

| 字段名 | 类型 | 说明 |
| :--- | :--- | :--- |
| `mode` | TEXT | 识别模式 (`mixed` 或 `separated`) |
| `speaker1_audio_path` | TEXT | 说话人1的本地音频路径 |
| `speaker2_audio_path` | TEXT | 说话人2的本地音频路径 |
| `speaker2_oss_url` | TEXT | 说话人2上传后的公网 URL |
| `speaker2_tingwu_task_id` | TEXT | 说话人2的听悟任务 ID |
| `speaker1_transcript` | TEXT | 说话人1的转写文本 |
| `speaker2_transcript` | TEXT | 说话人2的转写文本 |
| `aligned_conversation` | TEXT | 经过时间戳对齐后的对话流 (JSON) |
| `speaker1_status` | TEXT | 说话人1的任务状态 |
| `speaker2_status` | TEXT | 说话人2的任务状态 |
| `speaker1_failed_step` | TEXT | 说话人1失败的流水线步骤（如有） |
| `speaker2_failed_step` | TEXT | 说话人2失败的流水线步骤（如有） |

#### 重试与错误处理

| 字段名 | 类型 | 说明 |
| :--- | :--- | :--- |
| `last_error` | TEXT | 最后一次失败的错误信息 |
| `failed_step` | TEXT | 失败的流水线步骤 |
| `retry_count` | INTEGER | 已重试次数 |
| `last_successful_status` | TEXT | 最后一次成功的状态（用于断点续传） |

写入采用 `insert(or: .replace)`，以 `id` 为主键。

### 历史列表

`HistoryStore` 在初始化时加载任务，并提供：

- `refresh()`：按 `created_at` 倒序重新拉取
- `deleteTask(at:)`：按 UUID 删除任务记录

## 持久化（MySQL）

`MySQLStorage` 与 SQLite 采用相同的逻辑字段集，并通过 `CREATE TABLE IF NOT EXISTS` 创建 `meeting_tasks` 表。

连接信息来自设置项：

- Host / Port / User / Database（UserDefaults）
- Password（Keychain，见下文）

## 配置（UserDefaults）

`SettingsStore` 通过 UserDefaults 保存非密钥配置：

- 存储：`storageType`（`local` 或 `mysql`）
- MySQL：host/port/user/database
- OSS：region/bucket/prefix/endpoint
- 听悟：appKey、language
- 功能开关：summary/key points/action items/role split
- 日志：verbose 开关

## 密钥（Keychain）

`KeychainHelper` 使用 service：

- `cn.mistbit.voicememo.secrets`

accounts：

- `aliyun_ak_id`
- `aliyun_ak_secret`
- `mysql_password`

`SettingsStore` 不会在 UI 层暴露明文密钥，只提供：

- `hasAccessKeyId` / `hasAccessKeySecret`
- save/read/clear 方法

## 日志

`SettingsStore.log(_:)`：

- 永远输出到控制台。
- 落盘条件：
  - 开启 verbose，或
  - message 包含 `error` / `failed` / `test` / `system`

日志文件路径：

- `~/Library/Application Support/VoiceMemo/Logs/app.log`

设置页提供：

- 展示日志路径
- 打开日志目录
- 清空日志
