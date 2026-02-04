import SwiftUI
import ScreenCaptureKit

struct ContentView: View {
    @ObservedObject var settings: SettingsStore
    @StateObject private var recorder: AudioRecorder
    @StateObject private var historyStore = HistoryStore()
    
    // Navigation State
    @State private var selectedSidebarItem: SidebarItem? = .history
    @State private var selectedRecordingMode: RecordingModeItem?
    @State private var selectedImportMode: ImportModeItem?
    @State private var selectedSettingsCategory: SettingsCategory? = .general
    @State private var selectedTask: MeetingTask?
    
    // Import State
    @State private var isImporting = false
    @State private var importError: String?
    
    init(settings: SettingsStore) {
        self.settings = settings
        _recorder = StateObject(wrappedValue: AudioRecorder(settings: settings))
    }
    
    // Method to navigate to a task in history
    func navigateToTask(_ task: MeetingTask) {
        selectedSidebarItem = .history
        selectedTask = task
    }
    
    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selectedSidebarItem) { item in
                NavigationLink(value: item) {
                    Label(item.title, systemImage: item.icon)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Voice Memo")
            .frame(minWidth: 200, idealWidth: 220, maxWidth: 280)
        } content: {
            ZStack {
                if let item = selectedSidebarItem {
                    switch item {
                    case .recording:
                        List(RecordingModeItem.allCases, selection: $selectedRecordingMode) { mode in
                            NavigationLink(value: mode) {
                                VStack(alignment: .leading) {
                                    Label(mode.title, systemImage: mode.icon)
                                    Text(mode.description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .navigationTitle("New Recording")
                        
                    case .importAudio:
                        List(ImportModeItem.allCases, selection: $selectedImportMode) { mode in
                            NavigationLink(value: mode) {
                                VStack(alignment: .leading) {
                                    Label(mode.title, systemImage: mode.icon)
                                    Text(mode.description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .navigationTitle("Import")
                        
                    case .history:
                        HistoryListView(store: historyStore, selectedTask: $selectedTask)
                            .navigationTitle("History")
                        
                    case .settings:
                        List(SettingsCategory.allCases, selection: $selectedSettingsCategory) { category in
                            NavigationLink(value: category) {
                                VStack(alignment: .leading) {
                                    Label(category.title, systemImage: category.icon)
                                    Text(category.description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .navigationTitle("Settings")
                    }
                } else {
                    Text("Select an item")
                        .foregroundColor(.secondary)
                }
            }
            .navigationSplitViewColumnWidth(min: 250, ideal: 300, max: 400)
        } detail: {
            if let item = selectedSidebarItem {
                switch item {
                case .recording:
                    if let mode = selectedRecordingMode {
                        RecordingView(recorder: recorder, settings: settings, showModeSelection: false, onViewResult: {
                            if let task = recorder.latestTask {
                                navigateToTask(task)
                            }
                        })
                            .onAppear {
                                recorder.recordingMode = mode.mode
                            }
                            .onChange(of: mode) { newMode in
                                recorder.recordingMode = newMode.mode
                            }
                    } else {
                        Text("Select a recording mode")
                            .foregroundColor(.secondary)
                    }
                    
                case .importAudio:
                    if let mode = selectedImportMode {
                        switch mode {
                        case .file:
                            if isImporting {
                                VStack(spacing: 16) {
                                    ProgressView()
                                        .scaleEffect(1.5)
                                    Text("Importing...")
                                        .foregroundColor(.secondary)
                                }
                            } else {
                                ImportView { mode, files in
                                    handleImport(mode: mode, files: files)
                                }
                            }
                        }
                    } else {
                        Text("Select an import method")
                            .foregroundColor(.secondary)
                    }
                    
                case .history:
                    if let task = selectedTask {
                        ResultView(task: task, settings: settings)
                            .id(task.id)
                    } else {
                        Text("Select a meeting to view details")
                            .foregroundColor(.secondary)
                    }
                    
                case .settings:
                    if let category = selectedSettingsCategory {
                        SettingsView(settings: settings, category: category)
                    } else {
                        Text("Select a settings category")
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                Text("Welcome to Voice Memo")
                    .foregroundColor(.secondary)
            }
        }
        .frame(minWidth: 1000, minHeight: 600)
        .onChange(of: recorder.latestTask?.id) { _ in
            Task { await historyStore.refresh() }
        }
        .alert("Import Failed", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK") { }
        } message: {
            if let error = importError {
                Text(error)
            }
        }
    }
    
    private func handleImport(mode: MeetingMode, files: [URL]) {
        isImporting = true
        importError = nil
        
        Task {
            do {
                let newTask = try await historyStore.importTask(mode: mode, files: files)
                await MainActor.run {
                    isImporting = false
                    selectedSidebarItem = .history
                    selectedTask = newTask
                }
            } catch {
                await MainActor.run {
                    isImporting = false
                    importError = error.localizedDescription
                }
            }
        }
    }
}
