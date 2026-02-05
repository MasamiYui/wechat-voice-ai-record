import Foundation

/// 转写结果解析器
/// 负责将听悟 API 返回的 JSON 数据解析为可读的文本格式
struct TranscriptParser {
    
    static func buildTranscriptText(from transcriptionData: [String: Any]) -> String? {
        if let result = transcriptionData["Result"] as? [String: Any],
           let transcription = result["Transcription"] as? [String: Any] {
            return buildTranscriptText(from: transcription)
        }
        if let transcription = transcriptionData["Transcription"] as? [String: Any] {
            return buildTranscriptText(from: transcription)
        }
        if let paragraphs = transcriptionData["Paragraphs"] as? [[String: Any]] {
            return paragraphs.compactMap { extractLine(from: $0) }.joined(separator: "\n")
        }
        if let sentences = transcriptionData["Sentences"] as? [[String: Any]] {
            return sentences.compactMap { extractLine(from: $0) }.joined(separator: "\n")
        }
        if let utterances = transcriptionData["utterances"] as? [[String: Any]] {
            return utterances.compactMap { extractLine(from: $0) }.joined(separator: "\n")
        }
        if let transcript = transcriptionData["Transcript"] as? String {
            return transcript
        }
        if let text = transcriptionData["text"] as? String {
            return text
        }
        return nil
    }
    
    private static func extractLine(from item: [String: Any]) -> String? {
        let speaker = extractSpeaker(from: item)
        let text = extractText(from: item)
        guard !text.isEmpty else { return nil }
        if let speaker {
            return "\(speaker): \(text)"
        }
        return text
    }
    
    private static func extractText(from item: [String: Any]) -> String {
        if let text = item["Text"] as? String, !text.isEmpty { return text }
        if let text = item["text"] as? String, !text.isEmpty { return text }
        if let words = item["Words"] as? [[String: Any]] {
            return words.compactMap { $0["Text"] as? String ?? $0["text"] as? String }.joined()
        }
        return ""
    }
    
    private static func extractSpeaker(from item: [String: Any]) -> String? {
        if let name = item["SpeakerName"] as? String, !name.isEmpty { return name }
        if let name = item["Speaker"] as? String, !name.isEmpty { return name }
        if let name = item["speaker"] as? String, !name.isEmpty { return name }
        if let id = item["SpeakerId"] ?? item["SpeakerID"] ?? item["speaker_id"] { return "Speaker \(id)" }
        return nil
    }
}
