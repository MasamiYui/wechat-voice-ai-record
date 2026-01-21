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
        
        var endpoint = settings.ossEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if !endpoint.hasPrefix("http") {
            endpoint = "https://\(endpoint)"
        }
        
        let bucket = settings.ossBucket.trimmingCharacters(in: .whitespacesAndNewlines)
        let region = settings.ossRegion.trimmingCharacters(in: .whitespacesAndNewlines)
        
        settings.log("OSS upload start: file=\(fileURL.path) bucket=\(bucket) key=\(objectKey) region=\(region) endpoint=\(endpoint)")
        
        let provider = StaticCredentialsProvider(accessKeyId: akId, accessKeySecret: akSecret)
        let config = Configuration.default()
            .withRegion(region)
            .withEndpoint(endpoint)
            .withCredentialsProvider(provider)
            
        let client = Client(config)
        
        let request = PutObjectRequest(
            bucket: bucket,
            key: objectKey,
            body: .file(fileURL)
        )
        
        do {
            let result = try await client.putObject(request)
            
            guard result.statusCode >= 200 && result.statusCode < 300 else {
                settings.log("OSS upload failed: status=\(result.statusCode)")
                throw NSError(domain: "OSSService", code: Int(result.statusCode), userInfo: [
                    NSLocalizedDescriptionKey: "Upload failed with status \(result.statusCode)"
                ])
            }
            
            var host = endpoint
            if host.hasPrefix("https://") {
                host = String(host.dropFirst(8))
            } else if host.hasPrefix("http://") {
                host = String(host.dropFirst(7))
            }
            
            let publicUrl = "https://\(bucket).\(host)/\(objectKey)"
            settings.log("OSS upload success: url=\(publicUrl)")
            
            return publicUrl
        } catch let ossError as AlibabaCloudOSS.ClientError {
            settings.log("OSS ClientError: \(String(describing: ossError))")
            throw ossError
        } catch {
            settings.log("OSS upload error: \(String(describing: error))")
            throw error
        }
    }
}
