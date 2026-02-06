import Foundation

class VolcengineService: TranscriptionService {
    private let settings: SettingsStore
    private let baseURL = "https://openspeech.bytedance.com/api/v3/auc/bigmodel"
    
    init(settings: SettingsStore) {
        self.settings = settings
    }
    
    // MARK: - TranscriptionService Implementation
    
    func createTask(fileUrl: String) async throws -> String {
        let requestId = UUID().uuidString
        let request = try buildCreateTaskRequest(fileUrl: fileUrl, requestId: requestId)
        
        if settings.enableVerboseLogging {
            settings.log("Volcengine CreateTask URL: \(request.url?.absoluteString ?? "")")
            if let headers = request.allHTTPHeaderFields {
                settings.log("Volcengine CreateTask Headers: \(headers)")
            }
            if let body = request.httpBody, let bodyStr = String(data: body, encoding: .utf8) {
                settings.log("Volcengine CreateTask Body: \(bodyStr)")
            }
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.invalidResponse
        }
        
        if settings.enableVerboseLogging {
            let responseText = String(data: data, encoding: .utf8) ?? "Unable to decode response body"
            settings.log("Volcengine CreateTask Response: \(responseText)")
        }
        
        // V3 API: 200 OK means success. The ID is the requestId we sent.
        if httpResponse.statusCode == 200 {
            // Check if response body is empty or valid JSON (it should be empty {} or minimal)
            // We trust the status code 200.
            return requestId
        } else {
            // Error handling
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw TranscriptionError.taskCreationFailed("Volcengine Error \(httpResponse.statusCode): \(errorMsg)")
        }
    }
    
    func getTaskInfo(taskId: String) async throws -> (status: String, result: [String: Any]?) {
        let request = try buildQueryRequest(taskId: taskId)
        
        if settings.enableVerboseLogging {
            settings.log("Volcengine GetTaskInfo URL: \(request.url?.absoluteString ?? "") TaskID: \(taskId)")
            if let headers = request.allHTTPHeaderFields {
                settings.log("Volcengine GetTaskInfo Headers: \(headers)")
            }
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            // If 400 or other, it might be failed or invalid ID
            let errorMsg = String(data: data, encoding: .utf8) ?? "HTTP Error"
            throw TranscriptionError.taskQueryFailed("HTTP Error: \(errorMsg)")
        }
        
        if settings.enableVerboseLogging {
            let responseText = String(data: data, encoding: .utf8) ?? "Unable to decode response body"
            settings.log("Volcengine GetTaskInfo Response: \(responseText)")
        }
        
        // Parse Response
        // V3 Response: { "result": { ... }, "audio_info": { ... } }
        guard let resp = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TranscriptionError.taskQueryFailed("Invalid JSON response")
        }
        
        var normalizedStatus = "FAILED"
        var resultData: [String: Any]? = nil
        
        if let result = resp["result"] as? [String: Any] {
            // Check for completion signals
            let text = result["text"] as? String ?? ""
            let utterances = result["utterances"] as? [[String: Any]] ?? []
            
            // Also check audio_info for duration (implies audio loaded and analyzed)
            var hasDuration = false
            if let audioInfo = resp["audio_info"] as? [String: Any],
               let duration = audioInfo["duration"] as? Int, duration > 0 {
                hasDuration = true
            }
            
            if !text.isEmpty || !utterances.isEmpty || hasDuration {
                normalizedStatus = "SUCCESS"
                resultData = resp
            } else {
                // If everything is empty, it's likely still processing
                // This handles the {"audio_info":{},"result":{"text":""}} case
                normalizedStatus = "RUNNING"
                resultData = nil
            }
        } else {
            // No result field at all
             normalizedStatus = "FAILED"
             resultData = resp
        }
        
        return (normalizedStatus, resultData)
    }

    func buildCreateTaskRequest(fileUrl: String, requestId: String) throws -> URLRequest {
        let url = try endpointURL(path: "/submit")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        guard let accessToken = settings.getVolcAccessToken(), !accessToken.isEmpty else {
            throw TranscriptionError.invalidCredentials
        }
        
        // V3 Auth Headers
        request.setValue(settings.volcAppId, forHTTPHeaderField: "X-Api-App-Key")
        request.setValue(accessToken, forHTTPHeaderField: "X-Api-Access-Key")
        request.setValue(settings.volcResourceId, forHTTPHeaderField: "X-Api-Resource-Id")
        request.setValue(requestId, forHTTPHeaderField: "X-Api-Request-Id")
        request.setValue("-1", forHTTPHeaderField: "X-Api-Sequence")
        
        var reqBody: [String: Any] = [
            "model_name": "bigmodel",
            "enable_speaker_info": true,
            "enable_itn": true,
            "enable_punc": true
        ]
        
        reqBody["ssd_version"] = "200"
        
        let body: [String: Any] = [
            "user": [
                "uid": requestId
            ],
            "audio": [
                "url": fileUrl,
                "format": inferAudioFormat(from: fileUrl)
            ],
            "request": reqBody
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
    
    func buildQueryRequest(taskId: String) throws -> URLRequest {
        let url = try endpointURL(path: "/query")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        guard let accessToken = settings.getVolcAccessToken(), !accessToken.isEmpty else {
            throw TranscriptionError.invalidCredentials
        }
        
        // V3 Auth Headers
        request.setValue(settings.volcAppId, forHTTPHeaderField: "X-Api-App-Key")
        request.setValue(accessToken, forHTTPHeaderField: "X-Api-Access-Key")
        request.setValue(settings.volcResourceId, forHTTPHeaderField: "X-Api-Resource-Id")
        request.setValue(taskId, forHTTPHeaderField: "X-Api-Request-Id")
        request.setValue("-1", forHTTPHeaderField: "X-Api-Sequence")
        
        let body: [String: Any] = [:] // Empty body
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
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
