import Foundation
import Combine

class HistoryStore: ObservableObject {
    @Published var tasks: [MeetingTask] = []
    
    init() {
        Task { await refresh() }
    }
    
    @MainActor
    func refresh() async {
        do {
            tasks = try await StorageManager.shared.currentProvider.fetchTasks()
        } catch {
            print("HistoryStore refresh error: \(error)")
        }
    }
    
    func deleteTask(at offsets: IndexSet) {
        let tasksToDelete = offsets.map { tasks[$0] }
        Task {
            for task in tasksToDelete {
                try? await StorageManager.shared.currentProvider.deleteTask(id: task.id)
            }
            await refresh()
        }
    }

    func deleteTask(_ task: MeetingTask) {
        Task {
            try? await StorageManager.shared.currentProvider.deleteTask(id: task.id)
            await refresh()
        }
    }

    func deleteTasks(_ tasks: [MeetingTask]) {
        Task {
            for task in tasks {
                try? await StorageManager.shared.currentProvider.deleteTask(id: task.id)
            }
            await refresh()
        }
    }

    func updateTitle(for task: MeetingTask, newTitle: String) {
        Task {
            try? await StorageManager.shared.currentProvider.updateTaskTitle(id: task.id, newTitle: newTitle)
            await refresh()
        }
    }
    
    func importAudio(from sourceURL: URL) async throws -> MeetingTask {
        // 1. Generate unique ID and path
        let uuid = UUID().uuidString
        let fileExt = sourceURL.pathExtension
        let fileName = "\(uuid).\(fileExt)"
        
        let recordingsDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("VoiceMemo/recordings")
        
        try FileManager.default.createDirectory(at: recordingsDir, withIntermediateDirectories: true)
        
        let destinationURL = recordingsDir.appendingPathComponent(fileName)
        
        // 2. Copy file
        // Start accessing security scoped resource if needed (for user selected files)
        let startAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if startAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }
        
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        
        // 3. Create Task
        let title = sourceURL.deletingPathExtension().lastPathComponent
        let task = MeetingTask(recordingId: uuid, localFilePath: destinationURL.path, title: title)
        
        // 4. Save
        try await StorageManager.shared.currentProvider.saveTask(task)
        await refresh()
        
        return task
    }
}
