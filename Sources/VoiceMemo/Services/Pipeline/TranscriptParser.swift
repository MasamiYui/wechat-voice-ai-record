import Foundation

/// Protocol for parsing transcription results from different providers
protocol TranscriptionResultParser {
    func canParse(_ data: [String: Any]) -> Bool
    func parse(_ data: [String: Any]) -> String?
}

/// Helper for consistent formatting
enum TranscriptFormatHelper {
    static func formatSpeaker(_ val: Any) -> String {
        let str = "\(val)"
        if str.lowercased().hasPrefix("speaker") { return str }
        return "Speaker \(str)"
    }
}

/// Parser for Aliyun Tingwu format
struct TingwuParser: TranscriptionResultParser {
    func canParse(_ data: [String: Any]) -> Bool {
        return data.keys.contains("Result") || 
               data.keys.contains("Transcription") || 
               data.keys.contains("Paragraphs") ||
               data.keys.contains("Sentences")
    }
    
    func parse(_ data: [String: Any]) -> String? {
        // Handle nested Result wrapper
        if let result = data["Result"] as? [String: Any],
           let transcription = result["Transcription"] as? [String: Any] {
            return parse(transcription)
        }
        if let transcription = data["Transcription"] as? [String: Any] {
            return parse(transcription)
        }
        
        if let paragraphs = data["Paragraphs"] as? [[String: Any]] {
            return paragraphs.compactMap { extractLine(from: $0) }.joined(separator: "\n")
        }
        if let sentences = data["Sentences"] as? [[String: Any]] {
            return sentences.compactMap { extractLine(from: $0) }.joined(separator: "\n")
        }
        return nil
    }
    
    private func extractLine(from item: [String: Any]) -> String? {
        let text = extractText(from: item)
        guard !text.isEmpty else { return nil }
        
        if let speaker = extractSpeaker(from: item) {
            return "\(speaker): \(text)"
        }
        return text
    }
    
    private func extractText(from item: [String: Any]) -> String {
        if let text = item["Text"] as? String, !text.isEmpty { return text }
        if let words = item["Words"] as? [[String: Any]] {
            return words.compactMap { $0["Text"] as? String }.joined()
        }
        return ""
    }
    
    private func extractSpeaker(from item: [String: Any]) -> String? {
        if let name = item["SpeakerName"] as? String, !name.isEmpty { return TranscriptFormatHelper.formatSpeaker(name) }
        if let id = item["SpeakerId"] ?? item["SpeakerID"] { return TranscriptFormatHelper.formatSpeaker(id) }
        return nil
    }
}

/// Parser for Volcengine format
struct VolcengineParser: TranscriptionResultParser {
    func canParse(_ data: [String: Any]) -> Bool {
        return data.keys.contains("utterances") || data.keys.contains("text")
    }
    
    func parse(_ data: [String: Any]) -> String? {
        if let utterances = data["utterances"] as? [[String: Any]] {
            return utterances.compactMap { extractLine(from: $0) }.joined(separator: "\n")
        }
        if let text = data["text"] as? String {
            return text
        }
        return nil
    }
    
    private func extractLine(from item: [String: Any]) -> String? {
        let text = item["text"] as? String ?? ""
        guard !text.isEmpty else { return nil }
        
        if let speaker = extractSpeaker(from: item) {
            return "\(speaker): \(text)"
        }
        return text
    }
    
    private func extractSpeaker(from item: [String: Any]) -> String? {
        if let name = item["speaker"] as? String, !name.isEmpty { return TranscriptFormatHelper.formatSpeaker(name) }
        if let additions = item["additions"] as? [String: Any],
           let name = additions["speaker"] as? String, !name.isEmpty {
            return TranscriptFormatHelper.formatSpeaker(name)
        }
        return nil
    }
}

/// Facade for parsing transcription results
struct TranscriptParser {
    
    private static let parsers: [TranscriptionResultParser] = [
        TingwuParser(),
        VolcengineParser()
    ]
    
    static func buildTranscriptText(from transcriptionData: [String: Any]) -> String? {
        for parser in parsers {
            if parser.canParse(transcriptionData) {
                return parser.parse(transcriptionData)
            }
        }
        
        // Fallback for flat structure or unknown format
        if let transcript = transcriptionData["Transcript"] as? String {
            return transcript
        }
        if let text = transcriptionData["text"] as? String {
            return text
        }
        
        return nil
    }
}
