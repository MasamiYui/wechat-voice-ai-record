import XCTest
@testable import WeChatVoiceRecorder

final class OSSUploadTests: XCTestCase {
    private let ossAccessKeyId = "YOUR_ACCESS_KEY_ID"
    private let ossAccessKeySecret = "YOUR_ACCESS_KEY_SECRET"
    private let ossBucket = "YOUR_BUCKET_NAME"
    private let ossRegion = "cn-beijing"
    private let ossEndpoint = "https://oss-cn-beijing.aliyuncs.com"
    private let ossPrefix = "wvr/"
    
    func testOSSUploadConnection() async throws {
        guard ossAccessKeyId != "YOUR_ACCESS_KEY_ID",
              ossAccessKeySecret != "YOUR_ACCESS_KEY_SECRET",
              ossBucket != "YOUR_BUCKET_NAME",
              !ossAccessKeyId.isEmpty,
              !ossAccessKeySecret.isEmpty,
              !ossBucket.isEmpty else {
            throw XCTSkip("Please fill OSS credentials in OSSUploadTests.swift")
        }
        
        let settings = SettingsStore()
        settings.ossRegion = ossRegion
        settings.ossEndpoint = ossEndpoint
        settings.ossBucket = ossBucket
        settings.ossPrefix = ossPrefix
        settings.saveAccessKeyId(ossAccessKeyId)
        settings.saveAccessKeySecret(ossAccessKeySecret)
        
        defer {
            settings.clearSecrets()
        }
        
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("test_oss_\(UUID().uuidString).txt")
        try "Connection Test".write(to: tempFile, atomically: true, encoding: .utf8)
        
        let service = OSSService(settings: settings)
        let objectKey = "\(settings.ossPrefix)test/\(UUID().uuidString).txt"
        let url = try await service.uploadFile(fileURL: tempFile, objectKey: objectKey)
        
        XCTAssertTrue(url.contains(ossBucket))
        XCTAssertTrue(url.contains(objectKey))
    }
}
