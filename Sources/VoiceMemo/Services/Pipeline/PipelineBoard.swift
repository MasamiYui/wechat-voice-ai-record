import Foundation

/// 流水线执行黑板 (Execution Board)
/// 这是一个纯内存、强类型的数据结构，用于在流水线节点间传递状态和产物。
/// 它解耦了 Node 与 MeetingTask (DB Model)，使 Node 具备原子性和可测试性。
struct PipelineBoard {
    // --- 基础信息 ---
    let recordingId: String
    let creationDate: Date
    
    // --- 配置 (Configuration) ---
    struct Config {
        let ossPrefix: String
        let tingwuAppKey: String
        let enableSummarization: Bool
        let enableMeetingAssistance: Bool
        let enableSpeakerDiarization: Bool
        let speakerCount: Int
    }
    let config: Config
    
    // --- 多路数据 (Channels) ---
    // 0: Mixed Mode (默认)
    var channels: [Int: ChannelData] = [:]
    
    // --- 辅助方法 ---
    mutating func updateChannel(_ id: Int, _ transform: (inout ChannelData) -> Void) {
        var channel = channels[id] ?? ChannelData()
        transform(&channel)
        channels[id] = channel
    }
    
    func formattedDatePath() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter.string(from: creationDate)
    }
}

/// 单路流水线数据
struct ChannelData {
    // 1. 原始音频 (Raw)
    var rawAudioPath: String?         // 本地路径
    var rawAudioOssURL: String?       // OSS URL
    
    // 2. 转码后音频 (Mixed/Processed)
    var processedAudioPath: String?   // 本地路径 (如 16k/48k m4a)
    var processedAudioOssURL: String? // OSS URL (用于提交给听悟)
    
    // 3. 听悟任务
    var tingwuTaskId: String?
    var tingwuTaskStatus: String?     // e.g. "RUNNING", "COMPLETE"
    
    // 4. 最终产物
    var transcript: TingwuResult?     // 解析后的结构化结果
    
    // 5. 完整轮询结果 (用于数据库存储)
    var overviewData: String?     // 概览数据 (JSON String)
    var transcriptData: String?   // 转录数据 (JSON String)
    var conversationData: String? // 对话数据 (JSON String)
    var rawData: String?          // 原始数据 (JSON String)
    
    // 6. 错误追踪 (用于单路重试)
    var lastError: String?
    var failedStep: MeetingTaskStatus?
}

/// 统一的服务提供者 (用于注入无状态服务)
struct ServiceProvider {
    let ossService: OSSService
    let transcriptionService: TranscriptionService
    
    // Legacy support for older code referencing tingwuService directly if needed
    // but ideally we should migrate all usages to transcriptionService
    var tingwuService: TranscriptionService { return transcriptionService }
}

/// 听悟结果结构
struct TingwuResult {
    var text: String?
    var summary: String?
}

/// 流水线错误定义
enum PipelineError: LocalizedError {
    case channelNotFound(Int)
    case inputMissing(String)
    case transcodeFailed
    case taskRunning
    case taskFailed(String)
    case cloudError(String)
    
    var errorDescription: String? {
        switch self {
        case .channelNotFound(let id): return "Channel \(id) not found"
        case .inputMissing(let msg): return "Input missing: \(msg)"
        case .transcodeFailed: return "Transcoding failed"
        case .taskRunning: return "Task is still running"
        case .taskFailed(let msg): return "Task failed: \(msg)"
        case .cloudError(let msg): return "Cloud service error: \(msg)"
        }
    }
}
