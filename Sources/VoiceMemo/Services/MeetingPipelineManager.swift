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
        
        if task.mode == .mixed {
            await runPipeline(from: .transcoding, targetSpeaker: nil)
        } else {
            await runSeparatedPipeline(from: .transcoding)
        }
    }
    
    func upload() async {
        if task.mode == .mixed {
            await runPipeline(from: .uploading, targetSpeaker: nil)
        } else {
            await runSeparatedPipeline(from: .uploading)
        }
    }
    
    func uploadOriginal() async {
        if task.mode == .mixed {
            await runPipeline(from: .uploadingRaw, targetSpeaker: nil)
        } else {
            await runSeparatedPipeline(from: .uploadingRaw)
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
                let startStep: MeetingTaskStatus
                if spk == 1 {
                    startStep = task.speaker1FailedStep ?? .recorded
                } else {
                    startStep = task.speaker2FailedStep ?? .recorded
                }
                await runSingleTrack(from: startStep, speaker: spk)
                await tryAlign()
            } else {
                await runSeparatedPipeline()
            }
        }
    }
    
    func restartFromBeginning() async {
        settings.log("Restart from beginning")
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
        await self.save()
        
        await start()
    }
    
    // MARK: - Pipeline Orchestration
    
    private func runMixedPipeline() async {
        await runPipeline(from: .recorded, targetSpeaker: nil)
    }
    
    private func runSeparatedPipeline(from step: MeetingTaskStatus = .recorded) async {
        async let t1: Void = runSingleTrack(from: step == .transcoding ? (task.speaker1Status == .completed ? .completed : step) : step, speaker: 1)
        async let t2: Void = runSingleTrack(from: step == .transcoding ? (task.speaker2Status == .completed ? .completed : step) : step, speaker: 2)
        
        _ = await (t1, t2)
        await tryAlign()
    }
    
    private func runSingleTrack(from startStep: MeetingTaskStatus, speaker: Int) async {
        if (speaker == 1 && task.speaker1Status == .completed && startStep != .polling) ||
           (speaker == 2 && task.speaker2Status == .completed && startStep != .polling) {
            return
        }
        
        let nodes = buildChain(from: startStep, channelId: speaker)
        await executeChain(nodes: nodes, speaker: speaker)
    }
    
    private func runPipeline(from startStep: MeetingTaskStatus, targetSpeaker: Int?) async {
        let nodes = buildChain(from: startStep, channelId: targetSpeaker ?? 0)
        await executeChain(nodes: nodes, speaker: targetSpeaker)
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
    
    private func executeChain(nodes: [PipelineNode], speaker: Int?) async {
        // 1. Hydrate Board from Task
        let taskSnapshot = await MainActor.run { self.task }
        var board = createBoard(from: taskSnapshot)
        let services = ServiceProvider(ossService: ossService, tingwuService: tingwuService)
        let channelId = speaker ?? 0
        
        await MainActor.run { self.isProcessing = true }
        
        for node in nodes {
            // Update UI status to "Running"
            await updateStatus(node.step, speaker: speaker, isFailed: false)
            
            var success = false
            var retryCount = 0
            
            while !success {
                do {
                    // 2. Run Node (Pure execution on Board)
                    try await node.run(board: &board, services: services)
                    
                    // 3. Persist State (Sync Board back to Task)
                    await persistState(from: board, channelId: channelId, completedStep: node.step)
                    success = true
                    
                } catch {
                    // Handle PipelineError with type safety
                    if let pipelineError = error as? PipelineError {
                        switch pipelineError {
                        case .taskRunning:
                            retryCount += 1
                            if retryCount > PipelineConstants.maxPollingRetries {
                                await updateStatus(.failed, speaker: speaker, step: node.step, error: "Polling timeout", isFailed: true)
                                return
                            }
                            try? await Task.sleep(nanoseconds: PipelineConstants.pollingInterval)
                            continue
                        case .channelNotFound(let id):
                            await updateStatus(.failed, speaker: speaker, step: node.step, error: "Channel \(id) not found", isFailed: true)
                            return
                        case .inputMissing(let msg):
                            await updateStatus(.failed, speaker: speaker, step: node.step, error: "Input missing: \(msg)", isFailed: true)
                            return
                        case .transcodeFailed:
                            await updateStatus(.failed, speaker: speaker, step: node.step, error: "Transcoding failed", isFailed: true)
                            return
                        case .cloudError(let msg):
                            await updateStatus(.failed, speaker: speaker, step: node.step, error: "Cloud service error: \(msg)", isFailed: true)
                            return
                        case .taskFailed(let msg):
                            await updateStatus(.failed, speaker: speaker, step: node.step, error: "Task failed: \(msg)", isFailed: true)
                            return
                        }
                    }
                    
                    // Backward compatibility: handle non-PipelineError NSError
                    let nsError = error as NSError
                    if nsError.code == 202 {
                        retryCount += 1
                        if retryCount > PipelineConstants.maxPollingRetries {
                            await updateStatus(.failed, speaker: speaker, step: node.step, error: "Polling timeout", isFailed: true)
                            return
                        }
                        try? await Task.sleep(nanoseconds: PipelineConstants.pollingInterval)
                        continue
                    }
                    
                    // Unknown error
                    await updateStatus(.failed, speaker: speaker, step: node.step, error: error.localizedDescription, isFailed: true)
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
            mode: task.mode,
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
        
        // Hydrate Speaker Channels (Separated Mode)
        // Note: In separated mode, Speaker 1 reuses the main MeetingTask fields
        // (originalOssUrl, ossUrl, tingwuTaskId) for compatibility with mixed mode.
        // Speaker 2 uses dedicated speaker2* fields.
        if task.mode == .separated {
            // Speaker 1 (Channel 1) - Reuses main MeetingTask fields
            var spk1 = ChannelData()
            
            if let path = task.speaker1AudioPath {
                if path.hasSuffix("_48k.m4a") {
                    spk1.processedAudioPath = path
                    spk1.rawAudioPath = path
                } else {
                    spk1.rawAudioPath = path
                    let url = URL(fileURLWithPath: path)
                    let processedUrl = url.deletingLastPathComponent().appendingPathComponent("speaker1_48k.m4a")
                    if FileManager.default.fileExists(atPath: processedUrl.path) {
                        spk1.processedAudioPath = processedUrl.path
                    }
                }
            }
            
            spk1.rawAudioOssURL = task.originalOssUrl
            spk1.processedAudioOssURL = task.ossUrl
            spk1.tingwuTaskId = task.tingwuTaskId
            spk1.failedStep = task.speaker1FailedStep
            if let transcriptText = task.speaker1Transcript {
                spk1.transcript = TingwuResult(text: transcriptText)
            }
            if task.speaker1Status == .failed {
                spk1.lastError = task.lastError
            }
            board.channels[1] = spk1
            
            // Speaker 2 (Channel 2) - Uses dedicated speaker2* fields
            var spk2 = ChannelData()
            
            if let path = task.speaker2AudioPath {
                if path.hasSuffix("_48k.m4a") {
                    spk2.processedAudioPath = path
                    spk2.rawAudioPath = path
                } else {
                    spk2.rawAudioPath = path
                    let url = URL(fileURLWithPath: path)
                    let processedUrl = url.deletingLastPathComponent().appendingPathComponent("speaker2_48k.m4a")
                    if FileManager.default.fileExists(atPath: processedUrl.path) {
                        spk2.processedAudioPath = processedUrl.path
                    }
                }
            }
            
            spk2.rawAudioOssURL = task.speaker2OriginalOssUrl
            spk2.processedAudioOssURL = task.speaker2OssUrl
            spk2.tingwuTaskId = task.speaker2TingwuTaskId
            spk2.failedStep = task.speaker2FailedStep
            if let transcriptText = task.speaker2Transcript {
                spk2.transcript = TingwuResult(text: transcriptText)
            }
            if task.speaker2Status == .failed {
                spk2.lastError = task.lastError
            }
            board.channels[2] = spk2
        }
        
        return board
    }
    
    private func persistState(from board: PipelineBoard, channelId: Int, completedStep: MeetingTaskStatus) async {
        guard let channel = board.channels[channelId] else { return }
        
        await MainActor.run {
            updateChannelFields(channelId: channelId, channel: channel)
            updateChannelStatus(channelId: channelId, completedStep: completedStep)
            self.errorMessage = nil
        }
        await self.save()
    }
    
    private func updateChannelFields(channelId: Int, channel: ChannelData) {
        switch channelId {
        case 0:
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
        case 1:
            if let url = channel.rawAudioOssURL { self.task.originalOssUrl = url }
            if let path = channel.processedAudioPath { self.task.speaker1AudioPath = path }
            if let url = channel.processedAudioOssURL { self.task.ossUrl = url }
            if let tid = channel.tingwuTaskId { self.task.tingwuTaskId = tid }
            if let res = channel.transcript { self.task.speaker1Transcript = res.text }
        case 2:
            if let url = channel.rawAudioOssURL { self.task.speaker2OriginalOssUrl = url }
            if let path = channel.processedAudioPath { self.task.speaker2AudioPath = path }
            if let url = channel.processedAudioOssURL { self.task.speaker2OssUrl = url }
            if let tid = channel.tingwuTaskId { self.task.speaker2TingwuTaskId = tid }
            if let res = channel.transcript { self.task.speaker2Transcript = res.text }
        default:
            break
        }
    }
    
    private func updateChannelStatus(channelId: Int, completedStep: MeetingTaskStatus) {
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
        
        guard let status = postStatus else { return }
        
        switch channelId {
        case 0:
            self.task.status = status
        case 1:
            self.task.speaker1Status = status
            syncGlobalStatus()
        case 2:
            self.task.speaker2Status = status
            syncGlobalStatus()
        default:
            break
        }
    }
    
    // MARK: - Helpers
    
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
                    // Sync failure status
                    syncGlobalStatus()
                } else {
                    self.task.status = .failed
                    self.task.failedStep = step
                }
                self.task.lastError = error
                self.errorMessage = error
                self.isProcessing = false
            } else {
                if let spk = speaker {
                    if spk == 1 { self.task.speaker1Status = status }
                    else { self.task.speaker2Status = status }
                    syncGlobalStatus()
                } else {
                    self.task.status = status
                }
                self.errorMessage = nil
            }
        }
        await self.save()
    }
    
    /// Synchronizes global status based on speaker statuses in Separated Mode.
    /// Uses the "earliest" active state logic (e.g. if one is uploading and one is transcoding, show uploading).
    private func syncGlobalStatus() {
        guard task.mode == .separated else { return }
        
        let s1 = task.speaker1Status ?? .recorded
        let s2 = task.speaker2Status ?? .recorded
        
        // 1. Failure takes precedence
        if s1 == .failed || s2 == .failed {
            if task.status != .failed { task.status = .failed }
            return
        }
        
        // 2. Completion requires both
        if s1 == .completed && s2 == .completed {
            if task.status != .completed { task.status = .completed }
            return
        }
        
        // 3. Active processing state (show the earliest active step)
        let steps: [MeetingTaskStatus] = [
            .uploadingRaw, .uploadedRaw,
            .transcoding, .transcoded,
            .uploading, .uploaded,
            .created, .polling
        ]
        
        func rank(_ s: MeetingTaskStatus) -> Int {
            return steps.firstIndex(of: s) ?? -1
        }
        
        let r1 = rank(s1)
        let r2 = rank(s2)
        
        var target: MeetingTaskStatus = .recorded
        
        if r1 >= 0 || r2 >= 0 {
            if r1 >= 0 && r2 >= 0 {
                target = steps[min(r1, r2)]
            } else if r1 >= 0 {
                target = s1
            } else if r2 >= 0 {
                target = s2
            }
        }
        
        if task.status != target {
            task.status = target
        }
    }
    
    private func tryAlign() async {
        let shouldSave = await MainActor.run { () -> Bool in
            let t1 = self.task.speaker1Transcript ?? ""
            let t2 = self.task.speaker2Transcript ?? ""
            
            if !t1.isEmpty || !t2.isEmpty {
                var merged = ""
                if !t1.isEmpty { merged += "### Speaker 1 (Local)\n\(t1)\n\n" }
                if !t2.isEmpty { merged += "### Speaker 2 (Remote)\n\(t2)\n" }
                self.task.transcript = merged
                syncGlobalStatus()
                return true
            }
            return false
        }
        if shouldSave {
            await self.save()
        }
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
