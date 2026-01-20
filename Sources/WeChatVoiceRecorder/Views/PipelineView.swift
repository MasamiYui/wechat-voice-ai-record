import SwiftUI

struct PipelineView: View {
    @StateObject var manager: MeetingPipelineManager
    @State private var showingResult = false
    
    init(task: MeetingTask, settings: SettingsStore) {
        _manager = StateObject(wrappedValue: MeetingPipelineManager(task: task, settings: settings))
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Task Info
            HStack {
                VStack(alignment: .leading) {
                    Text(manager.task.title)
                        .font(.headline)
                    Text(manager.task.createdAt.formatted())
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text(manager.task.status.rawValue.uppercased())
                    .font(.caption)
                    .padding(6)
                    .background(statusColor.opacity(0.2))
                    .foregroundColor(statusColor)
                    .cornerRadius(4)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            
            // Pipeline Steps
            HStack(spacing: 0) {
                StepView(title: "Record", icon: "mic.fill", isActive: true, isCompleted: true)
                ArrowView()
                StepView(title: "Transcode", icon: "waveform", isActive: manager.task.status == .transcoding, isCompleted: isAfter(.transcoding))
                ArrowView()
                StepView(title: "Upload", icon: "icloud.and.arrow.up", isActive: manager.task.status == .uploading, isCompleted: isAfter(.uploading))
                ArrowView()
                StepView(title: "Create Task", icon: "doc.badge.plus", isActive: manager.task.status == .created, isCompleted: isAfter(.created))
                ArrowView()
                StepView(title: "Poll", icon: "arrow.triangle.2.circlepath", isActive: manager.task.status == .polling, isCompleted: manager.task.status == .completed)
            }
            .padding(.vertical)
            
            Divider()
            
            // Action Area
            VStack(spacing: 12) {
                if let error = manager.errorMessage {
                    Text("Error: \(error)")
                        .foregroundColor(.red)
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                }
                
                if manager.isProcessing {
                    ProgressView("Processing...")
                } else {
                    actionButton
                }
            }
            .padding()
            
            if manager.task.status == .completed {
                Button("View Result") {
                    showingResult = true
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(minWidth: 500)
        .sheet(isPresented: $showingResult) {
            ResultView(task: manager.task)
        }
    }
    
    private var statusColor: Color {
        switch manager.task.status {
        case .completed: return .green
        case .failed: return .red
        case .recorded: return .blue
        default: return .orange
        }
    }
    
    private func isAfter(_ status: MeetingTaskStatus) -> Bool {
        let order: [MeetingTaskStatus] = [.recorded, .transcoding, .transcoded, .uploading, .uploaded, .created, .polling, .completed]
        guard let currentIndex = order.firstIndex(of: manager.task.status),
              let targetIndex = order.firstIndex(of: status) else { return false }
        
        // Handle "uploaded" mapping to "created" step check
        // If status is .uploaded, it means Transcode and Upload are done.
        
        return currentIndex > targetIndex
    }
    
    @ViewBuilder
    private var actionButton: some View {
        switch manager.task.status {
        case .recorded, .failed:
            Button("Transcode Audio") {
                Task { await manager.transcode() }
            }
            .buttonStyle(.borderedProminent)
            
        case .transcoding:
            Text("Transcoding...")
            
        case .transcoded:
            Button("Upload to OSS") {
                Task { await manager.upload() }
            }
            .buttonStyle(.borderedProminent)
            
        case .uploading:
            Text("Uploading...")
            
        // After transcoding (which sets status back to .recorded with new path? No, I need a status)
        // Wait, in manager I set status to .recorded after transcode.
        // This is ambiguous. I should have set it to .transcoded or just auto-upload.
        // But user wants manual steps.
        // Let's assume .recorded means "Ready to Transcode".
        // If I want "Ready to Upload", I need a status.
        // I added .uploaded.
        // Let's refine the flow logic in View:
        
        // If local file is "mixed_48k.m4a", implies transcoded.
        // This is a bit hacky.
        // Let's assume user clicks "Start" and it does Transcode -> Upload -> Create Task -> Poll automatically?
        // User said: "手动执行， UI做成流水线一样，自己点进去下一个节点这样".
        // This implies: Click "Transcode" -> Done. Click "Upload" -> Done. Click "Create" -> Done.
        
        // Let's try to infer next step or provide buttons for all available next steps.
        
        case .uploaded:
             Button("Create Tingwu Task") {
                 Task { await manager.createTask() }
             }
             .buttonStyle(.borderedProminent)
             
        case .created: // Actually I used .created as "Creating" state in manager.
             // Wait, manager sets .created BEFORE async call, then .polling AFTER.
             // So .created is a transient state "Creating...".
             Text("Creating Task...")
             
        case .polling:
             Button("Refresh Status") {
                 Task { await manager.pollStatus() }
             }
             .buttonStyle(.bordered)
             
        case .completed:
             Text("Completed")
                .foregroundColor(.green)
        }
    }
}

struct StepView: View {
    let title: String
    let icon: String
    let isActive: Bool
    let isCompleted: Bool
    
    var body: some View {
        VStack {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(isCompleted ? .green : (isActive ? .blue : .gray))
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.gray.opacity(0.1)))
            
            Text(title)
                .font(.caption)
                .foregroundColor(isCompleted ? .primary : .secondary)
        }
        .frame(width: 80)
    }
}

struct ArrowView: View {
    var body: some View {
        Image(systemName: "arrow.right")
            .foregroundColor(.gray)
            .frame(width: 20)
    }
}
