import SwiftUI
import UniformTypeIdentifiers

struct ResultView: View {
    let task: MeetingTask
    let settings: SettingsStore
    @State private var selectedTab: ResultTab = .overview
    @Namespace private var animationNamespace
    
    enum ResultTab: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case transcript = "Transcript"
        case raw = "Raw Data"
        case pipeline = "Pipeline"
        
        var id: String { self.rawValue }
    }
    
    init(task: MeetingTask, settings: SettingsStore) {
        self.task = task
        self.settings = settings
        // Default to Pipeline if task is not completed
        if task.status != .completed {
            _selectedTab = State(initialValue: .pipeline)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 16) {
                // Top Row: Title & Actions
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(task.title)
                            .font(.title2)
                            .fontWeight(.bold)
                        Text(task.createdAt, style: .date)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button(action: exportMarkdown) {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                
                // Bottom Row: Custom Tabs
                HStack(spacing: 24) {
                    ForEach(ResultTab.allCases) { tab in
                        Button {
                            withAnimation(.snappy) {
                                selectedTab = tab
                            }
                        } label: {
                            VStack(spacing: 6) {
                                Text(tab.rawValue)
                                    .font(.system(size: 14))
                                    .fontWeight(selectedTab == tab ? .medium : .regular)
                                    .foregroundColor(selectedTab == tab ? .primary : .secondary)
                                
                                // Active Indicator
                                ZStack {
                                    Rectangle()
                                        .fill(Color.clear)
                                        .frame(height: 2)
                                    if selectedTab == tab {
                                        Rectangle()
                                            .fill(Color.accentColor)
                                            .frame(height: 2)
                                            .matchedGeometryEffect(id: "TabIndicator", in: animationNamespace)
                                    }
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 0)
            .background(Color(nsColor: .controlBackgroundColor))
            .overlay(Divider(), alignment: .bottom)
            
            // Content
            Group {
                switch selectedTab {
                case .overview:
                    OverviewView(task: task)
                case .transcript:
                    TranscriptView(text: derivedTranscript() ?? "No transcript available.")
                case .raw:
                    ScrollView {
                        Text(task.rawData ?? task.rawResponse ?? "No raw response.")
                            .font(.monospaced(.body)())
                            .padding(24)
                            .textSelection(.enabled)
                    }
                case .pipeline:
                    PipelineView(task: task, settings: settings) {
                        withAnimation {
                            selectedTab = .overview
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
        }
    }
    
    private func exportMarkdown() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = "\(task.title).md"
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                let content = generateMarkdown()
                try? content.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
    
    private func generateMarkdown() -> String {
        var md = "# \(task.title)\n\n"
        md += "Date: \(task.createdAt)\n\n"
        
        // Metadata
        md += "## Task Info\n"
        if let key = task.taskKey { md += "- Task Key: \(key)\n" }
        if let status = task.apiStatus { md += "- Status: \(status)\n" }
        if let error = task.statusText, !error.isEmpty { md += "- Message: \(error)\n" }
        if let duration = task.bizDuration { md += "- Duration: \(duration / 1000)s\n" }
        if let mp3 = task.outputMp3Path { md += "- Audio: [Download](\(mp3))\n" }
        md += "\n"
        
        if let summary = task.summary {
            md += "## Summary\n\(summary)\n\n"
        }
        
        if let keyPoints = task.keyPoints {
            md += "## Key Points\n\(keyPoints)\n\n"
        }
        
        if let actionItems = task.actionItems {
            md += "## Action Items\n\(actionItems)\n\n"
        }
        
        if let transcript = derivedTranscript() {
            md += "## Transcript\n\(transcript)\n"
        }
        
        return md
    }
    
    private func derivedTranscript() -> String? {
        if let transcript = task.transcript, !transcript.isEmpty {
            return transcript
        }
        
        // Try to parse from transcriptData (full JSON from DB)
        if let dataStr = task.transcriptData,
           let data = dataStr.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let text = TranscriptParser.buildTranscriptText(from: json) {
                return text
            }
        }
        
        guard let raw = task.rawResponse,
              let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["Result"] as? [String: Any] else {
            return nil
        }
        
        if let transcription = result["Transcription"] as? [String: Any] {
            return extractTranscript(from: transcription)
        }
        if let paragraphs = result["Paragraphs"] as? [[String: Any]] {
            return extractTranscript(from: ["Paragraphs": paragraphs])
        }
        if let sentences = result["Sentences"] as? [[String: Any]] {
            return extractTranscript(from: ["Sentences": sentences])
        }
        if let transcript = result["Transcript"] as? String {
            return transcript
        }
        return nil
    }
    
    private func extractTranscript(from transcriptionData: [String: Any]) -> String? {
        if let paragraphs = transcriptionData["Paragraphs"] as? [[String: Any]] {
            let lines = paragraphs.compactMap { paragraph -> String? in
                let speaker = extractSpeaker(from: paragraph)
                let text = extractText(from: paragraph)
                guard !text.isEmpty else { return nil }
                if let speaker {
                    return "\(speaker): \(text)"
                }
                return text
            }
            return lines.joined(separator: "\n")
        }
        
        if let sentences = transcriptionData["Sentences"] as? [[String: Any]] {
            let lines = sentences.compactMap { sentence -> String? in
                let speaker = extractSpeaker(from: sentence)
                let text = extractText(from: sentence)
                guard !text.isEmpty else { return nil }
                if let speaker {
                    return "\(speaker): \(text)"
                }
                return text
            }
            return lines.joined(separator: "\n")
        }
        
        if let transcript = transcriptionData["Transcript"] as? String {
            return transcript
        }
        
        return nil
    }
    
    private func extractText(from item: [String: Any]) -> String {
        if let text = item["Text"] as? String, !text.isEmpty {
            return text
        }
        if let text = item["text"] as? String, !text.isEmpty {
            return text
        }
        if let words = item["Words"] as? [[String: Any]] {
            let wordTexts = words.compactMap { word -> String? in
                if let text = word["Text"] as? String, !text.isEmpty {
                    return text
                }
                if let text = word["text"] as? String, !text.isEmpty {
                    return text
                }
                return nil
            }
            return wordTexts.joined()
        }
        if let words = item["Words"] as? [String] {
            return words.joined()
        }
        return ""
    }
    
    private func extractSpeaker(from item: [String: Any]) -> String? {
        if let name = item["SpeakerName"] as? String, !name.isEmpty {
            return name
        }
        if let name = item["Speaker"] as? String, !name.isEmpty {
            return name
        }
        if let name = item["Role"] as? String, !name.isEmpty {
            return name
        }
        if let id = item["SpeakerId"] {
            return "Speaker \(stringify(id))"
        }
        if let id = item["SpeakerID"] {
            return "Speaker \(stringify(id))"
        }
        if let id = item["RoleId"] {
            return "Speaker \(stringify(id))"
        }
        return nil
    }
    
    private func stringify(_ value: Any) -> String {
        if let str = value as? String {
            return str
        }
        if let num = value as? Int {
            return String(num)
        }
        if let num = value as? Double {
            return String(Int(num))
        }
        return "\(value)"
    }
}

struct TaskInfoView: View {
    let task: MeetingTask
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "info.circle")
                    .foregroundColor(.blue)
                Text("Task Info")
                    .font(.headline)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                if let key = task.taskKey {
                    InfoRow(label: "Task Key", value: key)
                }
                if let status = task.apiStatus {
                    InfoRow(label: "Status", value: status)
                }
                if let error = task.statusText, !error.isEmpty {
                     InfoRow(label: "Message", value: error)
                }
                if let duration = task.bizDuration {
                    InfoRow(label: "Duration", value: "\(duration / 1000)s")
                }
                if let mp3 = task.outputMp3Path, let url = URL(string: mp3) {
                     HStack(alignment: .top) {
                        Text("Audio:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .frame(width: 80, alignment: .leading)
                        Link("Download Audio", destination: url)
                            .font(.subheadline)
                    }
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack(alignment: .top) {
            Text(label + ":")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.subheadline)
                .textSelection(.enabled)
        }
    }
}

struct OverviewView: View {
    let task: MeetingTask
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Task Info
                TaskInfoView(task: task)
                
                if let summary = task.summary, !summary.isEmpty {
                    SectionCard(title: "Summary", icon: "doc.text", content: summary, color: .blue)
                }
                
                if let keyPoints = task.keyPoints, !keyPoints.isEmpty {
                    SectionCard(title: "Key Points", icon: "list.bullet", content: keyPoints, color: .orange)
                }
                
                if let actionItems = task.actionItems, !actionItems.isEmpty {
                    SectionCard(title: "Action Items", icon: "checkmark.circle", content: actionItems, color: .green)
                }
                
                if (task.summary == nil && task.keyPoints == nil && task.actionItems == nil) {
                     VStack(spacing: 12) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)
                        Text("No analysis results available yet.")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                }
            }
            .padding(24)
        }
    }
}

struct TranscriptView: View {
    let text: String
    
    var body: some View {
        ScrollView {
            Text(text)
                .font(.body)
                .lineSpacing(6)
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }
}

struct SectionCard: View {
    let title: String
    let icon: String
    let content: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            
            Text(markdownContent)
                .font(.body)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
    
    private var markdownContent: AttributedString {
        do {
            return try AttributedString(markdown: content)
        } catch {
            return AttributedString(stringLiteral: content)
        }
    }
}
