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
    
    // New Fields for Separated Mode
    private let mode = Expression<String>("mode")
    private let speaker1AudioPath = Expression<String?>("speaker1_audio_path")
    private let speaker2AudioPath = Expression<String?>("speaker2_audio_path")
    private let speaker2OssUrl = Expression<String?>("speaker2_oss_url")
    private let speaker2TingwuTaskId = Expression<String?>("speaker2_tingwu_task_id")
    private let speaker1Transcript = Expression<String?>("speaker1_transcript")
    private let speaker2Transcript = Expression<String?>("speaker2_transcript")
    private let alignedConversation = Expression<String?>("aligned_conversation")
    private let speaker1Status = Expression<String?>("speaker1_status")
    private let speaker2Status = Expression<String?>("speaker2_status")
    private let speaker1FailedStep = Expression<String?>("speaker1_failed_step")
    private let speaker2FailedStep = Expression<String?>("speaker2_failed_step")
    private let originalOssUrl = Expression<String?>("original_oss_url")
    private let speaker2OriginalOssUrl = Expression<String?>("speaker2_original_oss_url")
    
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
                
                // Separated Mode
                t.column(mode, defaultValue: "mixed")
                t.column(speaker1AudioPath)
                t.column(speaker2AudioPath)
                t.column(speaker2OssUrl)
                t.column(speaker2TingwuTaskId)
                t.column(speaker1Transcript)
                t.column(speaker2Transcript)
                t.column(alignedConversation)
                t.column(speaker1Status)
                t.column(speaker2Status)
                t.column(speaker1FailedStep)
                t.column(speaker2FailedStep)
                t.column(originalOssUrl)
                t.column(speaker2OriginalOssUrl)
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
            
            // Migration for Separated Mode
            if !existingColumns.contains("mode") { _ = try? db.run(tasks.addColumn(mode, defaultValue: "mixed")) }
            if !existingColumns.contains("speaker1_audio_path") { _ = try? db.run(tasks.addColumn(speaker1AudioPath)) }
            if !existingColumns.contains("speaker2_audio_path") { _ = try? db.run(tasks.addColumn(speaker2AudioPath)) }
            if !existingColumns.contains("speaker2_oss_url") { _ = try? db.run(tasks.addColumn(speaker2OssUrl)) }
            if !existingColumns.contains("speaker2_tingwu_task_id") { _ = try? db.run(tasks.addColumn(speaker2TingwuTaskId)) }
            if !existingColumns.contains("speaker1_transcript") { _ = try? db.run(tasks.addColumn(speaker1Transcript)) }
            if !existingColumns.contains("speaker2_transcript") { _ = try? db.run(tasks.addColumn(speaker2Transcript)) }
            if !existingColumns.contains("aligned_conversation") { _ = try? db.run(tasks.addColumn(alignedConversation)) }
            if !existingColumns.contains("speaker1_status") { _ = try? db.run(tasks.addColumn(speaker1Status)) }
            if !existingColumns.contains("speaker2_status") { _ = try? db.run(tasks.addColumn(speaker2Status)) }
            if !existingColumns.contains("speaker1_failed_step") { _ = try? db.run(tasks.addColumn(speaker1FailedStep)) }
            if !existingColumns.contains("speaker2_failed_step") { _ = try? db.run(tasks.addColumn(speaker2FailedStep)) }
            if !existingColumns.contains("original_oss_url") { _ = try? db.run(tasks.addColumn(originalOssUrl)) }
            if !existingColumns.contains("speaker2_original_oss_url") { _ = try? db.run(tasks.addColumn(speaker2OriginalOssUrl)) }
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
            mode <- task.mode.rawValue,
            speaker1AudioPath <- task.speaker1AudioPath,
            speaker2AudioPath <- task.speaker2AudioPath,
            speaker2OssUrl <- task.speaker2OssUrl,
            speaker2TingwuTaskId <- task.speaker2TingwuTaskId,
            speaker1Transcript <- task.speaker1Transcript,
            speaker2Transcript <- task.speaker2Transcript,
            alignedConversation <- task.alignedConversation,
            speaker1Status <- task.speaker1Status?.rawValue,
            speaker2Status <- task.speaker2Status?.rawValue,
            speaker1FailedStep <- task.speaker1FailedStep?.rawValue,
            speaker2FailedStep <- task.speaker2FailedStep?.rawValue,
            originalOssUrl <- task.originalOssUrl,
            speaker2OriginalOssUrl <- task.speaker2OriginalOssUrl
        )
        try db.run(insert)
    }
    
    func fetchTasks() async throws -> [MeetingTask] {
        guard let db = db else { return [] }
        
        var results: [MeetingTask] = []
        
        for row in try db.prepare(tasks.order(createdAt.desc)) {
            var task = MeetingTask(
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
            if let statusEnum = MeetingTaskStatus(rawValue: row[status]) {
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
            
            if let successStatusRaw = row[lastSuccessfulStatus], let successStatus = MeetingTaskStatus(rawValue: successStatusRaw) {
                task.lastSuccessfulStatus = successStatus
            }
            if let failedStatusRaw = row[failedStep], let failedStepEnum = MeetingTaskStatus(rawValue: failedStatusRaw) {
                task.failedStep = failedStepEnum
            }
            task.retryCount = row[retryCount]
            
            if let modeRaw = try? row.get(mode), let modeEnum = MeetingMode(rawValue: modeRaw) {
                task.mode = modeEnum
            }
            task.speaker1AudioPath = row[speaker1AudioPath]
            task.speaker2AudioPath = row[speaker2AudioPath]
            task.speaker2OssUrl = row[speaker2OssUrl]
            task.speaker2TingwuTaskId = row[speaker2TingwuTaskId]
            task.speaker1Transcript = row[speaker1Transcript]
            task.speaker2Transcript = row[speaker2Transcript]
            task.alignedConversation = row[alignedConversation]
            task.originalOssUrl = row[originalOssUrl]
            task.speaker2OriginalOssUrl = row[speaker2OriginalOssUrl]
            
            if let s1StatusRaw = row[speaker1Status], let s1StatusEnum = MeetingTaskStatus(rawValue: s1StatusRaw) {
                task.speaker1Status = s1StatusEnum
            }
            if let s2StatusRaw = row[speaker2Status], let s2StatusEnum = MeetingTaskStatus(rawValue: s2StatusRaw) {
                task.speaker2Status = s2StatusEnum
            }
            if let s1FailedRaw = row[speaker1FailedStep], let s1FailedEnum = MeetingTaskStatus(rawValue: s1FailedRaw) {
                task.speaker1FailedStep = s1FailedEnum
            }
            if let s2FailedRaw = row[speaker2FailedStep], let s2FailedEnum = MeetingTaskStatus(rawValue: s2FailedRaw) {
                task.speaker2FailedStep = s2FailedEnum
            }
            
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
        
        var task = MeetingTask(
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
        if let statusEnum = MeetingTaskStatus(rawValue: row[status]) {
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
        
        if let successStatusRaw = row[lastSuccessfulStatus], let successStatus = MeetingTaskStatus(rawValue: successStatusRaw) {
            task.lastSuccessfulStatus = successStatus
        }
        if let failedStatusRaw = row[failedStep], let failedStepEnum = MeetingTaskStatus(rawValue: failedStatusRaw) {
            task.failedStep = failedStepEnum
        }
        task.retryCount = row[retryCount]
        
        if let modeRaw = try? row.get(mode), let modeEnum = MeetingMode(rawValue: modeRaw) {
            task.mode = modeEnum
        }
        task.speaker1AudioPath = row[speaker1AudioPath]
        task.speaker2AudioPath = row[speaker2AudioPath]
        task.speaker2OssUrl = row[speaker2OssUrl]
        task.speaker2TingwuTaskId = row[speaker2TingwuTaskId]
        task.speaker1Transcript = row[speaker1Transcript]
        task.speaker2Transcript = row[speaker2Transcript]
        task.alignedConversation = row[alignedConversation]
        task.originalOssUrl = row[originalOssUrl]
        task.speaker2OriginalOssUrl = row[speaker2OriginalOssUrl]
        
        if let s1StatusRaw = row[speaker1Status], let s1StatusEnum = MeetingTaskStatus(rawValue: s1StatusRaw) {
            task.speaker1Status = s1StatusEnum
        }
        if let s2StatusRaw = row[speaker2Status], let s2StatusEnum = MeetingTaskStatus(rawValue: s2StatusRaw) {
            task.speaker2Status = s2StatusEnum
        }
        if let s1FailedRaw = row[speaker1FailedStep], let s1FailedEnum = MeetingTaskStatus(rawValue: s1FailedRaw) {
            task.speaker1FailedStep = s1FailedEnum
        }
        if let s2FailedRaw = row[speaker2FailedStep], let s2FailedEnum = MeetingTaskStatus(rawValue: s2FailedRaw) {
            task.speaker2FailedStep = s2FailedEnum
        }
        
        return task
    }
}
