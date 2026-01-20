import Foundation

enum MeetingTaskStatus: String, Codable, CaseIterable, Hashable {
    case recorded      // 录音完成
    case transcoding   // 转码中
    case transcoded    // 转码完成
    case uploading     // 上传中
    case uploaded      // 上传完成
    case created       // 任务创建中
    case polling       // 轮询中
    case completed     // 完成
    case failed        // 失败
}

struct MeetingTask: Identifiable, Codable, Hashable, Equatable {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var recordingId: String
    
    // File Paths
    var localFilePath: String
    var ossUrl: String?
    
    // Tingwu Info
    var tingwuTaskId: String?
    var status: MeetingTaskStatus = .recorded
    var title: String
    
    // Results
    var rawResponse: String?
    var transcript: String?
    var summary: String?
    var keyPoints: String?
    var actionItems: String?
    
    // Error
    var lastError: String?
    
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
