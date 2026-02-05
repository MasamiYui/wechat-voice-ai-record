import Foundation

class VolcengineService: TranscriptionService {
    private let settings: SettingsStore
    private let baseURL = "https://openspeech.bytedance.com/api/v3/auc/bigmodel"
    
    init(settings: SettingsStore) {
        self.settings = settings
    }
    
    // MARK: - TranscriptionService Implementation
    
    func createTask(fileUrl: String) async throws -> String {
        let url = URL(string: "\(baseURL)/submit")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        try addAuthHeaders(to: &request)
        
        // Build Request Body
        // https://www.volcengine.com/docs/6561/1354868
        let requestId = UUID().uuidString
        request.setValue(requestId, forHTTPHeaderField: "X-Api-Request-Id")
        request.setValue("-1", forHTTPHeaderField: "X-Api-Sequence")
        
        let body: [String: Any] = [
            "user": [
                "uid": "user_id_placeholder"
            ],
            "audio": [
                "url": fileUrl,
                "format": inferAudioFormat(from: fileUrl)
            ],
            "request": [
                "model_name": "bigmodel",
                "enable_itn": true,
                "enable_punc": true,
                "enable_speaker_info": settings.enableRoleSplit,
                "enable_channel_split": false,
                "show_utterances": true
            ]
        ]
        
        let jsonData = try JSONSerialization.data(withJSONObject: body)
        request.httpBody = jsonData
        
        if settings.enableVerboseLogging {
            settings.log("Volcengine CreateTask URL: \(url.absoluteString)")
            if let bodyStr = String(data: jsonData, encoding: .utf8) {
                settings.log("Volcengine CreateTask Body: \(bodyStr)")
            }
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "VolcengineService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        
        if settings.enableVerboseLogging {
            let responseText = String(data: data, encoding: .utf8) ?? "Unable to decode response body"
            settings.log("Volcengine CreateTask Response: \(responseText)")
        }
        
        if httpResponse.statusCode != 200 {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "VolcengineService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }
        
        // Header Response Check
        if let apiCode = httpResponse.value(forHTTPHeaderField: "X-Api-Status-Code"), apiCode != "20000000" {
             let apiMsg = httpResponse.value(forHTTPHeaderField: "X-Api-Message") ?? "Unknown API Error"
             throw NSError(domain: "VolcengineService", code: Int(apiCode) ?? 500, userInfo: [NSLocalizedDescriptionKey: "API Error: \(apiMsg)"])
        }
        
        // Volcengine uses the Request-Id as the Task-Id for query
        return requestId
    }
    
    func getTaskInfo(taskId: String) async throws -> (status: String, result: [String: Any]?) {
        let url = URL(string: "\(baseURL)/query")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        try addAuthHeaders(to: &request)
        request.setValue(taskId, forHTTPHeaderField: "X-Api-Request-Id")
        
        // Empty body for query
        request.httpBody = "{}".data(using: .utf8)
        
        if settings.enableVerboseLogging {
            settings.log("Volcengine GetTaskInfo URL: \(url.absoluteString) TaskID: \(taskId)")
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "VolcengineService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        
        if settings.enableVerboseLogging {
            let responseText = String(data: data, encoding: .utf8) ?? "Unable to decode response body"
            settings.log("Volcengine GetTaskInfo Response: \(responseText)")
        }
        
        if httpResponse.statusCode != 200 {
             let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "VolcengineService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }
        
        // Check X-Api-Status-Code
        // 20000000: Success (Completed)
        // 20000001: Processing
        // 20000002: Queued
        // Others: Error
        
        let apiCode = httpResponse.value(forHTTPHeaderField: "X-Api-Status-Code") ?? "0"
        
        var normalizedStatus = "FAILED"
        var resultData: [String: Any]? = nil
        
        switch apiCode {
        case "20000000":
            normalizedStatus = "SUCCESS" // Maps to existing Tingwu status for compatibility
            // Parse result body
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                resultData = json
            }
        case "20000001", "20000002":
            normalizedStatus = "RUNNING"
        default:
            normalizedStatus = "FAILED"
            let apiMsg = httpResponse.value(forHTTPHeaderField: "X-Api-Message") ?? "Unknown Error"
            resultData = ["Message": apiMsg, "Code": apiCode]
        }
        
        return (normalizedStatus, resultData)
    }
    
    func fetchJSON(url: String) async throws -> [String: Any] {
        // Standard JSON fetch
        guard let urlObj = URL(string: url) else {
            throw NSError(domain: "VolcengineService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid URL: \(url)"])
        }
        
        let (data, response) = try await URLSession.shared.data(from: urlObj)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "VolcengineService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch JSON"])
        }
        
        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return json
        }
        
        throw NSError(domain: "VolcengineService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON"])
    }
    
    // MARK: - Helpers
    
    private func addAuthHeaders(to request: inout URLRequest) throws {
        guard !settings.volcAppId.isEmpty else {
             throw NSError(domain: "VolcengineService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Missing Volcengine App ID"])
        }
        guard let accessToken = settings.getVolcAccessToken(), !accessToken.isEmpty else {
            throw NSError(domain: "VolcengineService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Missing Volcengine Access Token"])
        }
        
        request.setValue(settings.volcAppId, forHTTPHeaderField: "X-Api-App-Key")
        request.setValue(accessToken, forHTTPHeaderField: "X-Api-Access-Key")
        request.setValue(settings.volcResourceId, forHTTPHeaderField: "X-Api-Resource-Id")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }

    private func inferAudioFormat(from fileUrl: String) -> String {
        guard let url = URL(string: fileUrl) else { return "m4a" }
        let ext = url.pathExtension.lowercased()
        if ext.isEmpty { return "m4a" }
        switch ext {
        case "wav", "mp3", "ogg", "raw", "m4a":
            return ext
        default:
            return ext
        }
    }
}
