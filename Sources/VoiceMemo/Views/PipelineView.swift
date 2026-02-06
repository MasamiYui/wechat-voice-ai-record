import SwiftUI

struct PipelineView: View {
    @StateObject var manager: MeetingPipelineManager
    private let settings: SettingsStore
    @State private var showingResult = false
    
    // Rerun interaction
    @State private var stepToRerun: MeetingTaskStatus?
    @State private var showRerunAlert = false
    
    // Callback for navigation
    var onViewResult: (() -> Void)?
    
    init(task: MeetingTask, settings: SettingsStore, onViewResult: (() -> Void)? = nil) {
        self.settings = settings
        self.onViewResult = onViewResult
        _manager = StateObject(wrappedValue: MeetingPipelineManager(task: task, settings: settings))
    }
    
    var body: some View {
        VStack(spacing: 32) {
            // Pipeline Steps
            HStack(spacing: 0) {
                // Record Step (Not interactive for rerun)
                StepView(title: "Record", icon: "mic.fill", isActive: false, isCompleted: true, isFailed: false)
                
                ArrowView()
                
                stepButton(title: "Upload Raw", icon: "arrow.up.doc.fill", step: .uploadingRaw)
                ArrowView()
                stepButton(title: "Transcode", icon: "waveform", step: .transcoding)
                ArrowView()
                stepButton(title: "Upload", icon: "icloud.and.arrow.up.fill", step: .uploading)
                ArrowView()
                stepButton(title: "Create Task", icon: "doc.badge.plus", step: .created)
                ArrowView()
                stepButton(title: "Poll", icon: "arrow.triangle.2.circlepath", step: .polling)
            }
            .padding(.vertical, 20)
            .padding(.horizontal, 10)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .cornerRadius(16)
            
            // Action Area
            VStack(spacing: 16) {
                if let error = manager.errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(error)
                    }
                    .foregroundColor(.red)
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                }
                
                if manager.isProcessing {
                    ProgressView("Processing...")
                        .controlSize(.large)
                } else {
                    actionButton
                        .controlSize(.large)
                }
            }
            
            if manager.task.status == .completed {
                Button(action: {
                    if let callback = onViewResult {
                        callback()
                    } else {
                        showingResult = true
                    }
                }) {
                    HStack {
                        Text("View Result")
                        Image(systemName: "chevron.right")
                    }
                    .frame(maxWidth: 200)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
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
    
    @ViewBuilder
    private func stepButton(title: String, icon: String, step: MeetingTaskStatus) -> some View {
        let canRerun = manager.task.status == .completed || manager.task.status == .failed
        
        if canRerun {
            Button(action: {
                stepToRerun = step
                showRerunAlert = true
            }) {
                StepView(
                    title: title,
                    icon: icon,
                    isActive: isStepActive(step),
                    isCompleted: isAfter(step),
                    isFailed: isFailed(step)
                )
                .contentShape(Rectangle()) // Make sure the whole area is clickable
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentColor, lineWidth: 0) // Placeholder for hover effect if needed
                )
            }
            .buttonStyle(.plain)
            .onHover { inside in
                if inside {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .help("Click to rerun this step")
        } else {
            StepView(
                title: title,
                icon: icon,
                isActive: isStepActive(step),
                isCompleted: isAfter(step),
                isFailed: isFailed(step)
            )
        }
    }
    
    private func stepTitle(_ step: MeetingTaskStatus) -> String {
        switch step {
        case .uploadingRaw: return "Upload Raw"
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
            case .uploadingRaw: await manager.uploadOriginal()
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
        let order: [MeetingTaskStatus] = [.recorded, .uploadingRaw, .uploadedRaw, .transcoding, .transcoded, .uploading, .uploaded, .created, .polling, .completed]
        
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
        
        // Special case: .created status means Create Task step is completed
        if currentStatus == .created && status == .created { return true }
        
        guard let currentIndex = order.firstIndex(of: currentStatus),
              let targetIndex = order.firstIndex(of: status) else { return false }
        
        return currentIndex > targetIndex
    }
    
    private func isStepActive(_ step: MeetingTaskStatus) -> Bool {
        // 1. Exactly matching status (Running)
        if manager.task.status == step { return true }
        
        // 2. Waiting for next step (Manual mode readiness)
        switch (manager.task.status, step) {
        case (.recorded, .uploadingRaw): return true
        case (.uploadedRaw, .transcoding): return true
        case (.transcoded, .uploading): return true
        case (.uploaded, .created): return true
        case (.created, .polling): return true
        default: return false
        }
    }
    
    private func isFailed(_ step: MeetingTaskStatus) -> Bool {
        guard manager.task.status == .failed else { return false }
        return manager.task.failedStep == step
    }
    
    @ViewBuilder
    private var actionButton: some View {
        switch manager.task.status {
        case .recorded:
            Button("Start Processing") {
                Task { await manager.uploadOriginal() }
            }
            .buttonStyle(.borderedProminent)
            
        case .failed:
            VStack {
                if let failedStep = manager.task.failedStep {
                    Text("Failed at: \(failedStep.displayName)")
                        .foregroundColor(.red)
                        .font(.caption)
                    
                    Button("Retry \(failedStep.displayName)") {
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
            
        case .uploadingRaw:
            Text("Uploading Original...")
            
        case .uploadedRaw:
            Button("Start Transcode") {
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
            
        case .uploaded:
             Button(settings.asrProvider == .volcengine ? "Create Volcengine Task" : "Create Tingwu Task") {
                 Task { await manager.createTask() }
             }
             .buttonStyle(.borderedProminent)
             
        case .created:
             Button("Start Polling") {
                 Task { await manager.pollStatus() }
             }
             .buttonStyle(.bordered)
             
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
            .foregroundColor(foregroundOrigin)
            .frame(width: 40, height: 40)
            .background(Circle().fill(backgroundOrigin))
            
            Text(title)
                .font(.caption)
                .foregroundColor(textOrigin)
        }
        .frame(width: 80)
    }
    
    private var foregroundOrigin: Color {
        if isFailed { return .red }
        if isCompleted { return .green }
        if isActive { return .blue }
        return .gray
    }
    
    private var backgroundOrigin: Color {
        if isFailed { return Color.red.opacity(0.1) }
        if isCompleted { return Color.green.opacity(0.1) }
        if isActive { return Color.blue.opacity(0.1) }
        return Color.gray.opacity(0.1)
    }
    
    private var textOrigin: Color {
        if isFailed { return .red }
        if isCompleted { return .primary }
        if isActive { return .blue }
        return .secondary
    }
}

struct ArrowView: View {
    var body: some View {
        Image(systemName: "arrow.right")
            .foregroundColor(.gray)
            .frame(width: 20)
    }
}
