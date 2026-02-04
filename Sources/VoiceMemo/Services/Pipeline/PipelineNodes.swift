import Foundation
import AVFoundation

/// 幂等性检查策略：
/// - 上传节点 (UploadOriginalNode, UploadNode): 检查目标 URL 是否已存在
/// - 转码节点 (TranscodeNode): 检查输出文件是否存在（因为转码是本地操作）
/// - 任务创建节点 (CreateTaskNode): 检查任务 ID 是否已存在
/// - 轮询节点 (PollingNode): 无需幂等性检查，每次都会查询最新状态

protocol PipelineNode {
    var step: MeetingTaskStatus { get }
    /// Node 执行逻辑
    /// - Parameters:
    ///   - board: 流水线黑板 (In-Out)，Node 从中读取输入并将产物写回
    ///   - services: 无状态服务提供者
    func run(board: inout PipelineBoard, services: ServiceProvider) async throws
}

/// 辅助扩展：获取目标 Channel
extension PipelineBoard {
    func getChannel(_ id: Int) throws -> ChannelData {
        guard let channel = channels[id] else {
            throw PipelineError.channelNotFound(id)
        }
        return channel
    }
}

// MARK: - 1. 上传原始音频
class UploadOriginalNode: PipelineNode {
    let step: MeetingTaskStatus = .uploadingRaw
    let channelId: Int
    
    init(channelId: Int = 0) { self.channelId = channelId }
    
    func run(board: inout PipelineBoard, services: ServiceProvider) async throws {
        // 1. Read Input
        let channel = try board.getChannel(channelId)
        guard let inputPath = channel.rawAudioPath else {
            throw PipelineError.inputMissing("Raw audio path missing for channel \(channelId)")
        }
        
        // 2. Idempotency Check
        if channel.rawAudioOssURL != nil {
            print("UploadOriginalNode: URL exists, skipping upload.")
            return
        }
        
        // 3. Execution
        let datePath = board.formattedDatePath()
        
        let fileURL = URL(fileURLWithPath: inputPath)
        let filename = channelId == 0 ? "mixed_raw.m4a" : "speaker\(channelId)_raw.m4a"
        let objectKey = "\(board.config.ossPrefix)\(datePath)/\(board.recordingId)/\(filename)"
        
        let url = try await services.ossService.uploadFile(fileURL: fileURL, objectKey: objectKey)
        
        // 4. Write Output
        board.updateChannel(channelId) { $0.rawAudioOssURL = url }
    }
}

// MARK: - 2. 转码音频
class TranscodeNode: PipelineNode {
    let step: MeetingTaskStatus = .transcoding
    let channelId: Int
    
    init(channelId: Int = 0) { self.channelId = channelId }
    
    func run(board: inout PipelineBoard, services: ServiceProvider) async throws {
        // 1. Read Input
        let channel = try board.getChannel(channelId)
        guard let inputPath = channel.rawAudioPath else {
            throw PipelineError.inputMissing("Input file path missing")
        }
        
        // 2. Prepare Output Path
        let inputURL = URL(fileURLWithPath: inputPath)
        let outputFilename = channelId == 0 ? "mixed_48k.m4a" : "speaker\(channelId)_48k.m4a"
        let outputURL = inputURL.deletingLastPathComponent().appendingPathComponent(outputFilename)
        
        // 3. Idempotency Check
        if FileManager.default.fileExists(atPath: outputURL.path) {
            print("TranscodeNode: Processed file exists, skipping transcode.")
            board.updateChannel(channelId) { $0.processedAudioPath = outputURL.path }
            return
        }
        
        // 4. Execution (Always transcode for now to ensure quality)
        if await performTranscode(input: inputURL, output: outputURL) {
            // 5. Write Output
            board.updateChannel(channelId) { $0.processedAudioPath = outputURL.path }
        } else {
            throw PipelineError.transcodeFailed
        }
    }
    
    private func performTranscode(input: URL, output: URL) async -> Bool {
        try? FileManager.default.removeItem(at: output)
        
        // Basic checks
        guard FileManager.default.fileExists(atPath: input.path) else { return false }
        
        let asset = AVAsset(url: input)
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else { return false }
        
        exportSession.outputURL = output
        exportSession.outputFileType = .m4a
        await exportSession.export()
        
        return exportSession.status == .completed
    }
}

// MARK: - 3. 上传转码音频
class UploadNode: PipelineNode {
    let step: MeetingTaskStatus = .uploading
    let channelId: Int
    
    init(channelId: Int = 0) { self.channelId = channelId }
    
    func run(board: inout PipelineBoard, services: ServiceProvider) async throws {
        // 1. Read Input
        let channel = try board.getChannel(channelId)
        guard let inputPath = channel.processedAudioPath else {
            throw PipelineError.inputMissing("Processed audio path missing")
        }
        
        // 2. Idempotency Check
        if channel.processedAudioOssURL != nil {
            print("UploadNode: URL exists, skipping upload.")
            return
        }
        
        // 3. Execution
        let datePath = board.formattedDatePath()
        
        let fileURL = URL(fileURLWithPath: inputPath)
        // Note: Keeping legacy naming convention (mixed.m4a instead of mixed_48k.m4a in OSS) for consistency with existing data
        let filename = channelId == 0 ? "mixed.m4a" : "speaker\(channelId).m4a"
        let objectKey = "\(board.config.ossPrefix)\(datePath)/\(board.recordingId)/\(filename)"
        
        let url = try await services.ossService.uploadFile(fileURL: fileURL, objectKey: objectKey)
        
        // 4. Write Output
        board.updateChannel(channelId) { $0.processedAudioOssURL = url }
    }
}

// MARK: - 4. 创建听悟任务
class CreateTaskNode: PipelineNode {
    let step: MeetingTaskStatus = .created
    let channelId: Int
    
    init(channelId: Int = 0) { self.channelId = channelId }
    
    func run(board: inout PipelineBoard, services: ServiceProvider) async throws {
        // 1. Read Input
        let channel = try board.getChannel(channelId)
        guard let url = channel.processedAudioOssURL else {
            throw PipelineError.inputMissing("OSS URL missing")
        }
        
        // 2. Idempotency Check
        if channel.tingwuTaskId != nil {
            print("CreateTaskNode: Task ID exists, skipping creation.")
            return
        }
        
        // 3. Execution
        // TODO: Pass configuration parameters (summarization, diarization)
        let taskId = try await services.tingwuService.createTask(fileUrl: url)
        
        // 4. Write Output
        board.updateChannel(channelId) { $0.tingwuTaskId = taskId }
    }
}

// MARK: - 5. 轮询任务
class PollingNode: PipelineNode {
    let step: MeetingTaskStatus = .polling
    let channelId: Int
    
    init(channelId: Int = 0) { self.channelId = channelId }
    
    func run(board: inout PipelineBoard, services: ServiceProvider) async throws {
        // 1. Read Input
        let channel = try board.getChannel(channelId)
        guard let taskId = channel.tingwuTaskId else {
            throw PipelineError.inputMissing("Task ID missing")
        }
        
        // 2. Execution
        let (status, data) = try await services.tingwuService.getTaskInfo(taskId: taskId)
        
        // 3. Write Status
        board.updateChannel(channelId) { $0.tingwuTaskStatus = status }
        
        if status == "SUCCESS" || status == "COMPLETED" {
            if let result = data?["Result"] as? [String: Any] {
                // Parse all data types for complete storage
                let transcriptText = await fetchTranscript(from: result, service: services.tingwuService)
                let summaryText = await fetchSummary(from: result, service: services.tingwuService)
                
                // Fetch complete data for database storage
                let overviewData = await fetchOverviewData(from: result, service: services.tingwuService)
                let transcriptData = await fetchTranscriptData(from: result, service: services.tingwuService)
                let conversationData = await fetchConversationData(from: result, service: services.tingwuService)
                let rawData = await fetchRawData(from: data, service: services.tingwuService)
                
                // 4. Write Output
                board.updateChannel(channelId) {
                    $0.transcript = TingwuResult(text: transcriptText, summary: summaryText)
                    $0.overviewData = overviewData
                    $0.transcriptData = transcriptData
                    $0.conversationData = conversationData
                    $0.rawData = rawData
                }
            }
        } else if status == "FAILED" {
            let errorMsg = (data?["StatusText"] as? String) 
                ?? (data?["_OuterMessage"] as? String)
                ?? "Unknown cloud error"
            
            // Debug logging
            if let data = data {
                print("PollingNode: Task Failed. Data: \(data)")
            }
            
            throw PipelineError.cloudError(errorMsg)
        } else {
            // Still running
            throw PipelineError.taskRunning
        }
    }
    
    // --- Helper Methods (Simplified for Board) ---
    // Note: Ideally these should be in a separate Parser class
    
    private func fetchSummary(from result: [String: Any], service: TingwuService) async -> String? {
        if let summarizationUrl = result["Summarization"] as? String {
            if let data = try? await service.fetchJSON(url: summarizationUrl),
               let obj = data["Summarization"] as? [String: Any],
               let text = obj["ParagraphSummary"] as? String {
                return text
            }
        }
        return nil
    }
    
    private func fetchTranscript(from result: [String: Any], service: TingwuService) async -> String? {
        if let transcriptionUrl = result["Transcription"] as? String {
             if let data = try? await service.fetchJSON(url: transcriptionUrl) {
                 return TranscriptParser.buildTranscriptText(from: data)
             }
        }
        return nil
    }
    
    // buildTranscriptText removed, using TranscriptParser instead
    
    // New helper methods for complete data storage
    private func fetchOverviewData(from result: [String: Any], service: TingwuService) async -> String? {
        // Try to fetch summarization data
        if let summarizationUrl = result["Summarization"] as? String {
            if let data = try? await service.fetchJSON(url: summarizationUrl) {
                if let jsonData = try? JSONSerialization.data(withJSONObject: data),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    return jsonString
                }
            }
        }
        return nil
    }
    
    private func fetchTranscriptData(from result: [String: Any], service: TingwuService) async -> String? {
        // Try to fetch transcription data
        if let transcriptionUrl = result["Transcription"] as? String {
            if let data = try? await service.fetchJSON(url: transcriptionUrl) {
                if let jsonData = try? JSONSerialization.data(withJSONObject: data),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    return jsonString
                }
            }
        }
        return nil
    }
    
    private func fetchConversationData(from result: [String: Any], service: TingwuService) async -> String? {
        // Try to fetch conversation data if available
        if let conversationUrl = result["Conversation"] as? String {
            if let data = try? await service.fetchJSON(url: conversationUrl) {
                if let jsonData = try? JSONSerialization.data(withJSONObject: data),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    return jsonString
                }
            }
        }
        return nil
    }
    
    private func fetchRawData(from data: [String: Any]?, service: TingwuService) async -> String? {
        // Store the complete raw response data
        if let data = data {
            if let jsonData = try? JSONSerialization.data(withJSONObject: data),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString
            }
        }
        return nil
    }
}
