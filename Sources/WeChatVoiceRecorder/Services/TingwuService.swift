import Foundation
import CryptoKit

class TingwuService {
    private let settings: SettingsStore
    
    init(settings: SettingsStore) {
        self.settings = settings
    }
    
    // MARK: - API Methods
    
    func createTask(fileUrl: String) async throws -> String {
        guard let appKey = settings.tingwuAppKey.isEmpty ? nil : settings.tingwuAppKey else {
            throw NSError(domain: "TingwuService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Missing AppKey"])
        }
        
        let parameters: [String: Any] = [
            "AppKey": appKey,
            "Input": [
                "FileUrl": fileUrl,
                "SourceLanguage": settings.language
            ],
            "Parameters": [
                "AutoChaptersEnabled": true,
                "SummarizationEnabled": settings.enableSummary,
                "Transcoding": [
                    "TargetAudioFormat": "m4a", // Optional, but good practice
                    "SpectrumEnabled": false
                ]
                // Add more params like MeetingAssistanceEnabled if available
            ]
        ]
        
        let url = URL(string: "https://tingwu.cn-beijing.aliyuncs.com/openapi/tingwu/v2/tasks")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.addValue("offline", forHTTPHeaderField: "type") // Query param usually, but let's check.
        // Wait, search result showed query param type=realtime.
        // Let's put type=offline in query
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "type", value: "offline")]
        request.url = components.url
        
        let bodyData = try JSONSerialization.data(withJSONObject: parameters, options: [.sortedKeys]) // Sorted keys for stable hash
        request.httpBody = bodyData
        
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
    
    func getTaskInfo(taskId: String) async throws -> (status: String, result: [String: Any]?) {
        // GET /openapi/tingwu/v2/tasks/{taskId}
        let url = URL(string: "https://tingwu.cn-beijing.aliyuncs.com/openapi/tingwu/v2/tasks/\(taskId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        try await signRequest(&request, body: nil)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "TingwuService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        
        if httpResponse.statusCode != 200 {
             let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "TingwuService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        guard let dataObj = json?["Data"] as? [String: Any],
              let status = dataObj["TaskStatus"] as? String else {
             throw NSError(domain: "TingwuService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid status response"])
        }
        
        // Return full data object as result if completed
        return (status, dataObj)
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
        
        request.addValue(timestamp, forHTTPHeaderField: "x-acs-date")
        request.addValue(nonce, forHTTPHeaderField: "x-acs-signature-nonce")
        request.addValue("ACS3-HMAC-SHA256", forHTTPHeaderField: "x-acs-signature-method")
        request.addValue("2023-09-30", forHTTPHeaderField: "x-acs-version") // Version from search result
        // Wait, search result 2 said "2023-09-30" but search result 5 said "2022-09-30".
        // Search result 2 title: "API-tingwu-2023-09-30". So use 2023-09-30.
        
        // Content-SHA256
        let contentSha256: String
        if let body = body {
            contentSha256 = SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined()
        } else {
             // Empty string hash
             contentSha256 = SHA256.hash(data: Data()).map { String(format: "%02x", $0) }.joined()
        }
        request.addValue(contentSha256, forHTTPHeaderField: "x-acs-content-sha256")
        
        // 2. Canonical Request
        let method = request.httpMethod ?? "GET"
        let uri = request.url?.path ?? "/"
        let query = request.url?.query ?? "" // Needs to be sorted and percent encoded.
        // Since we only use simple query or no query, simple string is fine if already encoded.
        // But strictly, we should sort query params.
        // For CreateTask: type=offline.
        // For GetTaskInfo: no query.
        
        // Canonical Headers
        // Lowercase keys, sorted, trim value.
        // We signed: host, x-acs-content-sha256, x-acs-date, x-acs-signature-nonce, x-acs-signature-method, x-acs-version
        // And maybe Content-Type if present.
        
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("tingwu.cn-beijing.aliyuncs.com", forHTTPHeaderField: "host")
        
        let headersToSign = [
            "content-type": "application/json",
            "host": "tingwu.cn-beijing.aliyuncs.com",
            "x-acs-content-sha256": contentSha256,
            "x-acs-date": timestamp,
            "x-acs-signature-method": "ACS3-HMAC-SHA256",
            "x-acs-signature-nonce": nonce,
            "x-acs-version": "2023-09-30"
        ]
        
        let sortedHeaderKeys = headersToSign.keys.sorted()
        let canonicalHeaders = sortedHeaderKeys.map { "\($0):\(headersToSign[$0]!)" }.joined(separator: "\n")
        let signedHeaders = sortedHeaderKeys.joined(separator: ";")
        
        let canonicalRequest = """
        \(method)
        \(uri)
        \(query)
        \(canonicalHeaders)
        
        \(signedHeaders)
        \(contentSha256)
        """
        
        let canonicalRequestHash = SHA256.hash(data: canonicalRequest.data(using: .utf8)!).map { String(format: "%02x", $0) }.joined()
        
        // 3. String To Sign
        let stringToSign = """
        ACS3-HMAC-SHA256
        \(timestamp)
        \(canonicalRequestHash)
        """
        
        // 4. Signature
        let signature = hmac(key: akSecret, string: stringToSign)
        
        // 5. Authorization Header
        let auth = "ACS3-HMAC-SHA256 Credential=\(akId),SignedHeaders=\(signedHeaders),Signature=\(signature)"
        request.addValue(auth, forHTTPHeaderField: "Authorization")
    }
    
    private func hmac(key: String, string: String) -> String {
        let keyData = key.data(using: .utf8)!
        let data = string.data(using: .utf8)!
        let mac = HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: keyData))
        return mac.map { String(format: "%02x", $0) }.joined()
    }
}
