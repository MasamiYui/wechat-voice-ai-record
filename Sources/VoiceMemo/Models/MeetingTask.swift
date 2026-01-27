import Foundation

enum MeetingTaskStatus: String, Codable, CaseIterable, Hashable {
    case recorded      // 录音完成
    case uploadingOriginal // 上传原始文件中
    case uploadedOriginal  // 原始文件上传完成
    case transcoding   // 转码中
    case transcoded    // 转码完成
    case uploading     // 上传中
    case uploaded      // 上传完成
    case created       // 任务创建中
    case polling       // 轮询中
    case completed     // 完成
    case failed        // 失败
}

enum MeetingMode: String, Codable, Hashable {
    case mixed        // 混合模式 (默认)
    case separated    // 分离模式 (双人分轨)
}

struct MeetingTask: Identifiable, Codable, Hashable, Equatable {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var recordingId: String
    
    // Configuration
    var mode: MeetingMode = .mixed
    
    // File Paths
    var localFilePath: String // Mixed audio path (legacy) or Speaker 1 (Local) in separated mode? -> Let's keep this as "primary display path" or "mixed path"
    // In separated mode, localFilePath might store the mixed preview if we make one, or just be ignored?
    // Plan says: "mixed path (legacy)" and add speaker1/2 paths.
    // To minimize breakage, let's keep localFilePath as the "main" file. In separated mode, maybe we still generate a mix for preview? 
    // Wait, the plan says "skip merge". So localFilePath might be empty or point to speaker1?
    // Let's allow localFilePath to be Speaker 1 (Local) and add speaker2Path?
    // Actually, explicit is better.
    var speaker1AudioPath: String? // Local Mic
    var speaker2AudioPath: String? // Remote System
    
    var originalOssUrl: String? // Mixed Original OSS URL or Speaker 1 Original OSS URL
    var speaker2OriginalOssUrl: String? // Speaker 2 Original OSS URL
    
    var ossUrl: String? // Mixed OSS URL or Speaker 1 OSS URL?
    var speaker2OssUrl: String? // Speaker 2 OSS URL
    
    // Tingwu Info
    var tingwuTaskId: String? // Mixed or Speaker 1 Task ID
    var speaker2TingwuTaskId: String? // Speaker 2 Task ID
    
    var taskKey: String?
    var apiStatus: String?
    var statusText: String?
    var bizDuration: Int?
    var status: MeetingTaskStatus = .recorded
    var title: String
    
    // Results
    var rawResponse: String?
    var transcript: String? // Mixed transcript or merged display transcript
    var speaker1Transcript: String?
    var speaker2Transcript: String?
    var alignedConversation: String? // JSON String
    
    var summary: String?
    var keyPoints: String?
    var actionItems: String?
    var outputMp3Path: String?
    
    // Status for Separated Mode
    var speaker1Status: MeetingTaskStatus?
    var speaker2Status: MeetingTaskStatus?
    var speaker1FailedStep: MeetingTaskStatus?
    var speaker2FailedStep: MeetingTaskStatus?
    
    // Error & Retry
    var lastError: String?
    var lastSuccessfulStatus: MeetingTaskStatus?
    var failedStep: MeetingTaskStatus?
    var retryCount: Int = 0
    
    init(recordingId: String, localFilePath: String, title: String) {
        self.recordingId = recordingId
        self.localFilePath = localFilePath
        self.title = title
    }
    
    static func == (lhs: MeetingTask, rhs: MeetingTask) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
