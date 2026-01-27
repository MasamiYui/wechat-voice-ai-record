import Foundation
import Combine
import AVFoundation

class MeetingPipelineManager: ObservableObject {
    @Published var task: MeetingTask
    @Published var isProcessing: Bool = false
    @Published var errorMessage: String?
    
    private let ossService: OSSService
    private let tingwuService: TingwuService
    private let settings: SettingsStore
    
    init(task: MeetingTask, settings: SettingsStore) {
        self.task = task
        self.settings = settings
        self.ossService = OSSService(settings: settings)
        self.tingwuService = TingwuService(settings: settings)
    }
    
    // MARK: - Public Actions
    
    func start() async {
        if task.mode == .mixed {
            await runMixedPipeline()
        } else {
            await runSeparatedPipeline()
        }
    }
    
    func transcode(force: Bool = false) async {
        if !force && task.status != .recorded && task.status != .failed { return }
        
        // Decide start point based on mode
        await start()
    }
    
    // Legacy support for View buttons calling specific steps
    // We map them to running the pipeline from that step
    func upload() async {
        if task.mode == .mixed {
            await runPipeline(from: .uploading, targetSpeaker: nil)
        } else {
            // If upload is called manually, it implies a retry or manual trigger
            // We should check which one needs upload
             await runSeparatedPipeline(from: .uploading)
        }
    }
    
    func createTask() async {
        if task.mode == .mixed {
            await runPipeline(from: .created, targetSpeaker: nil)
        } else {
            await runSeparatedPipeline(from: .created)
        }
    }
    
    func pollStatus() async {
        if task.mode == .mixed {
            await runPipeline(from: .polling, targetSpeaker: nil)
        } else {
            await runSeparatedPipeline(from: .polling)
        }
    }
    
    // MARK: - Retry Logic
    
    func retry() async {
        await retry(speaker: nil)
    }
    
    func retry(speaker: Int?) async {
        settings.log("Retry requested for speaker: \(speaker ?? 0)")
        
        if task.mode == .mixed {
            let startStep = task.failedStep ?? .recorded
            await runPipeline(from: startStep, targetSpeaker: nil)
        } else {
            // Separated Mode
            if let spk = speaker {
                // Retry specific speaker
                let startStep: MeetingTaskStatus
                if spk == 1 {
                    startStep = task.speaker1FailedStep ?? .recorded
                } else {
                    startStep = task.speaker2FailedStep ?? .recorded
                }
                await runSingleTrack(from: startStep, speaker: spk)
                
                // After single track finishes, try alignment if both ready
                await tryAlign()
            } else {
                // Retry both (legacy behavior or generic retry button)
                await runSeparatedPipeline()
            }
        }
    }
    
    func restartFromBeginning() async {
        settings.log("Restart from beginning")
        // Reset Task
        var resetTask = task
        resetTask.status = .recorded
        resetTask.originalOssUrl = nil
        resetTask.speaker2OriginalOssUrl = nil
        resetTask.ossUrl = nil
        resetTask.speaker2OssUrl = nil
        resetTask.tingwuTaskId = nil
        resetTask.speaker2TingwuTaskId = nil
        resetTask.transcript = nil
        resetTask.speaker1Transcript = nil
        resetTask.speaker2Transcript = nil
        resetTask.summary = nil
        resetTask.failedStep = nil
        resetTask.speaker1FailedStep = nil
        resetTask.speaker2FailedStep = nil
        resetTask.speaker1Status = nil
        resetTask.speaker2Status = nil
        
        self.task = resetTask
        self.save()
        
        await start()
    }
    
    // MARK: - Pipeline Execution
    
    private func runMixedPipeline() async {
        // Full chain
        await runPipeline(from: .transcoding, targetSpeaker: nil)
    }
    
    private func runSeparatedPipeline(from step: MeetingTaskStatus = .transcoding) async {
        async let t1: Void = runSingleTrack(from: step == .transcoding ? (task.speaker1Status == .completed ? .completed : step) : step, speaker: 1)
        async let t2: Void = runSingleTrack(from: step == .transcoding ? (task.speaker2Status == .completed ? .completed : step) : step, speaker: 2)
        
        _ = await (t1, t2)
        await tryAlign()
    }
    
    private func runSingleTrack(from startStep: MeetingTaskStatus, speaker: Int) async {
        // If already completed, skip unless forced (not handled here for simplicity)
        if (speaker == 1 && task.speaker1Status == .completed && startStep != .polling) ||
           (speaker == 2 && task.speaker2Status == .completed && startStep != .polling) {
            return
        }
        
        var nodes: [PipelineNode] = []
        
        // Build chain based on startStep
        if startStep == .recorded || startStep == .failed {
            nodes.append(UploadOriginalNode(targetSpeaker: speaker))
            nodes.append(TranscodeNode(targetSpeaker: speaker))
            nodes.append(UploadNode(targetSpeaker: speaker))
            nodes.append(CreateTaskNode(targetSpeaker: speaker))
            nodes.append(PollingNode(targetSpeaker: speaker))
        } else if startStep == .uploadingOriginal {
            nodes.append(UploadOriginalNode(targetSpeaker: speaker))
            nodes.append(TranscodeNode(targetSpeaker: speaker))
            nodes.append(UploadNode(targetSpeaker: speaker))
            nodes.append(CreateTaskNode(targetSpeaker: speaker))
            nodes.append(PollingNode(targetSpeaker: speaker))
        } else if startStep == .uploadedOriginal || startStep == .transcoding {
            nodes.append(TranscodeNode(targetSpeaker: speaker))
            nodes.append(UploadNode(targetSpeaker: speaker))
            nodes.append(CreateTaskNode(targetSpeaker: speaker))
            nodes.append(PollingNode(targetSpeaker: speaker))
        } else if startStep == .transcoded || startStep == .uploading {
            nodes.append(UploadNode(targetSpeaker: speaker))
            nodes.append(CreateTaskNode(targetSpeaker: speaker))
            nodes.append(PollingNode(targetSpeaker: speaker))
        } else if startStep == .uploaded || startStep == .created {
            nodes.append(CreateTaskNode(targetSpeaker: speaker))
            nodes.append(PollingNode(targetSpeaker: speaker))
        } else if startStep == .polling {
            nodes.append(PollingNode(targetSpeaker: speaker))
        }
        
        await executeChain(nodes: nodes, speaker: speaker)
    }
    
    private func runPipeline(from startStep: MeetingTaskStatus, targetSpeaker: Int?) async {
        var nodes: [PipelineNode] = []
        
        // Logic for mixed mode mainly
        if startStep == .recorded || startStep == .failed {
            nodes.append(UploadOriginalNode(targetSpeaker: targetSpeaker))
            nodes.append(TranscodeNode(targetSpeaker: targetSpeaker))
            nodes.append(UploadNode(targetSpeaker: targetSpeaker))
            nodes.append(CreateTaskNode(targetSpeaker: targetSpeaker))
            nodes.append(PollingNode(targetSpeaker: targetSpeaker))
        } else if startStep == .uploadingOriginal {
            nodes.append(UploadOriginalNode(targetSpeaker: targetSpeaker))
            nodes.append(TranscodeNode(targetSpeaker: targetSpeaker))
            nodes.append(UploadNode(targetSpeaker: targetSpeaker))
            nodes.append(CreateTaskNode(targetSpeaker: targetSpeaker))
            nodes.append(PollingNode(targetSpeaker: targetSpeaker))
        } else if startStep == .uploadedOriginal || startStep == .transcoding {
            nodes.append(TranscodeNode(targetSpeaker: targetSpeaker))
            nodes.append(UploadNode(targetSpeaker: targetSpeaker))
            nodes.append(CreateTaskNode(targetSpeaker: targetSpeaker))
            nodes.append(PollingNode(targetSpeaker: targetSpeaker))
        } else if startStep == .transcoded || startStep == .uploading {
            nodes.append(UploadNode(targetSpeaker: targetSpeaker))
            nodes.append(CreateTaskNode(targetSpeaker: targetSpeaker))
            nodes.append(PollingNode(targetSpeaker: targetSpeaker))
        } else if startStep == .uploaded || startStep == .created {
            nodes.append(CreateTaskNode(targetSpeaker: targetSpeaker))
            nodes.append(PollingNode(targetSpeaker: targetSpeaker))
        } else if startStep == .polling {
            nodes.append(PollingNode(targetSpeaker: targetSpeaker))
        }
        
        await executeChain(nodes: nodes, speaker: targetSpeaker)
    }
    
    private func executeChain(nodes: [PipelineNode], speaker: Int?) async {
        await MainActor.run { self.isProcessing = true }
        
        for node in nodes {
            // 1. Update Status to Running
            await updateStatus(node.step, speaker: speaker, isFailed: false)
            
            // 2. Run Node
            var success = false
            var retryCount = 0
            let maxRetries = 60 // For polling
            
            while !success {
                do {
                    let context = PipelineContext(task: self.task, settings: self.settings, ossService: self.ossService, tingwuService: self.tingwuService)
                    let updatedTask = try await node.run(context: context)
                    
                    await MainActor.run {
                        self.task = updatedTask
                        // Specific status updates for separated mode
                        if let spk = speaker {
                            if spk == 1 { self.task.speaker1Status = node.step == .polling ? .completed : node.step }
                            else { self.task.speaker2Status = node.step == .polling ? .completed : node.step }
                        }
                    }
                    self.save()
                    success = true
                    
                } catch {
                    let nsError = error as NSError
                    if nsError.code == 202 && node is PollingNode {
                        // Polling: wait and retry
                        retryCount += 1
                        if retryCount > maxRetries {
                            await updateStatus(.failed, speaker: speaker, step: node.step, error: "Polling timeout")
                            return
                        }
                        try? await Task.sleep(nanoseconds: 2 * 1_000_000_000) // 2s
                        continue
                    } else {
                        // Real failure
                        await updateStatus(.failed, speaker: speaker, step: node.step, error: error.localizedDescription)
                        return
                    }
                }
            }
        }
        
        // Chain completed
        if speaker == nil {
            await updateStatus(.completed, speaker: nil, isFailed: false)
        }
        await MainActor.run { self.isProcessing = false }
    }
    
    private func updateStatus(_ status: MeetingTaskStatus, speaker: Int?, step: MeetingTaskStatus? = nil, error: String? = nil, isFailed: Bool = false) async {
        await MainActor.run {
            if isFailed {
                if let spk = speaker {
                    if spk == 1 {
                        self.task.speaker1Status = .failed
                        self.task.speaker1FailedStep = step
                    } else {
                        self.task.speaker2Status = .failed
                        self.task.speaker2FailedStep = step
                    }
                    // Global status update?
                    self.task.status = .failed
                } else {
                    self.task.status = .failed
                    self.task.failedStep = step
                }
                self.task.lastError = error
                self.errorMessage = error
                self.isProcessing = false
            } else {
                // Running status
                if let spk = speaker {
                    if spk == 1 { self.task.speaker1Status = status }
                    else { self.task.speaker2Status = status }
                    // Update global status to something meaningful?
                    if self.task.status != .polling { self.task.status = status }
                } else {
                    self.task.status = status
                }
                self.errorMessage = nil
            }
        }
        self.save()
    }
    
    private func tryAlign() async {
        // Only if both are done (or one done one failed?)
        // For now, simple merge if both have content
        await MainActor.run {
            let t1 = self.task.speaker1Transcript ?? ""
            let t2 = self.task.speaker2Transcript ?? ""
            
            if !t1.isEmpty || !t2.isEmpty {
                var merged = ""
                if !t1.isEmpty { merged += "### Speaker 1 (Local)\n\(t1)\n\n" }
                if !t2.isEmpty { merged += "### Speaker 2 (Remote)\n\(t2)\n" }
                self.task.transcript = merged
                self.task.status = .completed
                self.save()
            }
        }
    }
    
    func buildTranscriptText(from transcriptionData: [String: Any]) -> String {
        func build(from data: [String: Any]) -> String? {
            if let result = data["Result"] as? [String: Any],
               let transcription = result["Transcription"] as? [String: Any] {
                return build(from: transcription)
            }
            if let transcription = data["Transcription"] as? [String: Any] {
                return build(from: transcription)
            }
            if let paragraphs = data["Paragraphs"] as? [[String: Any]] {
                return paragraphs.compactMap { extractLine(from: $0) }.joined(separator: "\n")
            }
            if let sentences = data["Sentences"] as? [[String: Any]] {
                return sentences.compactMap { extractLine(from: $0) }.joined(separator: "\n")
            }
            if let transcript = data["Transcript"] as? String {
                return transcript
            }
            return nil
        }
        
        func extractLine(from item: [String: Any]) -> String? {
            let speaker = extractSpeaker(from: item)
            let text = extractText(from: item)
            guard !text.isEmpty else { return nil }
            if let speaker {
                return "\(speaker): \(text)"
            }
            return text
        }
        
        func extractText(from item: [String: Any]) -> String {
            if let text = item["Text"] as? String, !text.isEmpty { return text }
            if let text = item["text"] as? String, !text.isEmpty { return text }
            if let words = item["Words"] as? [[String: Any]] {
                return words.compactMap { $0["Text"] as? String ?? $0["text"] as? String }.joined()
            }
            return ""
        }
        
        func extractSpeaker(from item: [String: Any]) -> String? {
            if let name = item["SpeakerName"] as? String, !name.isEmpty { return name }
            if let name = item["Speaker"] as? String, !name.isEmpty { return name }
            if let id = item["SpeakerId"] ?? item["SpeakerID"] { return "Speaker \(id)" }
            return nil
        }
        
        return build(from: transcriptionData) ?? ""
    }

    private func save() {
        Task { try? await StorageManager.shared.currentProvider.saveTask(self.task) }
    }
}

// MARK: - Core Abstractions

struct PipelineContext {
    var task: MeetingTask
    let settings: SettingsStore
    let ossService: OSSService
    let tingwuService: TingwuService
    
    // Helper to log
    func log(_ message: String) {
        settings.log(message)
    }
}

protocol PipelineNode {
    var step: MeetingTaskStatus { get }
    
    // Returns the updated task if successful. Throws error if failed.
    func run(context: PipelineContext) async throws -> MeetingTask
}

// MARK: - Concrete Nodes

// 0. Upload Original Node
class UploadOriginalNode: PipelineNode {
    let step: MeetingTaskStatus = .uploadingOriginal
    let targetSpeaker: Int?
    
    init(targetSpeaker: Int? = nil) {
        self.targetSpeaker = targetSpeaker
    }
    
    func run(context: PipelineContext) async throws -> MeetingTask {
        context.log("UploadOriginalNode start: target=\(targetSpeaker ?? 0)")
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        let datePath = formatter.string(from: context.task.createdAt)
        
        var fileURL: URL
        var objectKey: String
        
        if let spk = targetSpeaker {
            if spk == 1 {
                guard let path = context.task.speaker1AudioPath else { throw NSError(domain: "Pipeline", code: 404, userInfo: [NSLocalizedDescriptionKey: "Speaker 1 path missing"]) }
                fileURL = URL(fileURLWithPath: path)
                // Use _raw suffix
                objectKey = "\(context.settings.ossPrefix)\(datePath)/\(context.task.recordingId)/speaker1_raw.m4a"
            } else {
                guard let path = context.task.speaker2AudioPath else { throw NSError(domain: "Pipeline", code: 404, userInfo: [NSLocalizedDescriptionKey: "Speaker 2 path missing"]) }
                fileURL = URL(fileURLWithPath: path)
                objectKey = "\(context.settings.ossPrefix)\(datePath)/\(context.task.recordingId)/speaker2_raw.m4a"
            }
        } else {
            fileURL = URL(fileURLWithPath: context.task.localFilePath)
            objectKey = "\(context.settings.ossPrefix)\(datePath)/\(context.task.recordingId)/mixed_raw.m4a"
        }
        
        let url = try await context.ossService.uploadFile(fileURL: fileURL, objectKey: objectKey)
        context.log("Upload Original success: \(url)")
        
        var updatedTask = context.task
        if let spk = targetSpeaker {
            if spk == 1 {
                updatedTask.originalOssUrl = url
            } else {
                updatedTask.speaker2OriginalOssUrl = url
            }
        } else {
            updatedTask.originalOssUrl = url
        }
        
        return updatedTask
    }
}

// 1. Transcode Node
class TranscodeNode: PipelineNode {
    let step: MeetingTaskStatus = .transcoding
    let targetSpeaker: Int? // nil for mixed, 1 for spk1, 2 for spk2
    
    init(targetSpeaker: Int? = nil) {
        self.targetSpeaker = targetSpeaker
    }
    
    func run(context: PipelineContext) async throws -> MeetingTask {
        context.log("TranscodeNode start: target=\(targetSpeaker ?? 0)")
        
        var inputPath: String?
        var outputPath: String
        
        if let spk = targetSpeaker {
            if spk == 1 {
                inputPath = context.task.speaker1AudioPath
                outputPath = URL(fileURLWithPath: inputPath ?? "").deletingLastPathComponent().appendingPathComponent("speaker1_48k.m4a").path
            } else {
                inputPath = context.task.speaker2AudioPath
                outputPath = URL(fileURLWithPath: inputPath ?? "").deletingLastPathComponent().appendingPathComponent("speaker2_48k.m4a").path
            }
        } else {
            inputPath = context.task.localFilePath
            outputPath = URL(fileURLWithPath: inputPath ?? "").deletingLastPathComponent().appendingPathComponent("mixed_48k.m4a").path
        }
        
        guard let input = inputPath, !input.isEmpty else {
            throw NSError(domain: "Pipeline", code: 404, userInfo: [NSLocalizedDescriptionKey: "Input file path missing"])
        }
        
        let inputURL = URL(fileURLWithPath: input)
        let outputURL = URL(fileURLWithPath: outputPath)
        
        if await performTranscode(input: inputURL, output: outputURL, context: context) {
            var updatedTask = context.task
            if let spk = targetSpeaker {
                if spk == 1 {
                    updatedTask.speaker1AudioPath = outputPath
                    // In separated mode, localFilePath tracks speaker 1 (local)
                    updatedTask.localFilePath = outputPath
                } else {
                    updatedTask.speaker2AudioPath = outputPath
                }
            } else {
                updatedTask.localFilePath = outputPath
            }
            return updatedTask
        } else {
            throw NSError(domain: "Pipeline", code: 500, userInfo: [NSLocalizedDescriptionKey: "Transcode failed"])
        }
    }
    
    private func performTranscode(input: URL, output: URL, context: PipelineContext) async -> Bool {
        try? FileManager.default.removeItem(at: output)
        
        // Basic check if input file exists and has content
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: input.path)
            if let size = attrs[.size] as? UInt64, size == 0 {
                context.log("Transcode failed: Input file \(input.lastPathComponent) is empty (0 bytes)")
                return false
            }
        } catch {
            context.log("Transcode failed: Cannot access input file \(input.lastPathComponent): \(error.localizedDescription)")
            return false
        }

        let asset = AVAsset(url: input)
        
        // Check if asset is readable
        do {
            let isReadable = try await asset.load(.isReadable)
            if !isReadable {
                context.log("Transcode failed: Input file \(input.lastPathComponent) is not readable by AVAsset")
                return false
            }
        } catch {
            context.log("Transcode failed: Failed to load asset metadata for \(input.lastPathComponent): \(error.localizedDescription)")
            return false
        }

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            context.log("Transcode failed: cannot create export session for \(input.lastPathComponent)")
            return false
        }
        
        exportSession.outputURL = output
        exportSession.outputFileType = .m4a
        await exportSession.export()
        
        if exportSession.status == .completed {
            return true
        } else {
            let err = exportSession.error?.localizedDescription ?? "Unknown error"
            context.log("Transcode failed for \(input.lastPathComponent): \(err)")
            return false
        }
    }
}

// 2. Upload Node
class UploadNode: PipelineNode {
    let step: MeetingTaskStatus = .uploading
    let targetSpeaker: Int?
    
    init(targetSpeaker: Int? = nil) {
        self.targetSpeaker = targetSpeaker
    }
    
    func run(context: PipelineContext) async throws -> MeetingTask {
        context.log("UploadNode start: target=\(targetSpeaker ?? 0)")
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        let datePath = formatter.string(from: context.task.createdAt)
        
        var fileURL: URL
        var objectKey: String
        
        if let spk = targetSpeaker {
            if spk == 1 {
                guard let path = context.task.speaker1AudioPath else { throw NSError(domain: "Pipeline", code: 404, userInfo: [NSLocalizedDescriptionKey: "Speaker 1 path missing"]) }
                fileURL = URL(fileURLWithPath: path)
                objectKey = "\(context.settings.ossPrefix)\(datePath)/\(context.task.recordingId)/speaker1.m4a"
            } else {
                guard let path = context.task.speaker2AudioPath else { throw NSError(domain: "Pipeline", code: 404, userInfo: [NSLocalizedDescriptionKey: "Speaker 2 path missing"]) }
                fileURL = URL(fileURLWithPath: path)
                objectKey = "\(context.settings.ossPrefix)\(datePath)/\(context.task.recordingId)/speaker2.m4a"
            }
        } else {
            fileURL = URL(fileURLWithPath: context.task.localFilePath)
            objectKey = "\(context.settings.ossPrefix)\(datePath)/\(context.task.recordingId)/mixed.m4a"
        }
        
        let url = try await context.ossService.uploadFile(fileURL: fileURL, objectKey: objectKey)
        context.log("Upload success: \(url)")
        
        var updatedTask = context.task
        if let spk = targetSpeaker {
            if spk == 1 {
                updatedTask.ossUrl = url // Primary OSS URL tracks Speaker 1 in separated mode
            } else {
                updatedTask.speaker2OssUrl = url
            }
        } else {
            updatedTask.ossUrl = url
        }
        
        return updatedTask
    }
}

// 3. Create Task Node
class CreateTaskNode: PipelineNode {
    let step: MeetingTaskStatus = .created
    let targetSpeaker: Int?
    
    init(targetSpeaker: Int? = nil) {
        self.targetSpeaker = targetSpeaker
    }
    
    func run(context: PipelineContext) async throws -> MeetingTask {
        context.log("CreateTaskNode start: target=\(targetSpeaker ?? 0)")
        
        var fileUrl: String?
        if let spk = targetSpeaker {
            if spk == 1 {
                fileUrl = context.task.ossUrl
            } else {
                fileUrl = context.task.speaker2OssUrl
            }
        } else {
            fileUrl = context.task.ossUrl
        }
        
        guard let url = fileUrl else {
            throw NSError(domain: "Pipeline", code: 404, userInfo: [NSLocalizedDescriptionKey: "OSS URL missing"])
        }
        
        let taskId = try await context.tingwuService.createTask(fileUrl: url)
        context.log("Create task success: \(taskId)")
        
        var updatedTask = context.task
        if let spk = targetSpeaker {
            if spk == 1 {
                updatedTask.tingwuTaskId = taskId
            } else {
                updatedTask.speaker2TingwuTaskId = taskId
            }
        } else {
            updatedTask.tingwuTaskId = taskId
        }
        
        return updatedTask
    }
}

// 4. Polling Node
class PollingNode: PipelineNode {
    let step: MeetingTaskStatus = .polling
    let targetSpeaker: Int?
    
    init(targetSpeaker: Int? = nil) {
        self.targetSpeaker = targetSpeaker
    }
    
    func run(context: PipelineContext) async throws -> MeetingTask {
        context.log("PollingNode start: target=\(targetSpeaker ?? 0)")
        
        var taskId: String?
        if let spk = targetSpeaker {
            if spk == 1 {
                taskId = context.task.tingwuTaskId
            } else {
                taskId = context.task.speaker2TingwuTaskId
            }
        } else {
            taskId = context.task.tingwuTaskId
        }
        
        guard let id = taskId else {
            throw NSError(domain: "Pipeline", code: 404, userInfo: [NSLocalizedDescriptionKey: "Task ID missing"])
        }
        
        let (status, data) = try await context.tingwuService.getTaskInfo(taskId: id)
        context.log("Poll status: \(status)")
        
        var updatedTask = context.task
        
        if status == "SUCCESS" || status == "COMPLETED" {
            if let result = data?["Result"] as? [String: Any] {
                // Common metadata update
                if targetSpeaker == nil {
                     // Mixed Mode Logic
                     updatedTask.status = .completed
                     updateMetadata(task: &updatedTask, data: data, result: result)
                     if let transcript = await fetchTranscript(from: result, service: context.tingwuService) {
                         updatedTask.transcript = transcript
                     }
                     // Summary Logic
                     await updateSummary(task: &updatedTask, result: result, service: context.tingwuService)
                } else {
                    // Separated Mode Logic
                    if targetSpeaker == 1 {
                        updatedTask.speaker1Status = .completed
                        if let transcript = await fetchTranscript(from: result, service: context.tingwuService) {
                            updatedTask.speaker1Transcript = transcript
                        }
                    } else {
                        updatedTask.speaker2Status = .completed
                        if let transcript = await fetchTranscript(from: result, service: context.tingwuService) {
                            updatedTask.speaker2Transcript = transcript
                        }
                    }
                }
            }
            return updatedTask
        } else if status == "FAILED" {
            // Failure handling
            if let data = data {
                if let taskKey = data["TaskKey"] as? String { updatedTask.taskKey = taskKey }
                if let taskStatus = data["TaskStatus"] as? String { updatedTask.apiStatus = taskStatus }
                if let statusText = data["StatusText"] as? String { updatedTask.statusText = statusText }
            }
            throw NSError(domain: "Pipeline", code: 500, userInfo: [NSLocalizedDescriptionKey: "Cloud task failed: \(updatedTask.statusText ?? "Unknown")"])
        } else {
            // Still running
            throw NSError(domain: "Pipeline", code: 202, userInfo: [NSLocalizedDescriptionKey: "Task running"])
        }
    }
    
    // MARK: - Helpers
    
    private func updateMetadata(task: inout MeetingTask, data: [String: Any]?, result: [String: Any]) {
        if let taskKey = data?["TaskKey"] as? String { task.taskKey = taskKey }
        if let taskStatus = data?["TaskStatus"] as? String { task.apiStatus = taskStatus }
        if let statusText = data?["StatusText"] as? String { task.statusText = statusText }
        if let bizDuration = data?["BizDuration"] as? Int { task.bizDuration = bizDuration }
        if let outputMp3Path = result["OutputMp3Path"] as? String { task.outputMp3Path = outputMp3Path }
        
        if let data = data, let jsonData = try? JSONSerialization.data(withJSONObject: data, options: .prettyPrinted) {
            task.rawResponse = String(data: jsonData, encoding: .utf8)
        }
    }
    
    private func updateSummary(task: inout MeetingTask, result: [String: Any], service: TingwuService) async {
        // ... (Logic from MeetingPipelineManager) ...
        // Simplified for brevity, assume similar logic or copy-paste
        // For now, let's copy the core logic
        if let summarizationUrl = result["Summarization"] as? String {
             if let summarizationData = try? await service.fetchJSON(url: summarizationUrl) {
                 if let summarizationObj = summarizationData["Summarization"] as? [String: Any] {
                     if let summary = summarizationObj["ParagraphTitle"] as? String {
                         task.summary = summary
                     }
                     if let summaryText = summarizationObj["ParagraphSummary"] as? String {
                         task.summary = (task.summary ?? "") + "\n\n" + summaryText
                     }
                 }
             }
        }
    }
    
    private func fetchTranscript(from result: [String: Any], service: TingwuService) async -> String? {
        var transcriptText: String?
        if let transcriptionUrl = result["Transcription"] as? String {
            do {
                let transcriptionData = try await service.fetchJSON(url: transcriptionUrl)
                transcriptText = buildTranscriptText(from: transcriptionData)
            } catch {
                print("Failed to download transcript")
            }
        } else if let transcriptionObj = result["Transcription"] as? [String: Any] {
            transcriptText = buildTranscriptText(from: transcriptionObj)
        }
        
        if transcriptText == nil {
            if let paragraphs = result["Paragraphs"] as? [[String: Any]] {
                transcriptText = buildTranscriptText(from: ["Paragraphs": paragraphs])
            } else if let sentences = result["Sentences"] as? [[String: Any]] {
                transcriptText = buildTranscriptText(from: ["Sentences": sentences])
            } else if let transcriptInline = result["Transcript"] as? String {
                transcriptText = transcriptInline
            }
        }
        return transcriptText
    }
    
    private func buildTranscriptText(from transcriptionData: [String: Any]) -> String? {
        // Reuse logic from previous manager
        if let result = transcriptionData["Result"] as? [String: Any],
           let transcription = result["Transcription"] as? [String: Any] {
            return buildTranscriptText(from: transcription)
        }
        if let transcription = transcriptionData["Transcription"] as? [String: Any] {
            return buildTranscriptText(from: transcription)
        }
        if let paragraphs = transcriptionData["Paragraphs"] as? [[String: Any]] {
            return paragraphs.compactMap { extractLine(from: $0) }.joined(separator: "\n")
        }
        if let sentences = transcriptionData["Sentences"] as? [[String: Any]] {
            return sentences.compactMap { extractLine(from: $0) }.joined(separator: "\n")
        }
        if let transcript = transcriptionData["Transcript"] as? String {
            return transcript
        }
        return nil
    }
    
    private func extractLine(from item: [String: Any]) -> String? {
        let speaker = extractSpeaker(from: item)
        let text = extractText(from: item)
        guard !text.isEmpty else { return nil }
        if let speaker {
            return "\(speaker): \(text)"
        }
        return text
    }
    
    private func extractText(from item: [String: Any]) -> String {
        if let text = item["Text"] as? String, !text.isEmpty { return text }
        if let text = item["text"] as? String, !text.isEmpty { return text }
        if let words = item["Words"] as? [[String: Any]] {
            return words.compactMap { $0["Text"] as? String ?? $0["text"] as? String }.joined()
        }
        return ""
    }
    
    private func extractSpeaker(from item: [String: Any]) -> String? {
        if let name = item["SpeakerName"] as? String, !name.isEmpty { return name }
        if let name = item["Speaker"] as? String, !name.isEmpty { return name }
        if let id = item["SpeakerId"] ?? item["SpeakerID"] { return "Speaker \(id)" }
        return nil
    }
}
