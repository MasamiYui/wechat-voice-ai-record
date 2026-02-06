import XCTest
@testable import VoiceMemo

final class VolcengineTests: XCTestCase {
    
    func testServiceFactory() {
        let settings = SettingsStore()
        
        // Default is Tingwu
        settings.asrProvider = .tingwu
        let manager1 = MeetingPipelineManager(task: MeetingTask(recordingId: "1", localFilePath: "", title: ""), settings: settings)
        XCTAssertTrue(manager1.activeTranscriptionService is TingwuService)
        
        // Switch to Volcengine
        settings.asrProvider = .volcengine
        let manager2 = MeetingPipelineManager(task: MeetingTask(recordingId: "2", localFilePath: "", title: ""), settings: settings)
        XCTAssertTrue(manager2.activeTranscriptionService is VolcengineService)
    }

    func testCreateTaskRequestConstruction() throws {
        let settings = SettingsStore()
        settings.volcAppId = "TEST_APP_ID"
        settings.volcResourceId = "volc.auc.common"
        settings.enableRoleSplit = false // Ensure it works even if setting is false
        settings.saveVolcAccessToken("TEST_TOKEN")
        defer { settings.clearVolcSecrets() }
        
        let service = VolcengineService(settings: settings)
        let requestId = "TEST_REQ_ID"
        let request = try service.buildCreateTaskRequest(fileUrl: "https://example.com/audio.m4a", requestId: requestId)
        
        XCTAssertEqual(request.url?.absoluteString, "https://openspeech.bytedance.com/api/v3/auc/bigmodel/submit")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        // V3 Auth Headers
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Api-App-Key"), "TEST_APP_ID")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Api-Access-Key"), "TEST_TOKEN")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Api-Resource-Id"), "volc.auc.common")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Api-Request-Id"), requestId)
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Api-Sequence"), "-1")
        
        guard let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any],
              let user = json["user"] as? [String: Any],
              let audio = json["audio"] as? [String: Any],
              let req = json["request"] as? [String: Any] else {
            XCTFail("Failed to parse request body")
            return
        }
        
        XCTAssertEqual(user["uid"] as? String, requestId)
        
        XCTAssertEqual(audio["url"] as? String, "https://example.com/audio.m4a")
        XCTAssertEqual(audio["format"] as? String, "m4a")
        
        XCTAssertEqual(req["model_name"] as? String, "bigmodel")
        XCTAssertEqual(req["enable_speaker_info"] as? Bool, true)
        XCTAssertEqual(req["ssd_version"] as? String, "200")
        XCTAssertEqual(req["enable_itn"] as? Bool, true)
        XCTAssertEqual(req["enable_punc"] as? Bool, true)
    }
    
    func testQueryRequestConstruction() throws {
        let settings = SettingsStore()
        settings.volcAppId = "TEST_APP_ID"
        settings.volcResourceId = "volc.auc.common"
        settings.saveVolcAccessToken("TEST_TOKEN")
        defer { settings.clearVolcSecrets() }
        
        let service = VolcengineService(settings: settings)
        let request = try service.buildQueryRequest(taskId: "TASK_ID")
        
        XCTAssertEqual(request.url?.absoluteString, "https://openspeech.bytedance.com/api/v3/auc/bigmodel/query")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        // V3 Auth Headers
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Api-App-Key"), "TEST_APP_ID")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Api-Access-Key"), "TEST_TOKEN")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Api-Resource-Id"), "volc.auc.common")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Api-Request-Id"), "TASK_ID")
        
        guard let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            XCTFail("Failed to parse request body")
            return
        }
        
        XCTAssertTrue(json.isEmpty)
    }
    
    func testTranscriptParsingFromUtterances() {
        // Test the new Volcengine format support in TranscriptParser
        
        let volcResponse: [String: Any] = [
            "utterances": [
                [
                    "text": "Hello World",
                    "start_time": 100,
                    "end_time": 200,
                    "additions": ["speaker": "Speaker 1"]
                ],
                [
                    "text": "This is a test",
                    "start_time": 300,
                    "end_time": 400,
                    "speaker": "Alice"
                ]
            ]
        ]
        
        let text = TranscriptParser.buildTranscriptText(from: volcResponse)
        XCTAssertEqual(text, "Speaker 1: Hello World\nSpeaker Alice: This is a test")
    }
    
    func testTranscriptParsingFromText() {
        let volcResponse: [String: Any] = [
            "text": "Full transcript text here."
        ]
        
        let text = TranscriptParser.buildTranscriptText(from: volcResponse)
        XCTAssertEqual(text, "Full transcript text here.")
    }
}
