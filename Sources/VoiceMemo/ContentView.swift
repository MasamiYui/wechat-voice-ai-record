import SwiftUI
import ScreenCaptureKit

struct ContentView: View {
    @ObservedObject var settings: SettingsStore
    @StateObject private var recorder: AudioRecorder
    @StateObject private var historyStore = HistoryStore()
    
    @State private var selectedTask: MeetingTask?
    @State private var isRecordingMode = true
    @State private var isSettingsMode = false
    
    init(settings: SettingsStore) {
        self.settings = settings
        _recorder = StateObject(wrappedValue: AudioRecorder(settings: settings))
    }
    
    var body: some View {
        NavigationSplitView {
            HistoryView(store: historyStore, selectedTask: $selectedTask, isRecordingMode: $isRecordingMode)
        } detail: {
            if isSettingsMode {
                SettingsView(settings: settings)
            } else if isRecordingMode {
                RecordingView(recorder: recorder, settings: settings)
            } else if let task = selectedTask {
                ResultView(task: task, settings: settings)
                    .id(task.id) // Force refresh when switching tasks
            } else {
                Text("Select a meeting or start a new recording")
                    .foregroundColor(.secondary)
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: {
                    isSettingsMode = true
                    isRecordingMode = false
                    selectedTask = nil
                }) {
                    Image(systemName: "gear")
                }
                .disabled(recorder.isRecording)
            }
        }
        .onChange(of: selectedTask) { newTask in
            if newTask != nil {
                isRecordingMode = false
                isSettingsMode = false
            }
        }
        .onChange(of: isRecordingMode) { newValue in
            if newValue {
                selectedTask = nil
                isSettingsMode = false
            }
        }
        .onChange(of: recorder.latestTask?.id) { _ in
            // Refresh history when a new task is created
            Task { await historyStore.refresh() }
        }
        .frame(minWidth: 900, minHeight: 600)
    }
}
