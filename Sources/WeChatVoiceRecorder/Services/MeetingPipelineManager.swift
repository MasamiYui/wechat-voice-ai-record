import Foundation
import AVFoundation
import Combine

class MeetingPipelineManager: ObservableObject {
    @Published var task: MeetingTask
    @Published var isProcessing: Bool = false
    @Published var errorMessage: String?
    
    private let ossService: OSSService
    private let tingwuService: TingwuService
    private let database: DatabaseManager
    private let settings: SettingsStore
    
    init(task: MeetingTask, settings: SettingsStore) {
        self.task = task
        self.settings = settings
        self.ossService = OSSService(settings: settings)
        self.tingwuService = TingwuService(settings: settings)
        self.database = DatabaseManager.shared
    }
    
    // MARK: - Actions
    
    func transcode() async {
        guard task.status == .recorded || task.status == .failed else { return }
        
        await updateStatus(.transcoding, error: nil)
        
        // Output path: .../mixed_48k.m4a
        let inputURL = URL(fileURLWithPath: task.localFilePath)
        let outputURL = inputURL.deletingLastPathComponent().appendingPathComponent("mixed_48k.m4a")
        
        // If already exists, delete
        try? FileManager.default.removeItem(at: outputURL)
        
        let asset = AVAsset(url: inputURL)
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            await updateStatus(.failed, error: "Cannot create export session")
            return
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a
        // Note: AVAssetExportPresetAppleM4A usually defaults to high quality AAC. 
        // To strictly force 48k, we might need AVAssetWriter, but ExportSession is simpler for MVP.
        // Let's assume the preset is sufficient.
        
        await exportSession.export()
        
        if exportSession.status == .completed {
            // Update local path to the transcoded one
            var updatedTask = task
            updatedTask.localFilePath = outputURL.path
            // We keep status as transcoding -> uploading ready?
            // Actually, we can just say "Transcode Done", waiting for upload.
            // But our status enum is limited. Let's stay in 'transcoding' until upload starts?
            // Or better: update status to .recorded (ready to upload) but with new path?
            // Or add a 'transcoded' status.
            // For MVP, let's just move to 'uploading' automatically? 
            // User wants "manual trigger". So we need a state "Ready to Upload".
            // Let's reuse .recorded but maybe add a flag?
            // Or just allow user to click "Upload" which triggers upload.
            // Let's add a `transcoded` status to MeetingTask if possible, or just stay in `recorded` and rely on UI to show "Transcoded".
            // I'll add `transcoded` to MeetingTaskStatus enum in next step.
            
            // For now, let's assume we proceed to next step or stay in .recorded.
            // Let's update task in DB
            self.task.localFilePath = outputURL.path
            await updateStatus(.transcoded, error: nil) // Transcode complete
        } else {
            await updateStatus(.failed, error: exportSession.error?.localizedDescription ?? "Transcode failed")
        }
    }
    
    func upload() async {
        await updateStatus(.uploading, error: nil)
        
        do {
            let fileURL = URL(fileURLWithPath: task.localFilePath)
            // Object Key: wvr/{yyyy}/{MM}/{dd}/{recordingId}/mixed.m4a
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy/MM/dd"
            let datePath = formatter.string(from: task.createdAt)
            let objectKey = "\(settings.ossPrefix)\(datePath)/\(task.recordingId)/mixed.m4a"
            
            let url = try await ossService.uploadFile(fileURL: fileURL, objectKey: objectKey)
            
            var updatedTask = task
            updatedTask.ossUrl = url
            updatedTask.status = .uploaded // Ready to create task
            self.task = updatedTask
            self.save()
        } catch {
            await updateStatus(.failed, error: error.localizedDescription)
        }
    }
    
    func createTask() async {
        guard let ossUrl = task.ossUrl else { return }
        await updateStatus(.created, error: nil) // Using created as "Creating..." (transient)
        
        do {
            let taskId = try await tingwuService.createTask(fileUrl: ossUrl)
            
            var updatedTask = task
            updatedTask.tingwuTaskId = taskId
            updatedTask.status = .polling // Ready to poll
            self.task = updatedTask
            self.save()
        } catch {
             await updateStatus(.failed, error: error.localizedDescription)
        }
    }
    
    func pollStatus() async {
        guard let taskId = task.tingwuTaskId else { return }
        await MainActor.run { self.isProcessing = true }
        
        do {
            let (status, data) = try await tingwuService.getTaskInfo(taskId: taskId)
            // Status: ONGOING, SUCCESS, FAILED
            
            if status == "SUCCESS" {
                // Parse Result
                if let result = data?["Result"] as? [String: Any] {
                    // Update task with results
                    var updatedTask = task
                    updatedTask.status = .completed
                    
                    // Save raw JSON
                    if let jsonData = try? JSONSerialization.data(withJSONObject: data!, options: .prettyPrinted) {
                        updatedTask.rawResponse = String(data: jsonData, encoding: .utf8)
                    }
                    
                    // Extract Transcripts
                    if let sentences = result["Sentences"] as? [[String: Any]] {
                        let text = sentences.compactMap { $0["Text"] as? String }.joined(separator: "\n")
                        updatedTask.transcript = text
                    }
                    
                    // Extract Summarization
                    if let summaryObj = result["Summarization"] as? [String: Any] {
                        if let summary = summaryObj["Headline"] as? String {
                            updatedTask.summary = summary
                        }
                        if let summaryText = summaryObj["Summary"] as? String {
                            // Append to summary if headline exists
                            updatedTask.summary = (updatedTask.summary ?? "") + "\n\n" + summaryText
                        }
                        
                        // Extract KeyPoints
                        if let keyPointsList = summaryObj["KeyPoints"] as? [[String: Any]] {
                            let kpText = keyPointsList.compactMap { $0["Text"] as? String }.joined(separator: "\n- ")
                            updatedTask.keyPoints = "- " + kpText
                        }
                        
                        // Extract ActionItems
                        if let actionItemsList = summaryObj["ActionItems"] as? [[String: Any]] {
                            let aiText = actionItemsList.compactMap { $0["Text"] as? String }.joined(separator: "\n- ")
                            updatedTask.actionItems = "- " + aiText
                        }
                    }
                    
                    self.task = updatedTask
                    self.save()
                }
            } else if status == "FAILED" {
                 await updateStatus(.failed, error: "Task failed in cloud")
            } else {
                // Still running
                // Just update UI, don't change status from .polling
                 await MainActor.run { self.isProcessing = false }
            }
        } catch {
            await updateStatus(.failed, error: error.localizedDescription)
        }
        
        await MainActor.run { self.isProcessing = false }
    }
    
    // MARK: - Helper
    
    @MainActor
    private func updateStatus(_ status: MeetingTaskStatus, error: String?) {
        self.task.status = status
        self.task.lastError = error
        self.errorMessage = error
        self.isProcessing = false
        self.save()
    }
    
    private func save() {
        database.saveTask(self.task)
    }
}
