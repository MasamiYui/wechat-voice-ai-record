import SwiftUI

struct PipelineView: View {
    @StateObject var manager: MeetingPipelineManager
    private let settings: SettingsStore
    @State private var showingResult = false
    
    // Rerun interaction
    @State private var stepToRerun: MeetingTaskStatus?
    @State private var showRerunAlert = false
    
    init(task: MeetingTask, settings: SettingsStore) {
        self.settings = settings
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
                // Record Step (Not interactive for rerun)
                StepView(title: "Record", icon: "mic.fill", isActive: true, isCompleted: true, isFailed: false)
                    .opacity(1.0)
                
                ArrowView()
                
                stepButton(title: "Transcode", icon: "waveform", step: .transcoding)
                ArrowView()
                stepButton(title: "Upload", icon: "icloud.and.arrow.up", step: .uploading)
                ArrowView()
                stepButton(title: "Create Task", icon: "doc.badge.plus", step: .created)
                ArrowView()
                stepButton(title: "Poll", icon: "arrow.triangle.2.circlepath", step: .polling)
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
            ResultView(task: manager.task, settings: settings)
        }
        .alert("Rerun Step?", isPresented: $showRerunAlert, presenting: stepToRerun) { step in
            Button("Cancel", role: .cancel) { }
            Button("Rerun") {
                rerun(step)
            }
        } message: { step in
            Text("Are you sure you want to rerun '\(stepTitle(step))'? This might overwrite existing data.")
        }
    }
    
    // MARK: - Helpers
    
    private func stepButton(title: String, icon: String, step: MeetingTaskStatus) -> some View {
        let canRerun = manager.task.status == .completed || manager.task.status == .failed
        
        return Button(action: {
            if canRerun {
                stepToRerun = step
                showRerunAlert = true
            }
        }) {
            StepView(
                title: title,
                icon: icon,
                isActive: manager.task.status == step,
                isCompleted: isAfter(step),
                isFailed: isFailed(step)
            )
            .contentShape(Rectangle()) // Make sure the whole area is clickable
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.accentColor, lineWidth: canRerun ? 0 : 0) // Placeholder for hover effect if needed
            )
        }
        .buttonStyle(.plain)
        .disabled(!canRerun)
        .onHover { inside in
            if canRerun && inside {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .help(canRerun ? "Click to rerun this step" : "")
    }
    
    private func stepTitle(_ step: MeetingTaskStatus) -> String {
        switch step {
        case .transcoding: return "Transcode"
        case .uploading: return "Upload"
        case .created: return "Create Task"
        case .polling: return "Poll Status"
        default: return step.rawValue
        }
    }

    private func rerun(_ step: MeetingTaskStatus) {
        Task {
            switch step {
            case .transcoding: await manager.transcode(force: true)
            case .uploading: await manager.upload()
            case .created: await manager.createTask()
            case .polling: await manager.pollStatus()
            default: break
            }
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
        
        let currentStatus: MeetingTaskStatus
        if manager.task.status == .failed {
            if let failedStep = manager.task.failedStep {
                currentStatus = failedStep
            } else {
                return false
            }
        } else {
            currentStatus = manager.task.status
        }
        
        guard let currentIndex = order.firstIndex(of: currentStatus),
              let targetIndex = order.firstIndex(of: status) else { return false }
        
        return currentIndex > targetIndex
    }
    
    private func isFailed(_ step: MeetingTaskStatus) -> Bool {
        guard manager.task.status == .failed else { return false }
        return manager.task.failedStep == step
    }
    
    @ViewBuilder
    private var actionButton: some View {
        switch manager.task.status {
        case .recorded:
            Button("Transcode Audio") {
                Task { await manager.transcode() }
            }
            .buttonStyle(.borderedProminent)
            
        case .failed:
            VStack {
                if let failedStep = manager.task.failedStep {
                    Text("Failed at: \(failedStep.rawValue.capitalized)")
                        .foregroundColor(.red)
                        .font(.caption)
                    
                    Button("Retry \(failedStep.rawValue.capitalized)") {
                        Task { await manager.retry() }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Retry Last Step") {
                        Task { await manager.retry() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                
                Button("Restart from Beginning") {
                    Task { await manager.restartFromBeginning() }
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .font(.caption)
                .padding(.top, 4)
            }
            
        case .transcoding:
            Text("Transcoding...")
            
        case .transcoded:
            Button("Upload to OSS") {
                Task { await manager.upload() }
            }
            .buttonStyle(.borderedProminent)
            
        case .uploading:
            Text("Uploading...")
            
        case .uploaded:
             Button("Create Tingwu Task") {
                 Task { await manager.createTask() }
             }
             .buttonStyle(.borderedProminent)
             
        case .created:
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
    let isFailed: Bool
    
    var body: some View {
        VStack {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(isFailed ? .red : (isCompleted ? .green : (isActive ? .blue : .gray)))
                .frame(width: 40, height: 40)
                .background(Circle().fill(isFailed ? Color.red.opacity(0.1) : Color.gray.opacity(0.1)))
            
            Text(title)
                .font(.caption)
                .foregroundColor(isFailed ? .red : (isCompleted ? .primary : .secondary))
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
