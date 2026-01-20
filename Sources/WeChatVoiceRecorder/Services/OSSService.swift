import Foundation
import AlibabaCloudOSS

class OSSService {
    private let settings: SettingsStore
    
    init(settings: SettingsStore) {
        self.settings = settings
    }
    
    func uploadFile(fileURL: URL, objectKey: String) async throws -> String {
        guard let akId = settings.getAccessKeyId(),
              let akSecret = settings.getAccessKeySecret() else {
            throw NSError(domain: "OSSService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Missing AccessKey"])
        }
        
        let provider = StaticCredentialsProvider(accessKeyId: akId, accessKeySecret: akSecret)
        let config = Configuration.default()
            .withRegion(settings.ossRegion)
            .withEndpoint(settings.ossEndpoint)
            .withCredentialsProvider(provider)
            
        let client = Client(config)
        
        // Ensure bucket exists or just upload
        // For MVP, assume bucket exists
        
        // Put Object
        // Note: Using PutObjectFromFile if available, or PutObject with file body
        // The SDK v2 usually has putObject(request). body can be .file(url)
        let request = PutObjectRequest(
            bucket: settings.ossBucket,
            key: objectKey,
            body: .file(fileURL)
        )
        
        let result = try await client.putObject(request)
        
        guard result.statusCode >= 200 && result.statusCode < 300 else {
            throw NSError(domain: "OSSService", code: Int(result.statusCode), userInfo: [NSLocalizedDescriptionKey: "Upload failed with status \(result.statusCode)"])
        }
        
        // Construct Public URL
        // Format: https://{bucket}.{endpoint}/{key}
        // Endpoint in settings: https://oss-cn-beijing.aliyuncs.com
        // Result: https://wechat-record.oss-cn-beijing.aliyuncs.com/wvr/...
        
        // Strip protocol from endpoint if present to be safe, then reconstruct
        var host = settings.ossEndpoint
        if host.hasPrefix("https://") {
            host = String(host.dropFirst(8))
        } else if host.hasPrefix("http://") {
            host = String(host.dropFirst(7))
        }
        
        // For standard OSS endpoint: bucket.endpoint
        // If CNAME, just endpoint/key
        // Here we use standard Beijing endpoint
        let publicUrl = "https://\(settings.ossBucket).\(host)/\(objectKey)"
        
        return publicUrl
    }
}
