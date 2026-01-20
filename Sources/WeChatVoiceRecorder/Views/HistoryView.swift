import SwiftUI

struct HistoryView: View {
    @ObservedObject var store: HistoryStore
    @Binding var selectedTask: MeetingTask?
    @Binding var isRecordingMode: Bool
    
    @State private var searchText = ""
    
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
                Label("New Recording", systemImage: "mic.circle.fill")
                    .font(.headline)
                    .foregroundColor(.accentColor)
                    .padding(.vertical, 4)
            }
            .tag(nil as MeetingTask?) // Special tag logic if needed, but button action handles it
            .buttonStyle(.plain)
            
            Section(header: Text("History")) {
                ForEach(filteredTasks) { task in
                    NavigationLink(value: task) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(task.title)
                                .font(.headline)
                            HStack {
                                Text(task.createdAt, style: .date)
                                Text(task.createdAt, style: .time)
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                            
                            StatusBadge(status: task.status)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .onDelete(perform: deleteItems)
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $searchText, placement: .sidebar)
        .navigationTitle("Meetings")
        .toolbar {
            Button(action: {
                store.refresh()
            }) {
                Image(systemName: "arrow.clockwise")
            }
        }
    }
    
    private func deleteItems(offsets: IndexSet) {
        store.deleteTask(at: offsets)
        if let selected = selectedTask, !store.tasks.contains(where: { $0.id == selected.id }) {
            selectedTask = nil
        }
    }
}

struct StatusBadge: View {
    let status: MeetingTaskStatus
    
    var color: Color {
        switch status {
        case .completed: return .green
        case .failed: return .red
        case .recorded: return .blue
        default: return .orange
        }
    }
    
    var body: some View {
        Text(status.rawValue.capitalized)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .cornerRadius(4)
    }
}
