import Foundation
import SQLite

class DatabaseManager {
    static let shared = DatabaseManager()
    
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
    
    private init() {
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
            
            let appDir = baseDir.appendingPathComponent("WeChatVoiceRecorder")
            
            do {
                try fileManager.createDirectory(at: appDir, withIntermediateDirectories: true)
            } catch {
                print("Failed to create database directory: \(error)")
                // Try using a temporary directory as last resort
                let tempDir = fileManager.temporaryDirectory.appendingPathComponent("WeChatVoiceRecorder")
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
            })
            
            // Migration for existing tables
            _ = try? db.run(tasks.addColumn(taskKey))
            _ = try? db.run(tasks.addColumn(apiStatus))
            _ = try? db.run(tasks.addColumn(statusText))
            _ = try? db.run(tasks.addColumn(bizDuration))
            _ = try? db.run(tasks.addColumn(outputMp3Path))
        } catch {
            print("Create table error: \(error)")
        }
    }
    
    // CRUD Operations
    
    func saveTask(_ task: MeetingTask) {
        guard let db = db else { return }
        
        do {
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
                outputMp3Path <- task.outputMp3Path
            )
            try db.run(insert)
        } catch {
            print("Save task error: \(error)")
        }
    }
    
    func fetchTasks() -> [MeetingTask] {
        guard let db = db else { return [] }
        
        var results: [MeetingTask] = []
        
        do {
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
                
                results.append(task)
            }
        } catch {
            print("Fetch tasks error: \(error)")
        }
        
        return results
    }
    
    func deleteTask(id: UUID) {
        guard let db = db else { return }
        let task = tasks.filter(self.id == id.uuidString)
        _ = try? db.run(task.delete())
    }
}
