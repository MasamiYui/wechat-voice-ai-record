import Foundation
import Combine

class MeetingPipelineManager: ObservableObject {
    @Published var task: MeetingTask
    @Published var isProcessing: Bool = false
    @Published var errorMessage: String?
    
    private let ossService: OSSService
    private let tingwuService: TingwuService
    private let settings: SettingsStore
    
    private struct PipelineConstants {
        static let maxPollingRetries = 60
        static let pollingInterval: UInt64 = 2 * 1_000_000_000
    }
    
    init(task: MeetingTask, settings: SettingsStore) {
        self.task = task
        self.settings = settings
        self.ossService = OSSService(settings: settings)
        self.tingwuService = TingwuService(settings: settings)
    }
    
    // MARK: - Public Actions
    
    func start() async {
        await uploadOriginal()
    }
    
    func transcode(force: Bool = false) async {
        if !force && task.status != .uploadedRaw && task.status != .failed { return }
        await runPipeline(from: .transcoding)
    }
    
    func upload() async {
        await runPipeline(from: .uploading)
    }
    
    func uploadOriginal() async {
        await runPipeline(from: .uploadingRaw)
    }
    
    func createTask() async {
        await runPipeline(from: .created)
    }
    
    func pollStatus() async {
        await runPipeline(from: .polling)
    }
    
    // MARK: - Retry Logic
    
    func retry() async {
        settings.log("Retry requested")
        let startStep = task.failedStep ?? .recorded
        await runPipeline(from: startStep)
    }
    
    func restartFromBeginning() async {
        settings.log("Restart from beginning")
        let resetTask = task
        resetTask.status = .recorded
        resetTask.originalOssUrl = nil
        resetTask.ossUrl = nil
        resetTask.tingwuTaskId = nil
        resetTask.transcript = nil
        resetTask.summary = nil
        resetTask.failedStep = nil
        
        self.task = resetTask
        await self.save()
        
        await start()
    }
    
    // MARK: - Pipeline Orchestration
    
    private func runPipeline(from startStep: MeetingTaskStatus) async {
        let nodes = buildChain(from: startStep, channelId: 0)
        await executeChain(nodes: nodes)
    }
    
    private func buildChain(from startStep: MeetingTaskStatus, channelId: Int) -> [PipelineNode] {
        var nodes: [PipelineNode] = []
        
        if startStep == .recorded || startStep == .failed {
            nodes.append(UploadOriginalNode(channelId: channelId))
        } else if startStep == .uploadingRaw {
            nodes.append(UploadOriginalNode(channelId: channelId))
        } else if startStep == .uploadedRaw || startStep == .transcoding {
            nodes.append(TranscodeNode(channelId: channelId))
        } else if startStep == .transcoded || startStep == .uploading {
            nodes.append(UploadNode(channelId: channelId))
        } else if startStep == .uploaded || startStep == .created {
            nodes.append(CreateTaskNode(channelId: channelId))
        } else if startStep == .polling {
            nodes.append(PollingNode(channelId: channelId))
        }
        
        return nodes
    }
    
    // MARK: - Board & Execution Logic
    
    private func executeChain(nodes: [PipelineNode]) async {
        // 1. Hydrate Board from Task
        let taskSnapshot = await MainActor.run { self.task }
        var board = createBoard(from: taskSnapshot)
        let services = ServiceProvider(ossService: ossService, tingwuService: tingwuService)
        
        await MainActor.run { self.isProcessing = true }
        
        for node in nodes {
            // Update UI status to "Running"
            await updateStatus(node.step, isFailed: false)
            
            var success = false
            var retryCount = 0
            
            while !success {
                do {
                    // 2. Run Node (Pure execution on Board)
                    try await node.run(board: &board, services: services)
                    
                    // 3. Persist State (Sync Board back to Task)
                    await persistState(from: board, channelId: 0, completedStep: node.step)
                    success = true
                    
                } catch {
                    // Handle PipelineError with type safety
                    if let pipelineError = error as? PipelineError {
                        switch pipelineError {
                        case .taskRunning:
                            retryCount += 1
                            if retryCount > PipelineConstants.maxPollingRetries {
                                await updateStatus(.failed, step: node.step, error: "Polling timeout", isFailed: true)
                                return
                            }
                            try? await Task.sleep(nanoseconds: PipelineConstants.pollingInterval)
                            continue
                        case .channelNotFound(let id):
                            await updateStatus(.failed, step: node.step, error: "Channel \(id) not found", isFailed: true)
                            return
                        case .inputMissing(let msg):
                            await updateStatus(.failed, step: node.step, error: "Input missing: \(msg)", isFailed: true)
                            return
                        case .transcodeFailed:
                            await updateStatus(.failed, step: node.step, error: "Transcoding failed", isFailed: true)
                            return
                        case .cloudError(let msg):
                            await updateStatus(.failed, step: node.step, error: "Cloud service error: \(msg)", isFailed: true)
                            return
                        case .taskFailed(let msg):
                            await updateStatus(.failed, step: node.step, error: "Task failed: \(msg)", isFailed: true)
                            return
                        }
                    }
                    
                    // Backward compatibility: handle non-PipelineError NSError
                    let nsError = error as NSError
                    if nsError.code == 202 {
                        retryCount += 1
                        if retryCount > PipelineConstants.maxPollingRetries {
                            await updateStatus(.failed, step: node.step, error: "Polling timeout", isFailed: true)
                            return
                        }
                        try? await Task.sleep(nanoseconds: PipelineConstants.pollingInterval)
                        continue
                    }
                    
                    // Unknown error
                    await updateStatus(.failed, step: node.step, error: error.localizedDescription, isFailed: true)
                    return
                }
            }
        }
        
        await MainActor.run { self.isProcessing = false }
    }
    
    // MARK: - Hydration & Persistence
    
    private func createBoard(from task: MeetingTask) -> PipelineBoard {
        let config = PipelineBoard.Config(
            ossPrefix: settings.ossPrefix,
            tingwuAppKey: settings.tingwuAppKey,
            enableSummarization: settings.enableSummary,
            enableMeetingAssistance: settings.enableKeyPoints || settings.enableActionItems,
            enableSpeakerDiarization: settings.enableRoleSplit,
            speakerCount: settings.speakerCount
        )
        
        var board = PipelineBoard(
            recordingId: task.recordingId,
            creationDate: task.createdAt,
            config: config
        )
        
        // Hydrate Mixed Channel (0)
        var mixed = ChannelData()
        
        // Fix: Resolve processed path if missing
        let path = task.localFilePath
        if !path.isEmpty {
            if path.hasSuffix("_48k.m4a") {
                mixed.processedAudioPath = path
                mixed.rawAudioPath = path // Fallback
            } else {
                mixed.rawAudioPath = path
                // Check for existing processed file
                let url = URL(fileURLWithPath: path)
                let processedFilename = "mixed_48k.m4a"
                let processedUrl = url.deletingLastPathComponent().appendingPathComponent(processedFilename)
                if FileManager.default.fileExists(atPath: processedUrl.path) {
                    mixed.processedAudioPath = processedUrl.path
                }
            }
        }
        
        mixed.rawAudioOssURL = task.originalOssUrl
        mixed.processedAudioOssURL = task.ossUrl
        mixed.tingwuTaskId = task.tingwuTaskId
        board.channels[0] = mixed
        
        return board
    }
    
    private func persistState(from board: PipelineBoard, channelId: Int, completedStep: MeetingTaskStatus) async {
        guard let channel = board.channels[channelId] else { return }
        
        await MainActor.run {
            updateChannelFields(channel: channel)
            updateChannelStatus(completedStep: completedStep)
            self.errorMessage = nil
        }
        await self.save()
    }
    
    private func updateChannelFields(channel: ChannelData) {
        if let url = channel.rawAudioOssURL { self.task.originalOssUrl = url }
        if let path = channel.processedAudioPath { self.task.localFilePath = path }
        if let url = channel.processedAudioOssURL { self.task.ossUrl = url }
        if let tid = channel.tingwuTaskId { self.task.tingwuTaskId = tid }
        if let res = channel.transcript {
            self.task.transcript = res.text
            if let sum = res.summary { self.task.summary = sum }
        }
        // Save complete poll results to database
        if let overview = channel.overviewData { self.task.overviewData = overview }
        if let transcript = channel.transcriptData { self.task.transcriptData = transcript }
        if let conversation = channel.conversationData { self.task.conversationData = conversation }
        if let raw = channel.rawData { self.task.rawData = raw }
    }
    
    private func updateChannelStatus(completedStep: MeetingTaskStatus) {
        let postStatus: MeetingTaskStatus? = {
            switch completedStep {
            case .uploadingRaw: return .uploadedRaw
            case .transcoding: return .transcoded
            case .uploading: return .uploaded
            case .created: return .created
            case .polling: return .completed
            default: return nil
            }
        }()
        
        if let status = postStatus {
            self.task.status = status
        }
    }
    
    // MARK: - Helpers
    
    private func updateStatus(_ status: MeetingTaskStatus, step: MeetingTaskStatus? = nil, error: String? = nil, isFailed: Bool = false) async {
        await MainActor.run {
            if isFailed {
                self.task.status = .failed
                self.task.failedStep = step
                self.task.lastError = error
                self.errorMessage = error
                self.isProcessing = false
            } else {
                self.task.status = status
                self.errorMessage = nil
            }
        }
        await self.save()
    }
    
    // MARK: - Legacy Support for Tests
    
    func buildTranscriptText(from transcriptionData: [String: Any]) -> String {
        return TranscriptParser.buildTranscriptText(from: transcriptionData) ?? ""
    }
    
    private func save() async {
        let snapshot = await MainActor.run { self.task }
        let providerType = String(describing: type(of: StorageManager.shared.currentProvider))
        settings.log("MeetingPipelineManager save() called. TaskID: \(snapshot.id), Status: \(snapshot.status.rawValue), Provider: \(providerType)")
        
        do {
            try await StorageManager.shared.currentProvider.saveTask(snapshot)
            settings.log("MeetingPipelineManager save() success")
        } catch {
            settings.log("MeetingPipelineManager save() failed: \(error)")
        }
        
        NotificationCenter.default.post(name: .meetingTaskDidUpdate, object: snapshot.id, userInfo: [MeetingTask.userInfoTaskKey: snapshot])
    }
}
