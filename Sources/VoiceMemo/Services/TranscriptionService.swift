import Foundation

/// Protocol defining the interface for transcription services (ASR).
/// This allows switching between providers like Aliyun Tingwu and Volcengine.
protocol TranscriptionService {
    /// Submit an audio file for transcription.
    /// - Parameter fileUrl: Publicly accessible URL of the audio file (e.g., OSS URL).
    /// - Returns: Task ID string used to query status.
    func createTask(fileUrl: String) async throws -> String
    
    /// Query the status and result of a transcription task.
    /// - Parameter taskId: The task ID returned by createTask.
    /// - Returns: A tuple containing the standardized status string and the raw result dictionary.
    ///            Status should be normalized to: "RUNNING", "SUCCESS", "FAILED" (or compatible).
    func getTaskInfo(taskId: String) async throws -> (status: String, result: [String: Any]?)
    
    /// Helper to fetch JSON data from a URL (often used to retrieve results stored in OSS).
    func fetchJSON(url: String) async throws -> [String: Any]
}
