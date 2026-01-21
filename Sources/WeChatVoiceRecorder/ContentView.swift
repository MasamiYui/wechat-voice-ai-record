import SwiftUI
import ScreenCaptureKit

struct ContentView: View {
    @ObservedObject var settings: SettingsStore
    @StateObject private var recorder: AudioRecorder
    @StateObject private var historyStore = HistoryStore()
    
    @State private var selectedTask: MeetingTask?
    @State private var isRecordingMode = true
    @State private var isShowingSettings = false
    
    init(settings: SettingsStore) {
        self.settings = settings
        _recorder = StateObject(wrappedValue: AudioRecorder(settings: settings))
    }
    
    var body: some View {
        NavigationSplitView {
            HistoryView(store: historyStore, selectedTask: $selectedTask, isRecordingMode: $isRecordingMode)
        } detail: {
            if isRecordingMode {
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
                    isShowingSettings = true
                }) {
                    Image(systemName: "gear")
                }
                .disabled(recorder.isRecording)
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView(settings: settings)
        }
        .onChange(of: selectedTask) { newTask in
            if newTask != nil {
                isRecordingMode = false
            }
        }
        .onChange(of: isRecordingMode) { newValue in
            if newValue {
                selectedTask = nil
            }
        }
        .onChange(of: recorder.latestTask?.id) { _ in
            // Refresh history when a new task is created
            historyStore.refresh()
        }
        .frame(minWidth: 900, minHeight: 600)
    }
}
