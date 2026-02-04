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
    
    var logger: ((String) -> Void)?
    
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
    
    private func log(_ message: String) {
        print(message)
        logger?(message)
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
        
        log("MySQLStorage createTableIfNeeded: Creating table if needed")
        
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
            transcript LONGTEXT,
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
            original_oss_url TEXT,
            overview_data LONGTEXT,
            transcript_data LONGTEXT,
            conversation_data LONGTEXT,
            raw_data LONGTEXT
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
        
        log("MySQLStorage createTableIfNeeded: Existing columns: \(existingColumns)")
        
        if !existingColumns.contains("original_oss_url") {
            _ = try await pool.withConnection { conn in
                conn.query("ALTER TABLE meeting_tasks ADD COLUMN original_oss_url TEXT")
            }.get()
        }
        
        // Migration for Complete Poll Results
        if !existingColumns.contains("overview_data") {
            log("MySQLStorage createTableIfNeeded: Adding overview_data column")
            _ = try await pool.withConnection { conn in
                conn.query("ALTER TABLE meeting_tasks ADD COLUMN overview_data TEXT")
            }.get()
        }
        
        if !existingColumns.contains("transcript_data") {
            log("MySQLStorage createTableIfNeeded: Adding transcript_data column")
            _ = try await pool.withConnection { conn in
                conn.query("ALTER TABLE meeting_tasks ADD COLUMN transcript_data TEXT")
            }.get()
        }
        
        if !existingColumns.contains("conversation_data") {
            log("MySQLStorage createTableIfNeeded: Adding conversation_data column")
            _ = try await pool.withConnection { conn in
                conn.query("ALTER TABLE meeting_tasks ADD COLUMN conversation_data TEXT")
            }.get()
        }
        
        if !existingColumns.contains("raw_data") {
            log("MySQLStorage createTableIfNeeded: Adding raw_data column")
            _ = try await pool.withConnection { conn in
                conn.query("ALTER TABLE meeting_tasks ADD COLUMN raw_data TEXT")
            }.get()
        }
        
        log("MySQLStorage createTableIfNeeded: Table creation/migration completed")
        
        // Upgrade existing text columns to LONGTEXT to support large data
        _ = try? await pool.withConnection { conn in
            conn.query("ALTER TABLE meeting_tasks MODIFY COLUMN transcript LONGTEXT")
        }.get()
        
        _ = try? await pool.withConnection { conn in
            conn.query("ALTER TABLE meeting_tasks MODIFY COLUMN overview_data LONGTEXT")
        }.get()
        
        _ = try? await pool.withConnection { conn in
            conn.query("ALTER TABLE meeting_tasks MODIFY COLUMN transcript_data LONGTEXT")
        }.get()
        
        _ = try? await pool.withConnection { conn in
            conn.query("ALTER TABLE meeting_tasks MODIFY COLUMN conversation_data LONGTEXT")
        }.get()
        
        _ = try? await pool.withConnection { conn in
            conn.query("ALTER TABLE meeting_tasks MODIFY COLUMN raw_data LONGTEXT")
        }.get()
        
        log("MySQLStorage createTableIfNeeded: Column upgrade completed")
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
        
        log("MySQLStorage saveTask: Saving task \(task.id)")
        log("MySQLStorage saveTask: overviewData = \(task.overviewData?.prefix(100) ?? "nil")")
        log("MySQLStorage saveTask: transcriptData = \(task.transcriptData?.prefix(100) ?? "nil")")
        log("MySQLStorage saveTask: conversationData = \(task.conversationData?.prefix(100) ?? "nil")")
        log("MySQLStorage saveTask: rawData = \(task.rawData?.prefix(100) ?? "nil")")
        
        let sql = """
        INSERT INTO meeting_tasks (
            id, created_at, recording_id, local_file_path, oss_url, tingwu_task_id,
            status, title, raw_response, transcript, summary, key_points,
            action_items, last_error, task_key, api_status, status_text,
            biz_duration, output_mp3_path, last_successful_status, failed_step,
            retry_count, original_oss_url,
            overview_data, transcript_data, conversation_data, raw_data
        ) VALUES (
            ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
        ) ON DUPLICATE KEY UPDATE
            recording_id=VALUES(recording_id), local_file_path=VALUES(local_file_path),
            oss_url=VALUES(oss_url), tingwu_task_id=VALUES(tingwu_task_id),
            status=VALUES(status), title=VALUES(title), raw_response=VALUES(raw_response),
            transcript=VALUES(transcript), summary=VALUES(summary), key_points=VALUES(key_points),
            action_items=VALUES(action_items), last_error=VALUES(last_error),
            task_key=VALUES(task_key), api_status=VALUES(api_status), status_text=VALUES(status_text),
            biz_duration=VALUES(biz_duration), output_mp3_path=VALUES(output_mp3_path),
            last_successful_status=VALUES(last_successful_status), failed_step=VALUES(failed_step),
            retry_count=VALUES(retry_count),
            original_oss_url=VALUES(original_oss_url),
            overview_data=VALUES(overview_data), transcript_data=VALUES(transcript_data),
            conversation_data=VALUES(conversation_data), raw_data=VALUES(raw_data);
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
                task.originalOssUrl.map { MySQLData(string: $0) } ?? .null,
                task.overviewData.map { MySQLData(string: $0) } ?? .null,
                task.transcriptData.map { MySQLData(string: $0) } ?? .null,
                task.conversationData.map { MySQLData(string: $0) } ?? .null,
                task.rawData.map { MySQLData(string: $0) } ?? .null
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
              let status = MeetingTaskStatus.from(rawValue: statusRaw) else {
            return nil
        }
        
        let task = MeetingTask(recordingId: recordingId, localFilePath: localFilePath, title: title)
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
           let successStatus = MeetingTaskStatus.from(rawValue: successStatusRaw) {
            task.lastSuccessfulStatus = successStatus
        }
        if let failedStatusRaw = row.column("failed_step")?.string,
           let failedStep = MeetingTaskStatus.from(rawValue: failedStatusRaw) {
            task.failedStep = failedStep
        }
        task.retryCount = row.column("retry_count")?.int ?? 0
        
        task.originalOssUrl = row.column("original_oss_url")?.string
        task.overviewData = row.column("overview_data")?.string
        task.transcriptData = row.column("transcript_data")?.string
        task.conversationData = row.column("conversation_data")?.string
        task.rawData = row.column("raw_data")?.string
        
        return task
    }
}
