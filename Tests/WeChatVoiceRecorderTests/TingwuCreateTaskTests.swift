import XCTest
@testable import WeChatVoiceRecorder

final class TingwuCreateTaskTests: XCTestCase {
    private let accessKeyId = "YOUR_ACCESS_KEY_ID"
    private let accessKeySecret = "YOUR_ACCESS_KEY_SECRET"
    private let appKey = "YOUR_TINGWU_APPKEY"
    private let fileUrl = "YOUR_PUBLIC_OSS_FILE_URL"
    
    func testCreateTask() async throws {
        guard !accessKeyId.isEmpty, accessKeyId != "YOUR_ACCESS_KEY_ID",
              !accessKeySecret.isEmpty, accessKeySecret != "YOUR_ACCESS_KEY_SECRET",
              !appKey.isEmpty, appKey != "YOUR_TINGWU_APPKEY",
              !fileUrl.isEmpty, fileUrl != "YOUR_PUBLIC_OSS_FILE_URL" else {
            throw XCTSkip("Please fill Tingwu credentials and OSS file URL in TingwuCreateTaskTests.swift")
        }
        
        let settings = SettingsStore()
        settings.tingwuAppKey = appKey
        settings.saveAccessKeyId(accessKeyId)
        settings.saveAccessKeySecret(accessKeySecret)
        
        defer {
            settings.clearSecrets()
        }
        
        let service = TingwuService(settings: settings)
        let taskId = try await service.createTask(fileUrl: fileUrl)
        
        XCTAssertFalse(taskId.isEmpty)
    }
    
    func testCreateTaskRequestConstruction() throws {
        // This test verifies that the request body is constructed correctly,
        // specifically checking that Summarization and MeetingAssistance parameters are present.
        
        let settings = SettingsStore()
        settings.tingwuAppKey = "TEST_APP_KEY"
        settings.saveAccessKeyId("TEST_AK_ID")
        settings.saveAccessKeySecret("TEST_AK_SECRET")
        
        // Enable features to test parameter generation
        settings.enableSummary = true
        settings.enableKeyPoints = true
        settings.enableActionItems = true
        settings.enableRoleSplit = true
        
        let service = TingwuService(settings: settings)
        let fileUrl = "https://example.com/audio.m4a"
        
        // Call the internal helper method (made accessible via @testable)
        let request = try service.buildCreateTaskRequest(fileUrl: fileUrl)
        
        // Verify URL
        XCTAssertEqual(request.url?.absoluteString, "https://tingwu.cn-beijing.aliyuncs.com/openapi/tingwu/v2/tasks?type=offline")
        XCTAssertEqual(request.httpMethod, "PUT")
        
        // Verify Body
        guard let bodyData = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
              let parameters = json["Parameters"] as? [String: Any] else {
            XCTFail("Failed to parse request body")
            return
        }
        
        // Check Summarization
        XCTAssertEqual(parameters["SummarizationEnabled"] as? Bool, true)
        if let summarization = parameters["Summarization"] as? [String: Any],
           let types = summarization["Types"] as? [String] {
            XCTAssertTrue(types.contains("Paragraph"))
            XCTAssertTrue(types.contains("Conversational"))
        } else {
            XCTFail("Summarization.Types missing")
        }
        
        // Check MeetingAssistance
        XCTAssertEqual(parameters["MeetingAssistanceEnabled"] as? Bool, true)
        if let assistance = parameters["MeetingAssistance"] as? [String: Any],
           let types = assistance["Types"] as? [String] {
            XCTAssertTrue(types.contains("KeyInformation"))
            XCTAssertTrue(types.contains("Actions"))
        } else {
            XCTFail("MeetingAssistance.Types missing")
        }
        
        // Check Diarization
        if let transcription = parameters["Transcription"] as? [String: Any] {
            XCTAssertEqual(transcription["DiarizationEnabled"] as? Bool, true)
            if let diarization = transcription["Diarization"] as? [String: Any] {
                 XCTAssertEqual(diarization["SpeakerCount"] as? Int, 0)
            } else {
                XCTFail("Transcription.Diarization missing")
            }
        } else {
             XCTFail("Transcription missing")
        }
    }
    
    func testTranscriptParsingFromParagraphs() {
        let settings = SettingsStore()
        let task = MeetingTask(recordingId: "r1", localFilePath: "/tmp/mixed.m4a", title: "t1")
        let manager = MeetingPipelineManager(task: task, settings: settings)
        
        let transcriptionData: [String: Any] = [
            "Paragraphs": [
                [
                    "SpeakerId": 1,
                    "Words": [
                        ["Text": "你好"],
                        ["Text": "世界"]
                    ]
                ],
                [
                    "SpeakerId": 2,
                    "Words": [
                        ["Text": "收到"]
                    ]
                ]
            ]
        ]
        
        let text = manager.buildTranscriptText(from: transcriptionData)
        XCTAssertEqual(text, "Speaker 1: 你好世界\nSpeaker 2: 收到")
    }
}
