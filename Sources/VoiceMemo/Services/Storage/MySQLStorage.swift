import Foundation
import MySQLKit
import AsyncKit
import NIOSSL

enum StorageError: Error {
    case poolNotInitialized
}

final class MySQLStorage: StorageProvider, @unchecked Sendable {
    private let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    private var pool: EventLoopGroupConnectionPool<MySQLConnectionSource>?
    private var isShutdown = false
    
    struct Config: Sendable {
        let host: String
        let port: Int
        let user: String
        let password: String
        let database: String
    }
    
    private let config: Config
    
    init(config: Config) {
        self.config = config
        setupPool()
    }

    deinit {
        shutdown()
    }
    
    private func setupPool() {
        var tlsConfig = TLSConfiguration.makeClientConfiguration()
        tlsConfig.certificateVerification = .none
        
        let mysqlConfig = MySQLConfiguration(
            hostname: config.host,
            port: config.port,
            username: config.user,
            password: config.password,
            database: config.database,
            tlsConfiguration: tlsConfig
        )
        
        let source = MySQLConnectionSource(configuration: mysqlConfig)
        self.pool = EventLoopGroupConnectionPool(source: source, on: group)
    }

    func shutdown() {
        if isShutdown {
            return
        }
        isShutdown = true
        if let pool = pool {
            self.pool = nil
            pool.shutdown()
        }
        try? group.syncShutdownGracefully()
    }
    
    func createTableIfNeeded() async throws {
        guard let pool = pool else {
            throw StorageError.poolNotInitialized
        }
        let sql = """
        CREATE TABLE IF NOT EXISTS meeting_tasks (
            id VARCHAR(36) PRIMARY KEY,
            created_at DATETIME NOT NULL,
            recording_id VARCHAR(255) NOT NULL,
            local_file_path TEXT NOT NULL,
            oss_url TEXT,
            tingwu_task_id VARCHAR(255),
            status VARCHAR(50) NOT NULL,
            title TEXT NOT NULL,
            raw_response TEXT,
            transcript TEXT,
            summary TEXT,
            key_points TEXT,
            action_items TEXT,
            last_error TEXT,
            task_key VARCHAR(255),
            api_status VARCHAR(50),
            status_text TEXT,
            biz_duration INT,
            output_mp3_path TEXT,
            last_successful_status VARCHAR(50),
            failed_step VARCHAR(50),
            retry_count INT DEFAULT 0,
            mode VARCHAR(20) DEFAULT 'mixed',
            speaker1_audio_path TEXT,
            speaker2_audio_path TEXT,
            speaker2_oss_url TEXT,
            speaker2_tingwu_task_id VARCHAR(255),
            speaker1_transcript TEXT,
            speaker2_transcript TEXT,
            aligned_conversation TEXT,
            speaker1_status VARCHAR(50),
            speaker2_status VARCHAR(50),
            speaker1_failed_step VARCHAR(50),
            speaker2_failed_step VARCHAR(50),
            original_oss_url TEXT,
            speaker2_original_oss_url TEXT
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        """
        _ = try await pool.withConnection { conn in
            conn.query(sql)
        }.get()
        
        let existingColumns: Set<String> = try await pool.withConnection { conn in
            conn.query(
                "SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = ? AND TABLE_NAME = 'meeting_tasks'",
                [MySQLData(string: self.config.database)]
            ).flatMapThrowing { rows in
                Set(rows.compactMap { $0.column("COLUMN_NAME")?.string })
            }
        }.get()
        
        if !existingColumns.contains("speaker1_failed_step") {
            _ = try await pool.withConnection { conn in
                conn.query("ALTER TABLE meeting_tasks ADD COLUMN speaker1_failed_step VARCHAR(50)")
            }.get()
        }
        
        if !existingColumns.contains("speaker2_failed_step") {
            _ = try await pool.withConnection { conn in
                conn.query("ALTER TABLE meeting_tasks ADD COLUMN speaker2_failed_step VARCHAR(50)")
            }.get()
        }

        if !existingColumns.contains("original_oss_url") {
            _ = try await pool.withConnection { conn in
                conn.query("ALTER TABLE meeting_tasks ADD COLUMN original_oss_url TEXT")
            }.get()
        }
        
        if !existingColumns.contains("speaker2_original_oss_url") {
            _ = try await pool.withConnection { conn in
                conn.query("ALTER TABLE meeting_tasks ADD COLUMN speaker2_original_oss_url TEXT")
            }.get()
        }
    }
    
    func fetchTasks() async throws -> [MeetingTask] {
        guard let pool = pool else {
            throw StorageError.poolNotInitialized
        }
        return try await pool.withConnection { conn in
            conn.query("SELECT * FROM meeting_tasks ORDER BY created_at DESC").flatMapThrowing { rows in
                rows.compactMap { self.mapRowToTask($0) }
            }
        }.get()
    }
    
    func saveTask(_ task: MeetingTask) async throws {
        guard let pool = pool else {
            throw StorageError.poolNotInitialized
        }
        
        let sql = """
        INSERT INTO meeting_tasks (
            id, created_at, recording_id, local_file_path, oss_url, tingwu_task_id,
            status, title, raw_response, transcript, summary, key_points,
            action_items, last_error, task_key, api_status, status_text,
            biz_duration, output_mp3_path, last_successful_status, failed_step,
            retry_count, mode, speaker1_audio_path, speaker2_audio_path,
            speaker2_oss_url, speaker2_tingwu_task_id, speaker1_transcript,
            speaker2_transcript, aligned_conversation, speaker1_status, speaker2_status,
            speaker1_failed_step, speaker2_failed_step, original_oss_url, speaker2_original_oss_url
        ) VALUES (
            ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
        ) ON DUPLICATE KEY UPDATE
            recording_id=VALUES(recording_id), local_file_path=VALUES(local_file_path),
            oss_url=VALUES(oss_url), tingwu_task_id=VALUES(tingwu_task_id),
            status=VALUES(status), title=VALUES(title), raw_response=VALUES(raw_response),
            transcript=VALUES(transcript), summary=VALUES(summary), key_points=VALUES(key_points),
            action_items=VALUES(action_items), last_error=VALUES(last_error),
            task_key=VALUES(task_key), api_status=VALUES(api_status), status_text=VALUES(status_text),
            biz_duration=VALUES(biz_duration), output_mp3_path=VALUES(output_mp3_path),
            last_successful_status=VALUES(last_successful_status), failed_step=VALUES(failed_step),
            retry_count=VALUES(retry_count), mode=VALUES(mode),
            speaker1_audio_path=VALUES(speaker1_audio_path), speaker2_audio_path=VALUES(speaker2_audio_path),
            speaker2_oss_url=VALUES(speaker2_oss_url), speaker2_tingwu_task_id=VALUES(speaker2_tingwu_task_id),
            speaker1_transcript=VALUES(speaker1_transcript), speaker2_transcript=VALUES(speaker2_transcript),
            aligned_conversation=VALUES(aligned_conversation), speaker1_status=VALUES(speaker1_status),
            speaker2_status=VALUES(speaker2_status),
            speaker1_failed_step=VALUES(speaker1_failed_step),
            speaker2_failed_step=VALUES(speaker2_failed_step),
            original_oss_url=VALUES(original_oss_url),
            speaker2_original_oss_url=VALUES(speaker2_original_oss_url);
        """
        
        _ = try await pool.withConnection { conn in
            let binds: [MySQLData] = [
                MySQLData(string: task.id.uuidString),
                MySQLData(date: task.createdAt),
                MySQLData(string: task.recordingId),
                MySQLData(string: task.localFilePath),
                task.ossUrl.map { MySQLData(string: $0) } ?? .null,
                task.tingwuTaskId.map { MySQLData(string: $0) } ?? .null,
                MySQLData(string: task.status.rawValue),
                MySQLData(string: task.title),
                task.rawResponse.map { MySQLData(string: $0) } ?? .null,
                task.transcript.map { MySQLData(string: $0) } ?? .null,
                task.summary.map { MySQLData(string: $0) } ?? .null,
                task.keyPoints.map { MySQLData(string: $0) } ?? .null,
                task.actionItems.map { MySQLData(string: $0) } ?? .null,
                task.lastError.map { MySQLData(string: $0) } ?? .null,
                task.taskKey.map { MySQLData(string: $0) } ?? .null,
                task.apiStatus.map { MySQLData(string: $0) } ?? .null,
                task.statusText.map { MySQLData(string: $0) } ?? .null,
                task.bizDuration.map { MySQLData(int: $0) } ?? .null,
                task.outputMp3Path.map { MySQLData(string: $0) } ?? .null,
                task.lastSuccessfulStatus.map { MySQLData(string: $0.rawValue) } ?? .null,
                task.failedStep.map { MySQLData(string: $0.rawValue) } ?? .null,
                MySQLData(int: task.retryCount),
                MySQLData(string: task.mode.rawValue),
                task.speaker1AudioPath.map { MySQLData(string: $0) } ?? .null,
                task.speaker2AudioPath.map { MySQLData(string: $0) } ?? .null,
                task.speaker2OssUrl.map { MySQLData(string: $0) } ?? .null,
                task.speaker2TingwuTaskId.map { MySQLData(string: $0) } ?? .null,
                task.speaker1Transcript.map { MySQLData(string: $0) } ?? .null,
                task.speaker2Transcript.map { MySQLData(string: $0) } ?? .null,
                task.alignedConversation.map { MySQLData(string: $0) } ?? .null,
                task.speaker1Status.map { MySQLData(string: $0.rawValue) } ?? .null,
                task.speaker2Status.map { MySQLData(string: $0.rawValue) } ?? .null,
                task.speaker1FailedStep.map { MySQLData(string: $0.rawValue) } ?? .null,
                task.speaker2FailedStep.map { MySQLData(string: $0.rawValue) } ?? .null,
                task.originalOssUrl.map { MySQLData(string: $0) } ?? .null,
                task.speaker2OriginalOssUrl.map { MySQLData(string: $0) } ?? .null
            ]
            return conn.query(sql, binds)
        }.get()
    }

    func updateTaskStatus(id: UUID, status: MeetingTaskStatus) async throws {
        guard let pool = pool else {
            throw StorageError.poolNotInitialized
        }
        _ = try await pool.withConnection { conn in
            conn.query("UPDATE meeting_tasks SET status = ? WHERE id = ?", [MySQLData(string: status.rawValue), MySQLData(string: id.uuidString)])
        }.get()
    }
    
    func deleteTask(id: UUID) async throws {
        guard let pool = pool else {
            throw StorageError.poolNotInitialized
        }
        _ = try await pool.withConnection { conn in
            conn.query("DELETE FROM meeting_tasks WHERE id = ?", [MySQLData(string: id.uuidString)])
        }.get()
    }
    
    func updateTaskTitle(id: UUID, newTitle: String) async throws {
        guard let pool = pool else {
            throw StorageError.poolNotInitialized
        }
        _ = try await pool.withConnection { conn in
            conn.query("UPDATE meeting_tasks SET title = ? WHERE id = ?", [MySQLData(string: newTitle), MySQLData(string: id.uuidString)])
        }.get()
    }
    
    func getTask(id: UUID) async throws -> MeetingTask? {
        guard let pool = pool else {
            throw StorageError.poolNotInitialized
        }
        return try await pool.withConnection { conn in
            conn.query("SELECT * FROM meeting_tasks WHERE id = ?", [MySQLData(string: id.uuidString)]).flatMapThrowing { rows in
                rows.first.flatMap { self.mapRowToTask($0) }
            }
        }.get()
    }
    
    private func mapRowToTask(_ row: MySQLRow) -> MeetingTask? {
        guard let idString = row.column("id")?.string,
              let uuid = UUID(uuidString: idString),
              let createdAt = row.column("created_at")?.date,
              let recordingId = row.column("recording_id")?.string,
              let localFilePath = row.column("local_file_path")?.string,
              let title = row.column("title")?.string,
              let statusRaw = row.column("status")?.string,
              let status = MeetingTaskStatus(rawValue: statusRaw) else {
            return nil
        }
        
        var task = MeetingTask(recordingId: recordingId, localFilePath: localFilePath, title: title)
        task.id = uuid
        task.createdAt = createdAt
        task.status = status
        
        task.ossUrl = row.column("oss_url")?.string
        task.tingwuTaskId = row.column("tingwu_task_id")?.string
        task.rawResponse = row.column("raw_response")?.string
        task.transcript = row.column("transcript")?.string
        task.summary = row.column("summary")?.string
        task.keyPoints = row.column("key_points")?.string
        task.actionItems = row.column("action_items")?.string
        task.lastError = row.column("last_error")?.string
        task.taskKey = row.column("task_key")?.string
        task.apiStatus = row.column("api_status")?.string
        task.statusText = row.column("status_text")?.string
        task.bizDuration = row.column("biz_duration")?.int
        task.outputMp3Path = row.column("output_mp3_path")?.string
        
        if let successStatusRaw = row.column("last_successful_status")?.string,
           let successStatus = MeetingTaskStatus(rawValue: successStatusRaw) {
            task.lastSuccessfulStatus = successStatus
        }
        if let failedStatusRaw = row.column("failed_step")?.string,
           let failedStep = MeetingTaskStatus(rawValue: failedStatusRaw) {
            task.failedStep = failedStep
        }
        task.retryCount = row.column("retry_count")?.int ?? 0
        
        if let modeRaw = row.column("mode")?.string,
           let mode = MeetingMode(rawValue: modeRaw) {
            task.mode = mode
        }
        
        task.speaker1AudioPath = row.column("speaker1_audio_path")?.string
        task.speaker2AudioPath = row.column("speaker2_audio_path")?.string
        task.speaker2OssUrl = row.column("speaker2_oss_url")?.string
        task.speaker2TingwuTaskId = row.column("speaker2_tingwu_task_id")?.string
        task.speaker1Transcript = row.column("speaker1_transcript")?.string
        task.speaker2Transcript = row.column("speaker2_transcript")?.string
        task.alignedConversation = row.column("aligned_conversation")?.string
        
        if let s1StatusRaw = row.column("speaker1_status")?.string,
           let s1Status = MeetingTaskStatus(rawValue: s1StatusRaw) {
            task.speaker1Status = s1Status
        }
        if let s2StatusRaw = row.column("speaker2_status")?.string,
           let s2Status = MeetingTaskStatus(rawValue: s2StatusRaw) {
            task.speaker2Status = s2Status
        }
        
        if let s1FailedRaw = row.column("speaker1_failed_step")?.string,
           let s1Failed = MeetingTaskStatus(rawValue: s1FailedRaw) {
            task.speaker1FailedStep = s1Failed
        }
        if let s2FailedRaw = row.column("speaker2_failed_step")?.string,
           let s2Failed = MeetingTaskStatus(rawValue: s2FailedRaw) {
            task.speaker2FailedStep = s2Failed
        }
        
        task.originalOssUrl = row.column("original_oss_url")?.string
        task.speaker2OriginalOssUrl = row.column("speaker2_original_oss_url")?.string
        
        return task
    }
}
