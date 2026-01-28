import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    @State private var selectedMode: MeetingMode = .mixed
    @State private var file1URL: URL?
    @State private var file2URL: URL?
    @State private var isImporting = false
    @State private var errorMessage: String?
    
    var onImport: (MeetingMode, [URL]) -> Void
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Configuration Card
                GroupBox(label: Text("Configuration").bold()) {
                    VStack(spacing: 12) {
                        FormRow(label: "Mode") {
                            Picker("", selection: $selectedMode) {
                                Text("Mixed Mode (Single File)").tag(MeetingMode.mixed)
                                Text("Separated Mode (Dual Files)").tag(MeetingMode.separated)
                            }
                            .labelsHidden()
                            .frame(maxWidth: 240)
                        }
                        
                        Divider()
                        
                        FormRow(label: "Description") {
                            Text(modeDescription)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(8)
                }
                
                // Files Card
                GroupBox(label: Text("Files").bold()) {
                    VStack(spacing: 12) {
                        if selectedMode == .mixed {
                            FilePickerRow(title: "Audio File", url: $file1URL)
                        } else {
                            FilePickerRow(title: "Local (Speaker 1)", url: $file1URL)
                            FilePickerRow(title: "Remote (Speaker 2)", url: $file2URL)
                        }
                    }
                    .padding(8)
                }
                
                // Error Message
                if let error = errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(error)
                            .foregroundColor(.red)
                            .font(.callout)
                    }
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                }
                
                // Action Button
                HStack {
                    Spacer()
                    Button(action: doImport) {
                        if isImporting {
                            ProgressView()
                                .controlSize(.small)
                                .padding(.horizontal, 8)
                        } else {
                            Text("Start Import")
                                .padding(.horizontal, 8)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!canImport || isImporting)
                }
                .padding(.top, 10)
            }
            .padding()
            .frame(maxWidth: 800)
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }
    
    private var modeDescription: String {
        switch selectedMode {
        case .mixed:
            return "Mixed mode uses a single audio file containing all speakers. Suitable for standard recordings."
        case .separated:
            return "Separated mode requires two files: one for the local speaker (Mic) and one for the remote speaker (System Audio)."
        }
    }
    
    private var canImport: Bool {
        if selectedMode == .mixed {
            return file1URL != nil
        } else {
            return file1URL != nil && file2URL != nil
        }
    }
    
    private func doImport() {
        var files: [URL] = []
        if let f1 = file1URL { files.append(f1) }
        if selectedMode == .separated, let f2 = file2URL { files.append(f2) }
        
        isImporting = true
        errorMessage = nil
        
        // Slight delay to allow UI update
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            onImport(selectedMode, files)
            isImporting = false
        }
    }
    
    // MARK: - Helper Views
    
    private func FormRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .frame(width: 120, alignment: .trailing)
                .foregroundColor(.secondary)
            content()
        }
    }
}

struct FilePickerRow: View {
    let title: String
    @Binding var url: URL?
    
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .frame(width: 120, alignment: .trailing)
                .foregroundColor(.secondary)
            
            HStack {
                if let url = url {
                    Image(systemName: "doc.audio")
                        .foregroundColor(.blue)
                    Text(url.lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundColor(.primary)
                } else {
                    Text("No file selected")
                        .foregroundColor(.secondary)
                        .italic()
                }
                
                Spacer()
                
                if url != nil {
                    Button(action: { self.url = nil }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear selection")
                }
                
                Button("Select...") {
                    selectFile()
                }
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
    }
    
    private func selectFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Select"
        
        panel.begin { response in
            if response == .OK {
                self.url = panel.url
            }
        }
    }
}
