import Foundation
import CryptoKit

class TingwuService {
    private let settings: SettingsStore
    
    init(settings: SettingsStore) {
        self.settings = settings
    }
    
    // MARK: - API Methods
    
    func createTask(fileUrl: String) async throws -> String {
        var request = try buildCreateTaskRequest(fileUrl: fileUrl)
        
        let bodyData = request.httpBody
        try await signRequest(&request, body: bodyData)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "TingwuService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        
        if httpResponse.statusCode != 200 {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "TingwuService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }
        
        // Parse Response
        // Structure: { "Data": { "TaskId": "..." }, "Code": "0", ... }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let dataObj = json?["Data"] as? [String: Any], let taskId = dataObj["TaskId"] as? String {
            return taskId
        }
        
        throw NSError(domain: "TingwuService", code: 0, userInfo: [NSLocalizedDescriptionKey: "TaskId not found in response"])
    }

    internal func buildCreateTaskRequest(fileUrl: String) throws -> URLRequest {
        guard let appKey = settings.tingwuAppKey.isEmpty ? nil : settings.tingwuAppKey else {
            throw NSError(domain: "TingwuService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Missing AppKey"])
        }
        
        var parameters: [String: Any] = [
            "AppKey": appKey,
            "Input": [
                "FileUrl": fileUrl,
                "SourceLanguage": settings.language
            ]
        ]
        
        var apiParams: [String: Any] = [
            "AutoChaptersEnabled": true,
            "Transcoding": [
                "TargetAudioFormat": "m4a",
                "SpectrumEnabled": false
            ]
        ]
        
        // Summarization
        if settings.enableSummary {
            apiParams["SummarizationEnabled"] = true
            apiParams["Summarization"] = [
                "Types": ["Paragraph", "Conversational", "QuestionsAnswering", "MindMap"]
            ]
        }
        
        // Meeting Assistance (KeyPoints, ActionItems)
        if settings.enableKeyPoints || settings.enableActionItems {
            apiParams["MeetingAssistanceEnabled"] = true
            var assistanceTypes: [String] = []
            if settings.enableKeyPoints {
                assistanceTypes.append("KeyInformation")
            }
            if settings.enableActionItems {
                assistanceTypes.append("Actions")
            }
            apiParams["MeetingAssistance"] = [
                "Types": assistanceTypes
            ]
        }
        
        // Diarization (Role Split)
        if settings.enableRoleSplit {
            apiParams["Transcription"] = [
                "DiarizationEnabled": true,
                "Diarization": [
                    "SpeakerCount": 0 // 0 means auto-detect
                ]
            ]
        }
        
        parameters["Parameters"] = apiParams
        
        let url = URL(string: "https://tingwu.cn-beijing.aliyuncs.com/openapi/tingwu/v2/tasks")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("CreateTask", forHTTPHeaderField: "x-acs-action")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "type", value: "offline")]
        request.url = components.url
        
        let bodyData = try JSONSerialization.data(withJSONObject: parameters, options: [.sortedKeys]) // Sorted keys for stable hash
        request.httpBody = bodyData
        
        return request
    }
    
    func getTaskInfo(taskId: String) async throws -> (status: String, result: [String: Any]?) {
        // GET /openapi/tingwu/v2/tasks/{taskId}
        let url = URL(string: "https://tingwu.cn-beijing.aliyuncs.com/openapi/tingwu/v2/tasks/\(taskId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("GetTaskInfo", forHTTPHeaderField: "x-acs-action")
        
        if settings.enableVerboseLogging {
            settings.log("Tingwu GetTaskInfo URL: \(request.url?.absoluteString ?? "")")
        }
        
        try await signRequest(&request, body: nil)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "TingwuService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        
        if httpResponse.statusCode != 200 {
             let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "TingwuService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }
        
        if settings.enableVerboseLogging {
            let responseText = String(data: data, encoding: .utf8) ?? "Unable to decode response body"
            settings.log("Tingwu GetTaskInfo response: \(responseText)")
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        guard let dataObj = json?["Data"] as? [String: Any],
              let status = dataObj["TaskStatus"] as? String else {
             throw NSError(domain: "TingwuService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid status response"])
        }
        
        // Return full data object as result if completed
        return (status, dataObj)
    }
    
    func fetchJSON(url: String) async throws -> [String: Any] {
        guard let urlObj = URL(string: url) else {
            throw NSError(domain: "TingwuService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid URL: \(url)"])
        }
        
        if settings.enableVerboseLogging {
            settings.log("Tingwu fetchJSON URL: \(urlObj.absoluteString)")
        }
        
        let (data, response) = try await URLSession.shared.data(from: urlObj)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "TingwuService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch JSON from \(url)"])
        }
        
        if settings.enableVerboseLogging {
            let responseText = String(data: data, encoding: .utf8) ?? "Unable to decode response body"
            settings.log("Tingwu fetchJSON response: \(responseText)")
        }
        
        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return json
        }
        
        throw NSError(domain: "TingwuService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON response from \(url)"])
    }
    
    // MARK: - V3 Signature Implementation
    
    private func signRequest(_ request: inout URLRequest, body: Data?) async throws {
        guard let akId = settings.getAccessKeyId(),
              let akSecret = settings.getAccessKeySecret() else {
            throw NSError(domain: "TingwuService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Missing AccessKey"])
        }
        
        // 1. Headers
        let date = Date()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        let timestamp = formatter.string(from: date)
        
        let nonce = UUID().uuidString
        
        request.setValue(timestamp, forHTTPHeaderField: "x-acs-date")
        request.setValue(nonce, forHTTPHeaderField: "x-acs-signature-nonce")
        request.setValue("ACS3-HMAC-SHA256", forHTTPHeaderField: "x-acs-signature-method")
        request.setValue("2023-09-30", forHTTPHeaderField: "x-acs-version")
        
        // Content-SHA256
        let contentSha256: String
        if let body = body {
            contentSha256 = SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined()
        } else {
            contentSha256 = SHA256.hash(data: Data()).map { String(format: "%02x", $0) }.joined()
        }
        request.setValue(contentSha256, forHTTPHeaderField: "x-acs-content-sha256")
        
        // 2. Canonical Request
        let method = request.httpMethod ?? "GET"
        let uri = request.url?.path ?? "/"
        let query = canonicalQuery(from: request.url)
        
        // Canonical Headers
        // Lowercase keys, sorted, trim value.
        // We signed: host, x-acs-content-sha256, x-acs-date, x-acs-signature-nonce, x-acs-signature-method, x-acs-version
        // And maybe Content-Type if present.
        
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let host = request.url?.host {
            request.setValue(host, forHTTPHeaderField: "host")
        }
        
        var headersToSign: [String: String] = [
            "content-type": request.value(forHTTPHeaderField: "Content-Type") ?? "application/json",
            "host": request.value(forHTTPHeaderField: "host") ?? (request.url?.host ?? ""),
            "x-acs-content-sha256": contentSha256,
            "x-acs-date": timestamp,
            "x-acs-signature-method": "ACS3-HMAC-SHA256",
            "x-acs-signature-nonce": nonce,
            "x-acs-version": "2023-09-30"
        ]
        
        if let action = request.value(forHTTPHeaderField: "x-acs-action"), !action.isEmpty {
            headersToSign["x-acs-action"] = action
        }
        
        let signedHeaders = headersToSign.keys.sorted().joined(separator: ";")
        let canonicalRequest = buildCanonicalRequest(
            method: method,
            uri: uri,
            query: query,
            headers: headersToSign,
            contentSha256: contentSha256
        )
        
        let canonicalRequestHash = SHA256.hash(data: canonicalRequest.data(using: .utf8)!).map { String(format: "%02x", $0) }.joined()
        if settings.enableVerboseLogging {
            settings.log("Tingwu canonical request: \(canonicalRequest)")
            settings.log("Tingwu canonical request hash: \(canonicalRequestHash)")
        }
        
        // 3. String To Sign
        let stringToSign = "ACS3-HMAC-SHA256\n\(canonicalRequestHash)"
        
        // 4. Signature
        let signature = hmac(key: akSecret, string: stringToSign)
        if settings.enableVerboseLogging {
            settings.log("Tingwu string to sign: \(stringToSign)")
            settings.log("Tingwu signature: \(signature)")
        }
        
        // 5. Authorization Header
        let auth = "ACS3-HMAC-SHA256 Credential=\(akId),SignedHeaders=\(signedHeaders),Signature=\(signature)"
        request.setValue(auth, forHTTPHeaderField: "Authorization")
    }

    func buildCanonicalRequest(method: String, uri: String, query: String, headers: [String: String], contentSha256: String) -> String {
        let sortedHeaderKeys = headers.keys.sorted()
        let canonicalHeaders = sortedHeaderKeys.map { "\($0):\(headers[$0]!)" }.joined(separator: "\n")
        let signedHeaders = sortedHeaderKeys.joined(separator: ";")
        return "\(method)\n\(uri)\n\(query)\n\(canonicalHeaders)\n\n\(signedHeaders)\n\(contentSha256)"
    }
    
    private func canonicalQuery(from url: URL?) -> String {
        guard let url else { return "" }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return "" }
        guard let items = components.queryItems, !items.isEmpty else { return "" }
        let encodedItems = items.map { item -> (String, String) in
            let name = percentEncode(item.name)
            let value = percentEncode(item.value ?? "")
            return (name, value)
        }
        let sortedItems = encodedItems.sorted {
            if $0.0 == $1.0 {
                return $0.1 < $1.1
            }
            return $0.0 < $1.0
        }
        return sortedItems.map { "\($0.0)=\($0.1)" }.joined(separator: "&")
    }
    
    private func percentEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
    
    private func hmac(key: String, string: String) -> String {
        let keyData = key.data(using: .utf8)!
        let data = string.data(using: .utf8)!
        let mac = HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: keyData))
        return mac.map { String(format: "%02x", $0) }.joined()
    }
}
