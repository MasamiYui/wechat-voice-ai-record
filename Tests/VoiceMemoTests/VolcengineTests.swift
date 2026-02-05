import XCTest
@testable import VoiceMemo

final class VolcengineTests: XCTestCase {
    
    func testServiceFactory() {
        let settings = SettingsStore()
        
        // Default is Tingwu
        settings.asrProvider = .tingwu
        let manager1 = MeetingPipelineManager(task: MeetingTask(recordingId: "1", localFilePath: "", title: ""), settings: settings)
        // Accessing private property via Mirror for testing verification
        let mirror1 = Mirror(reflecting: manager1)
        if let service = mirror1.children.first(where: { $0.label == "transcriptionService" })?.value {
             XCTAssertTrue(service is TingwuService)
        } else {
            XCTFail("transcriptionService not found")
        }
        
        // Switch to Volcengine
        settings.asrProvider = .volcengine
        let manager2 = MeetingPipelineManager(task: MeetingTask(recordingId: "2", localFilePath: "", title: ""), settings: settings)
        let mirror2 = Mirror(reflecting: manager2)
        if let service = mirror2.children.first(where: { $0.label == "transcriptionService" })?.value {
             XCTAssertTrue(service is VolcengineService)
        } else {
             XCTFail("transcriptionService not found")
        }
    }
    
    func testTranscriptParsingFromUtterances() {
        // Test the new Volcengine format support in TranscriptParser
        
        let volcResponse: [String: Any] = [
            "utterances": [
                [
                    "text": "Hello World",
                    "start_time": 100,
                    "end_time": 200
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
        XCTAssertEqual(text, "Hello World\nAlice: This is a test")
    }
    
    func testTranscriptParsingFromText() {
        let volcResponse: [String: Any] = [
            "text": "Full transcript text here."
        ]
        
        let text = TranscriptParser.buildTranscriptText(from: volcResponse)
        XCTAssertEqual(text, "Full transcript text here.")
    }
}
