import SwiftUI
import UniformTypeIdentifiers

struct HistoryView: View {
    @ObservedObject var store: HistoryStore
    @Binding var selectedTask: MeetingTask?
    @Binding var isRecordingMode: Bool
    
    @State private var searchText = ""
    @State private var pendingDeleteTask: MeetingTask?
    @State private var isShowingDeleteAlert = false
    @State private var taskToRename: MeetingTask?
    @State private var newTitle: String = ""
    @State private var isShowingRenameAlert = false
    
    var filteredTasks: [MeetingTask] {
        if searchText.isEmpty {
            return store.tasks
        } else {
            return store.tasks.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
        }
    }
    
    var body: some View {
        List(selection: $selectedTask) {
            // New Recording Button Item
            Button(action: {
                selectedTask = nil
                isRecordingMode = true
            }) {
                HStack {
                    if isRecordingMode {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 8, height: 8)
                    } else {
                        Circle()
                            .fill(Color.clear)
                            .frame(width: 8, height: 8)
                    }
                    
                    Label("New Recording", systemImage: "mic.circle.fill")
                        .font(.headline)
                        .foregroundColor(isRecordingMode ? .primary : .secondary)
                    
                    Spacer()
                }
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowBackground(isRecordingMode ? Color.gray.opacity(0.1) : Color.clear)
            
            // Import Audio Button Item
            Button(action: {
                openImportPanel()
            }) {
                HStack {
                    Circle()
                        .fill(Color.clear)
                        .frame(width: 8, height: 8)
                    
                    Label("Import Audio", systemImage: "square.and.arrow.down")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Spacer()
                }
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            Section(header: Text("History").font(.caption).foregroundColor(.secondary)) {
                ForEach(filteredTasks) { task in
                    NavigationLink(value: task) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(task.title)
                                .font(.system(.body, design: .default))
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            
                            HStack {
                                Text(task.createdAt, style: .date)
                                Text(task.createdAt, style: .time)
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                            
                            StatusBadge(status: task.status)
                        }
                        .padding(.vertical, 6)
                    }
                    .contextMenu {
                        Button {
                            taskToRename = task
                            newTitle = task.title
                            isShowingRenameAlert = true
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }

                        Divider()

                        Button(role: .destructive) {
                            pendingDeleteTask = task
                            isShowingDeleteAlert = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                .onDelete(perform: deleteItems)
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search")
        .navigationTitle("Meetings")
        .toolbar {
            Button(action: {
                Task { await store.refresh() }
            }) {
                Image(systemName: "arrow.clockwise")
            }
            if let selectedTask {
                Button(role: .destructive) {
                    pendingDeleteTask = selectedTask
                    isShowingDeleteAlert = true
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .alert("Delete Meeting?", isPresented: $isShowingDeleteAlert) {
            Button("Delete", role: .destructive) {
                if let task = pendingDeleteTask {
                    store.deleteTask(task)
                    if selectedTask?.id == task.id {
                        selectedTask = nil
                    }
                }
                pendingDeleteTask = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteTask = nil
            }
        } message: {
            Text("This action cannot be undone.")
        }
        .alert("Rename Meeting", isPresented: $isShowingRenameAlert) {
            TextField("New Title", text: $newTitle)
            Button("Save") {
                if let task = taskToRename, !newTitle.isEmpty {
                    store.updateTitle(for: task, newTitle: newTitle)
                    // If the currently selected task is the one being renamed, we might need to update the detail view's identity or just let the binding handle it if it's reactive enough.
                }
                taskToRename = nil
            }
            Button("Cancel", role: .cancel) {
                taskToRename = nil
            }
        }
    }
    
    private func openImportPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Import"
        panel.message = "Select an audio file to import"
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                Task {
                    do {
                        let newTask = try await store.importAudio(from: url)
                        await MainActor.run {
                            self.selectedTask = newTask
                            self.isRecordingMode = false
                        }
                    } catch {
                        print("Import failed: \(error)")
                    }
                }
            }
        }
    }
    
    private func deleteItems(offsets: IndexSet) {
        let tasksToDelete = offsets.compactMap { index in
            filteredTasks.indices.contains(index) ? filteredTasks[index] : nil
        }
        store.deleteTasks(tasksToDelete)
        if let selected = selectedTask, !store.tasks.contains(where: { $0.id == selected.id }) {
            selectedTask = nil
        }
    }
}

struct StatusBadge: View {
    let status: MeetingTaskStatus
    
    var backgroundColor: Color {
        switch status {
        case .completed: return .green
        case .failed: return .red
        case .recorded: return .blue
        case .transcoding, .uploading, .polling: return .orange
        default: return .gray
        }
    }
    
    var body: some View {
        Text(status.rawValue.capitalized)
            .font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(backgroundColor)
            .foregroundColor(.white)
            .cornerRadius(10)
    }
}
