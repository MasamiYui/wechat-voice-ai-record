import Foundation

class VolcengineService: TranscriptionService {
    private let settings: SettingsStore
    private let baseURL = "https://openspeech.bytedance.com/api/v1/auc"
    
    init(settings: SettingsStore) {
        self.settings = settings
    }
    
    // MARK: - TranscriptionService Implementation
    
    func createTask(fileUrl: String) async throws -> String {
        let url = try endpointURL(path: "/submit")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        guard let accessToken = settings.getVolcAccessToken(), !accessToken.isEmpty else {
            throw TranscriptionError.invalidCredentials
        }
        
        // Volcengine V1 API Body
        let body: [String: Any] = [
            "app": [
                "appid": settings.volcAppId,
                "token": accessToken,
                "cluster": settings.volcResourceId // Treating ResourceID as Cluster ID
            ],
            "user": [
                "uid": "user_id_placeholder"
            ],
            "audio": [
                "url": fileUrl,
                "format": inferAudioFormat(from: fileUrl)
            ],
            "additions": [
                "with_speaker_info": settings.enableRoleSplit ? "True" : "False",
                "use_itn": "True",
                "use_punc": "True"
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
        
        guard let _ = response as? HTTPURLResponse else {
            throw TranscriptionError.invalidResponse
        }
        
        if settings.enableVerboseLogging {
            let responseText = String(data: data, encoding: .utf8) ?? "Unable to decode response body"
            settings.log("Volcengine CreateTask Response: \(responseText)")
        }
        
        // Parse Response
        // { "resp": { "code": 1000, "message": "Success", "id": "..." } }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let resp = json["resp"] as? [String: Any] else {
            throw TranscriptionError.taskCreationFailed("Invalid JSON response")
        }
        
        // Code 1000 is success for submission
        if let code = resp["code"] as? Int, code != 1000 {
            // Some error handling for string codes if API returns strings
            let msg = resp["message"] as? String ?? "Unknown error"
            throw TranscriptionError.taskCreationFailed("Volcengine Error \(code): \(msg)")
        }
        
        // Also handle string codes just in case
        if let codeStr = resp["code"] as? String, codeStr != "1000" {
            let msg = resp["message"] as? String ?? "Unknown error"
            throw TranscriptionError.taskCreationFailed("Volcengine Error \(codeStr): \(msg)")
        }
        
        guard let taskId = resp["id"] as? String else {
            throw TranscriptionError.taskCreationFailed("Task ID not found in response")
        }
        
        return taskId
    }
    
    func getTaskInfo(taskId: String) async throws -> (status: String, result: [String: Any]?) {
        let url = try endpointURL(path: "/query")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        guard let accessToken = settings.getVolcAccessToken(), !accessToken.isEmpty else {
            throw TranscriptionError.invalidCredentials
        }
        
        // Query Body
        let body: [String: Any] = [
            "appid": settings.volcAppId,
            "token": accessToken,
            "cluster": settings.volcResourceId,
            "id": taskId
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        if settings.enableVerboseLogging {
            settings.log("Volcengine GetTaskInfo URL: \(url.absoluteString) TaskID: \(taskId)")
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw TranscriptionError.taskQueryFailed("HTTP Error")
        }
        
        if settings.enableVerboseLogging {
            let responseText = String(data: data, encoding: .utf8) ?? "Unable to decode response body"
            settings.log("Volcengine GetTaskInfo Response: \(responseText)")
        }
        
        // Parse Response
        // { "resp": { "code": 1000, "text": "...", "id": "..." } }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let resp = json["resp"] as? [String: Any] else {
            throw TranscriptionError.taskQueryFailed("Invalid JSON response")
        }
        
        var normalizedStatus = "FAILED"
        var resultData: [String: Any]? = nil
        
        // Handle code as Int or String
        var code = 0
        if let c = resp["code"] as? Int {
            code = c
        } else if let cStr = resp["code"] as? String, let c = Int(cStr) {
            code = c
        }
        
        // Status mapping
        if code == 1000 {
            normalizedStatus = "SUCCESS"
            resultData = resp
        } else if code > 1000 && code < 2000 {
            normalizedStatus = "RUNNING"
        } else {
            normalizedStatus = "FAILED"
            let msg = resp["message"] as? String ?? "Unknown"
            resultData = ["Message": msg, "Code": "\(code)"]
        }
        
        return (normalizedStatus, resultData)
    }
    
    func fetchJSON(url: String) async throws -> [String: Any] {
        guard let urlObj = URL(string: url) else {
            throw TranscriptionError.invalidURL(url)
        }
        
        let (data, response) = try await URLSession.shared.data(from: urlObj)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw TranscriptionError.serviceUnavailable
        }
        
        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return json
        }
        
        throw TranscriptionError.parseError("Invalid JSON")
    }
    
    // MARK: - Helpers
    
    private func endpointURL(path: String) throws -> URL {
        if let url = URL(string: "\(baseURL)\(path)") {
            return url
        }
        throw TranscriptionError.invalidURL(baseURL)
    }

    private func inferAudioFormat(from fileUrl: String) -> String {
        guard let url = URL(string: fileUrl) else { return "m4a" }
        let ext = url.pathExtension.lowercased()
        if ext.isEmpty { return "m4a" }
        switch ext {
        case "wav", "ogg", "mp3", "mp4":
            return ext
        default:
            return "m4a" // Default fall back
        }
    }
}
