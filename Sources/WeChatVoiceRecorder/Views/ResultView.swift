import SwiftUI
import UniformTypeIdentifiers

struct ResultView: View {
    let task: MeetingTask
    
    var body: some View {
        VStack {
            HStack {
                Text(task.title)
                    .font(.headline)
                Spacer()
                Button("Export Markdown") {
                    exportMarkdown()
                }
            }
            .padding()
            
            HSplitView {
                // Left: Structure
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let summary = task.summary, !summary.isEmpty {
                            SectionView(title: "Summary", content: summary)
                        }
                        
                        if let keyPoints = task.keyPoints, !keyPoints.isEmpty {
                            SectionView(title: "Key Points", content: keyPoints)
                        }
                        
                        if let actionItems = task.actionItems, !actionItems.isEmpty {
                            SectionView(title: "Action Items", content: actionItems)
                        }
                    }
                    .padding()
                }
                .frame(minWidth: 300)
                
                // Right: Transcript
                VStack(alignment: .leading) {
                    Text("Transcript")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                    
                    TextEditor(text: .constant(task.transcript ?? "No transcript available"))
                        .font(.body)
                        .padding()
                }
                .frame(minWidth: 300)
            }
        }
        .frame(minWidth: 600, minHeight: 400)
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

struct SectionView: View {
    let title: String
    let content: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(.blue)
            Text(content)
                .textSelection(.enabled)
        }
    }
}
