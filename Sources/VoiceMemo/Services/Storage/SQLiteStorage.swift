import Foundation
import SQLite

class SQLiteStorage: StorageProvider {
    private var db: Connection?
    
    // Table Definition
    private let tasks = Table("meeting_tasks")
    private let id = Expression<String>("id")
    private let createdAt = Expression<Date>("created_at")
    private let recordingId = Expression<String>("recording_id")
    private let localFilePath = Expression<String>("local_file_path")
    private let ossUrl = Expression<String?>("oss_url")
    private let tingwuTaskId = Expression<String?>("tingwu_task_id")
    private let status = Expression<String>("status")
    private let title = Expression<String>("title")
    private let rawResponse = Expression<String?>("raw_response")
    private let transcript = Expression<String?>("transcript")
    private let summary = Expression<String?>("summary")
    private let keyPoints = Expression<String?>("key_points")
    private let actionItems = Expression<String?>("action_items")
    private let lastError = Expression<String?>("last_error")
    
    // New Fields
    private let taskKey = Expression<String?>("task_key")
    private let apiStatus = Expression<String?>("api_status")
    private let statusText = Expression<String?>("status_text")
    private let bizDuration = Expression<Int?>("biz_duration")
    private let outputMp3Path = Expression<String?>("output_mp3_path")
    
    // New Fields for Retry
    private let lastSuccessfulStatus = Expression<String?>("last_successful_status")
    private let failedStep = Expression<String?>("failed_step")
    private let retryCount = Expression<Int>("retry_count")
    
    // New Fields for Separated Mode (Removed)
    
    private let originalOssUrl = Expression<String?>("original_oss_url")
    
    // New Fields for Complete Poll Results
    private let overviewData = Expression<String?>("overview_data")
    private let transcriptData = Expression<String?>("transcript_data") 
    private let conversationData = Expression<String?>("conversation_data")
    private let rawData = Expression<String?>("raw_data")
    
    init() {
        setupDatabase()
    }
    
    private func setupDatabase() {
        do {
            let fileManager = FileManager.default
            
            // Fallback to Documents if ApplicationSupport fails or is not accessible
            let baseDir: URL
            if let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                baseDir = appSupport
            } else {
                baseDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
            }
            
            let appDir = baseDir.appendingPathComponent("VoiceMemo")
            
            do {
                try fileManager.createDirectory(at: appDir, withIntermediateDirectories: true)
            } catch {
                print("Failed to create database directory: \(error)")
                // Try using a temporary directory as last resort
                let tempDir = fileManager.temporaryDirectory.appendingPathComponent("VoiceMemo")
                try? fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
                let dbPath = tempDir.appendingPathComponent("db.sqlite3").path
                print("Fallback to temp database: \(dbPath)")
                db = try Connection(dbPath)
                createTables()
                return
            }
            
            let dbPath = appDir.appendingPathComponent("db.sqlite3").path
            print("Database path: \(dbPath)")
            db = try Connection(dbPath)
            
            createTables()
        } catch {
            print("Database setup error: \(error)")
        }
    }
    
    private func createTables() {
        guard let db = db else { return }
        
        do {
            try db.run(tasks.create(ifNotExists: true) { t in
                t.column(id, primaryKey: true)
                t.column(createdAt)
                t.column(recordingId)
                t.column(localFilePath)
                t.column(ossUrl)
                t.column(tingwuTaskId)
                t.column(status)
                t.column(title)
                t.column(rawResponse)
                t.column(transcript)
                t.column(summary)
                t.column(keyPoints)
                t.column(actionItems)
                t.column(lastError)
                t.column(taskKey)
                t.column(apiStatus)
                t.column(statusText)
                t.column(bizDuration)
                t.column(outputMp3Path)
                t.column(lastSuccessfulStatus)
                t.column(failedStep)
                t.column(retryCount, defaultValue: 0)
                
                // Separated Mode (Removed)
                t.column(originalOssUrl)
                t.column(overviewData)
                t.column(transcriptData)
                t.column(conversationData)
                t.column(rawData)
            })
            
            // Migration for existing tables - only add if they don't exist
            let existingColumns = getColumnNames()
            
            if !existingColumns.contains("task_key") { _ = try? db.run(tasks.addColumn(taskKey)) }
            if !existingColumns.contains("api_status") { _ = try? db.run(tasks.addColumn(apiStatus)) }
            if !existingColumns.contains("status_text") { _ = try? db.run(tasks.addColumn(statusText)) }
            if !existingColumns.contains("biz_duration") { _ = try? db.run(tasks.addColumn(bizDuration)) }
            if !existingColumns.contains("output_mp3_path") { _ = try? db.run(tasks.addColumn(outputMp3Path)) }
            if !existingColumns.contains("last_successful_status") { _ = try? db.run(tasks.addColumn(lastSuccessfulStatus)) }
            if !existingColumns.contains("failed_step") { _ = try? db.run(tasks.addColumn(failedStep)) }
            if !existingColumns.contains("retry_count") { _ = try? db.run(tasks.addColumn(retryCount, defaultValue: 0)) }
            
            // Migration for Separated Mode (Removed)
            if !existingColumns.contains("original_oss_url") { _ = try? db.run(tasks.addColumn(originalOssUrl)) }
            
            // Migration for Complete Poll Results
            if !existingColumns.contains("overview_data") { _ = try? db.run(tasks.addColumn(overviewData)) }
            if !existingColumns.contains("transcript_data") { _ = try? db.run(tasks.addColumn(transcriptData)) }
            if !existingColumns.contains("conversation_data") { _ = try? db.run(tasks.addColumn(conversationData)) }
            if !existingColumns.contains("raw_data") { _ = try? db.run(tasks.addColumn(rawData)) }
        } catch {
            print("Create table error: \(error)")
        }
    }
    
    private func getColumnNames() -> Set<String> {
        guard let db = db else { return [] }
        var names = Set<String>()
        do {
            for row in try db.prepare("PRAGMA table_info(meeting_tasks)") {
                if let name = row[1] as? String {
                    names.insert(name)
                }
            }
        } catch {
            print("Get column names error: \(error)")
        }
        return names
    }
    
    // MARK: - StorageProvider
    
    func saveTask(_ task: MeetingTask) async throws {
        guard let db = db else { return }
        
        let insert = tasks.insert(or: .replace,
            id <- task.id.uuidString,
            createdAt <- task.createdAt,
            recordingId <- task.recordingId,
            localFilePath <- task.localFilePath,
            ossUrl <- task.ossUrl,
            tingwuTaskId <- task.tingwuTaskId,
            status <- task.status.rawValue,
            title <- task.title,
            rawResponse <- task.rawResponse,
            transcript <- task.transcript,
            summary <- task.summary,
            keyPoints <- task.keyPoints,
            actionItems <- task.actionItems,
            lastError <- task.lastError,
            taskKey <- task.taskKey,
            apiStatus <- task.apiStatus,
            statusText <- task.statusText,
            bizDuration <- task.bizDuration,
            outputMp3Path <- task.outputMp3Path,
            lastSuccessfulStatus <- task.lastSuccessfulStatus?.rawValue,
            failedStep <- task.failedStep?.rawValue,
            retryCount <- task.retryCount,
            originalOssUrl <- task.originalOssUrl,
            overviewData <- task.overviewData,
            transcriptData <- task.transcriptData,
            conversationData <- task.conversationData,
            rawData <- task.rawData
        )
        try db.run(insert)
    }
    
    func fetchTasks() async throws -> [MeetingTask] {
        guard let db = db else { return [] }
        
        var results: [MeetingTask] = []
        
        for row in try db.prepare(tasks.order(createdAt.desc)) {
            let task = MeetingTask(
                recordingId: row[recordingId],
                localFilePath: row[localFilePath],
                title: row[title]
            )
            
            if let uuid = UUID(uuidString: row[id]) {
                task.id = uuid
            }
            task.createdAt = row[createdAt]
            task.ossUrl = row[ossUrl]
            task.tingwuTaskId = row[tingwuTaskId]
            if let statusEnum = MeetingTaskStatus.from(rawValue: row[status]) {
                task.status = statusEnum
            }
            task.rawResponse = row[rawResponse]
            task.transcript = row[transcript]
            task.summary = row[summary]
            task.keyPoints = row[keyPoints]
            task.actionItems = row[actionItems]
            task.lastError = row[lastError]
            task.taskKey = row[taskKey]
            task.apiStatus = row[apiStatus]
            task.statusText = row[statusText]
            task.bizDuration = row[bizDuration]
            task.outputMp3Path = row[outputMp3Path]
            
            if let successStatusRaw = row[lastSuccessfulStatus], let successStatus = MeetingTaskStatus.from(rawValue: successStatusRaw) {
                task.lastSuccessfulStatus = successStatus
            }
            if let failedStatusRaw = row[failedStep], let failedStepEnum = MeetingTaskStatus.from(rawValue: failedStatusRaw) {
                task.failedStep = failedStepEnum
            }
            task.retryCount = row[retryCount]
            
            task.originalOssUrl = row[originalOssUrl]
            task.overviewData = row[overviewData]
            task.transcriptData = row[transcriptData]
            task.conversationData = row[conversationData]
            task.rawData = row[rawData]
            
            results.append(task)
        }
        
        return results
    }
    
    func deleteTask(id: UUID) async throws {
        guard let db = db else { return }
        let task = tasks.filter(self.id == id.uuidString)
        _ = try db.run(task.delete())
    }
    
    func updateTaskTitle(id: UUID, newTitle: String) async throws {
        guard let db = db else { return }
        let task = tasks.filter(self.id == id.uuidString)
        _ = try db.run(task.update(title <- newTitle))
    }
    
    func getTask(id: UUID) async throws -> MeetingTask? {
        guard let db = db else { return nil }
        let query = tasks.filter(self.id == id.uuidString)
        
        guard let row = try db.pluck(query) else { return nil }
        
        let task = MeetingTask(
            recordingId: row[recordingId],
            localFilePath: row[localFilePath],
            title: row[title]
        )
        
        if let uuid = UUID(uuidString: row[self.id]) {
            task.id = uuid
        }
        task.createdAt = row[createdAt]
        task.ossUrl = row[ossUrl]
        task.tingwuTaskId = row[tingwuTaskId]
        if let statusEnum = MeetingTaskStatus.from(rawValue: row[status]) {
            task.status = statusEnum
        }
        // ... (rest of mapping) ...
        // To avoid code duplication, I should refactor the mapping logic, but for now I'll just copy it.
        task.rawResponse = row[rawResponse]
        task.transcript = row[transcript]
        task.summary = row[summary]
        task.keyPoints = row[keyPoints]
        task.actionItems = row[actionItems]
        task.lastError = row[lastError]
        task.taskKey = row[taskKey]
        task.apiStatus = row[apiStatus]
        task.statusText = row[statusText]
        task.bizDuration = row[bizDuration]
        task.outputMp3Path = row[outputMp3Path]
        
        if let successStatusRaw = row[lastSuccessfulStatus], let successStatus = MeetingTaskStatus.from(rawValue: successStatusRaw) {
            task.lastSuccessfulStatus = successStatus
        }
        if let failedStatusRaw = row[failedStep], let failedStepEnum = MeetingTaskStatus.from(rawValue: failedStatusRaw) {
            task.failedStep = failedStepEnum
        }
        task.retryCount = row[retryCount]
        
        task.originalOssUrl = row[originalOssUrl]
        task.overviewData = row[overviewData]
        task.transcriptData = row[transcriptData]
        task.conversationData = row[conversationData]
        task.rawData = row[rawData]
        
        return task
    }
}
