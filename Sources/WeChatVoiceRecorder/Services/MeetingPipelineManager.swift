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
        
        settings.log("Transcode start: input=\(task.localFilePath)")
        await updateStatus(.transcoding, error: nil)
        
        let inputURL = URL(fileURLWithPath: task.localFilePath)
        let outputURL = inputURL.deletingLastPathComponent().appendingPathComponent("mixed_48k.m4a")
        
        try? FileManager.default.removeItem(at: outputURL)
        
        let asset = AVAsset(url: inputURL)
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            settings.log("Transcode failed: cannot create export session")
            await updateStatus(.failed, error: "Cannot create export session")
            return
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a
        
        await exportSession.export()
        
        if exportSession.status == .completed {
            var updatedTask = task
            updatedTask.localFilePath = outputURL.path
            self.task.localFilePath = outputURL.path
            settings.log("Transcode success: output=\(outputURL.path)")
            await updateStatus(.transcoded, error: nil) // Transcode complete
        } else {
            settings.log("Transcode failed: \(exportSession.error?.localizedDescription ?? "Unknown error")")
            await updateStatus(.failed, error: exportSession.error?.localizedDescription ?? "Transcode failed")
        }
    }
    
    func upload() async {
        settings.log("Upload start: file=\(task.localFilePath)")
        await updateStatus(.uploading, error: nil)
        
        do {
            let fileURL = URL(fileURLWithPath: task.localFilePath)
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
            settings.log("Upload success: url=\(url)")
        } catch {
            settings.log("Upload failed: \(error.localizedDescription)")
            await updateStatus(.failed, error: error.localizedDescription)
        }
    }
    
    func createTask() async {
        guard let ossUrl = task.ossUrl else { return }
        settings.log("Create task start: ossUrl=\(ossUrl)")
        await updateStatus(.created, error: nil) // Using created as "Creating..." (transient)
        
        do {
            let taskId = try await tingwuService.createTask(fileUrl: ossUrl)
            
            var updatedTask = task
            updatedTask.tingwuTaskId = taskId
            updatedTask.status = .polling // Ready to poll
            self.task = updatedTask
            self.save()
            settings.log("Create task success: taskId=\(taskId)")
        } catch {
             settings.log("Create task failed: \(error.localizedDescription)")
             await updateStatus(.failed, error: error.localizedDescription)
        }
    }
    
    func pollStatus() async {
        guard let taskId = task.tingwuTaskId else { return }
        settings.log("Poll status start: taskId=\(taskId)")
        await MainActor.run { self.isProcessing = true }
        
        do {
            let (status, data) = try await tingwuService.getTaskInfo(taskId: taskId)
            settings.log("Poll status: \(status)")
            
            if status == "SUCCESS" || status == "COMPLETED" {
                if let result = data?["Result"] as? [String: Any] {
                    var updatedTask = task
                    updatedTask.status = .completed
                    
                    if let jsonData = try? JSONSerialization.data(withJSONObject: data!, options: .prettyPrinted) {
                        updatedTask.rawResponse = String(data: jsonData, encoding: .utf8)
                    }
                    
                    // 1. Handle Transcription (Transcript)
                    if let transcriptionUrl = result["Transcription"] as? String {
                        if let transcriptionData = try? await tingwuService.fetchJSON(url: transcriptionUrl) {
                            if let paragraphs = transcriptionData["Paragraphs"] as? [[String: Any]] {
                                // Extract text from Paragraphs structure
                                let text = paragraphs.compactMap { p -> String? in
                                    if let words = p["Words"] as? [[String: Any]] {
                                        return words.compactMap { $0["Text"] as? String }.joined()
                                    }
                                    return nil
                                }.joined(separator: "\n")
                                updatedTask.transcript = text
                            } else if let sentences = transcriptionData["Sentences"] as? [[String: Any]] {
                                // Fallback to Sentences structure
                                let text = sentences.compactMap { $0["Text"] as? String }.joined(separator: "\n")
                                updatedTask.transcript = text
                            }
                        }
                    } else if let sentences = result["Sentences"] as? [[String: Any]] {
                        // Fallback to inline Sentences if present
                        let text = sentences.compactMap { $0["Text"] as? String }.joined(separator: "\n")
                        updatedTask.transcript = text
                    }
                    
                    // 2. Handle Summarization
                    if let summarizationUrl = result["Summarization"] as? String {
                        if let summarizationData = try? await tingwuService.fetchJSON(url: summarizationUrl) {
                            if let summarizationObj = summarizationData["Summarization"] as? [String: Any] {
                                // Handle new structure inside "Summarization" key
                                if let summary = summarizationObj["ParagraphTitle"] as? String {
                                    updatedTask.summary = summary
                                }
                                if let summaryText = summarizationObj["ParagraphSummary"] as? String {
                                    updatedTask.summary = (updatedTask.summary ?? "") + "\n\n" + summaryText
                                }
                                
                                // Conversational Summary
                                if let conversationalSummary = summarizationObj["ConversationalSummary"] as? [[String: Any]] {
                                    let convText = conversationalSummary.compactMap { item -> String? in
                                        guard let speaker = item["SpeakerName"] as? String,
                                              let summary = item["Summary"] as? String else { return nil }
                                        return "\(speaker): \(summary)"
                                    }.joined(separator: "\n\n")
                                    if !convText.isEmpty {
                                        updatedTask.summary = (updatedTask.summary ?? "") + "\n\n### 对话总结\n" + convText
                                    }
                                }
                                
                                // Q&A Summary
                                if let qaSummary = summarizationObj["QuestionsAnsweringSummary"] as? [[String: Any]] {
                                    let qaText = qaSummary.compactMap { item -> String? in
                                        guard let q = item["Question"] as? String,
                                              let a = item["Answer"] as? String else { return nil }
                                        return "Q: \(q)\nA: \(a)"
                                    }.joined(separator: "\n\n")
                                    if !qaText.isEmpty {
                                        updatedTask.summary = (updatedTask.summary ?? "") + "\n\n### 问答总结\n" + qaText
                                    }
                                }
                                
                                // MindMap
                                if let mindMapSummary = summarizationObj["MindMapSummary"] as? [[String: Any]] {
                                    // Simple recursive extraction for mind map could be complex, for now just dump title
                                    let mmText = mindMapSummary.compactMap { $0["Title"] as? String }.joined(separator: ", ")
                                    if !mmText.isEmpty {
                                        updatedTask.summary = (updatedTask.summary ?? "") + "\n\n### 思维导图主题\n" + mmText
                                    }
                                }
                            } else {
                                // Fallback to old flat structure if any
                                if let summary = summarizationData["Headline"] as? String {
                                    updatedTask.summary = summary
                                }
                                if let summaryText = summarizationData["Summary"] as? String {
                                    updatedTask.summary = (updatedTask.summary ?? "") + "\n\n" + summaryText
                                }
                            }
                        }
                    } else if let summaryObj = result["Summarization"] as? [String: Any] {
                        // Fallback to inline Summarization if present
                        if let summary = summaryObj["Headline"] as? String {
                            updatedTask.summary = summary
                        }
                        if let summaryText = summaryObj["Summary"] as? String {
                            updatedTask.summary = (updatedTask.summary ?? "") + "\n\n" + summaryText
                        }
                        
                        if let keyPointsList = summaryObj["KeyPoints"] as? [[String: Any]] {
                            let kpText = keyPointsList.compactMap { $0["Text"] as? String }.joined(separator: "\n- ")
                            updatedTask.keyPoints = "- " + kpText
                        }
                        
                        if let actionItemsList = summaryObj["ActionItems"] as? [[String: Any]] {
                            let aiText = actionItemsList.compactMap { $0["Text"] as? String }.joined(separator: "\n- ")
                            updatedTask.actionItems = "- " + aiText
                        }
                    }
                    
                    // 3. Handle MeetingAssistance (KeyPoints/Actions might also be here)
                    if let assistanceUrl = result["MeetingAssistance"] as? String {
                        if let assistanceData = try? await tingwuService.fetchJSON(url: assistanceUrl) {
                            if let assistanceObj = assistanceData["MeetingAssistance"] as? [String: Any] {
                                // Handle Keywords
                                if let keywords = assistanceObj["Keywords"] as? [String] {
                                    let kwText = keywords.joined(separator: ", ")
                                    updatedTask.keyPoints = (updatedTask.keyPoints ?? "") + "### 关键词\n" + kwText + "\n\n"
                                }
                                
                                // Handle KeySentences (as Key Points)
                                if let keySentences = assistanceObj["KeySentences"] as? [[String: Any]] {
                                    let ksText = keySentences.compactMap { $0["Text"] as? String }.joined(separator: "\n- ")
                                    updatedTask.keyPoints = (updatedTask.keyPoints ?? "") + "### 重点语句\n- " + ksText
                                }
                                
                                // Handle ActionItems (if present in new structure, though logs don't show it yet)
                                if let actionItemsList = assistanceObj["ActionItems"] as? [[String: Any]] {
                                    let aiText = actionItemsList.compactMap { $0["Text"] as? String }.joined(separator: "\n- ")
                                    updatedTask.actionItems = "- " + aiText
                                }
                            } else {
                                // Fallback to flat structure
                                if let keyPointsList = assistanceData["KeyPoints"] as? [[String: Any]], updatedTask.keyPoints == nil {
                                    let kpText = keyPointsList.compactMap { $0["Text"] as? String }.joined(separator: "\n- ")
                                    updatedTask.keyPoints = "- " + kpText
                                }
                                
                                if let actionItemsList = assistanceData["ActionItems"] as? [[String: Any]], updatedTask.actionItems == nil {
                                    let aiText = actionItemsList.compactMap { $0["Text"] as? String }.joined(separator: "\n- ")
                                    updatedTask.actionItems = "- " + aiText
                                }
                            }
                        }
                    }
                    
                    self.task = updatedTask
                    self.save()
                    settings.log("Poll success: results saved")
                }
            } else if status == "FAILED" {
                 settings.log("Poll failed: cloud task failed")
                 await updateStatus(.failed, error: "Task failed in cloud")
            } else {
                 await MainActor.run { self.isProcessing = false }
            }
        } catch {
            settings.log("Poll failed: \(error.localizedDescription)")
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
        settings.log("Task status updated: \(status.rawValue) error=\(error ?? "")")
        self.save()
    }
    
    private func save() {
        database.saveTask(self.task)
    }
}
