import SwiftUI
import UniformTypeIdentifiers

struct ResultView: View {
    let task: MeetingTask
    @State private var selectedTab: ResultTab = .overview
    
    enum ResultTab: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case transcript = "Transcript"
        case raw = "Raw Data"
        
        var id: String { self.rawValue }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text(task.title)
                        .font(.title2)
                        .fontWeight(.bold)
                    Text(task.createdAt, style: .date)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Picker("View", selection: $selectedTab) {
                    ForEach(ResultTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 300)
                
                Spacer()
                
                Button(action: exportMarkdown) {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .overlay(Divider(), alignment: .bottom)
            
            // Content
            Group {
                switch selectedTab {
                case .overview:
                    OverviewView(task: task)
                case .transcript:
                    TranscriptView(text: task.transcript ?? "No transcript available.")
                case .raw:
                    ScrollView {
                        Text(task.rawResponse ?? "No raw response.")
                            .font(.monospaced(.body)())
                            .padding()
                            .textSelection(.enabled)
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
        
        if let summary = task.summary {
            md += "## Summary\n\(summary)\n\n"
        }
        
        if let keyPoints = task.keyPoints {
            md += "## Key Points\n\(keyPoints)\n\n"
        }
        
        if let actionItems = task.actionItems {
            md += "## Action Items\n\(actionItems)\n\n"
        }
        
        if let transcript = task.transcript {
            md += "## Transcript\n\(transcript)\n"
        }
        
        return md
    }
}

struct OverviewView: View {
    let task: MeetingTask
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
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
            .padding()
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
                .padding()
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
            
            Text(content)
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
}
