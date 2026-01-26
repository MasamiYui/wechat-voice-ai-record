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
    
    func importTask(mode: MeetingMode, files: [URL]) async throws -> MeetingTask {
        guard !files.isEmpty else {
            throw NSError(domain: "HistoryStore", code: 400, userInfo: [NSLocalizedDescriptionKey: "No files provided"])
        }
        
        let uuid = UUID().uuidString
        let recordingsDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("VoiceMemo/recordings")
        
        try FileManager.default.createDirectory(at: recordingsDir, withIntermediateDirectories: true)
        
        var task = MeetingTask(recordingId: uuid, localFilePath: "", title: "")
        task.mode = mode
        
        // Helper to safely copy file
        func copyFile(from src: URL, suffix: String) throws -> URL {
            let ext = src.pathExtension
            let fileName = "\(uuid)\(suffix).\(ext)"
            let dst = recordingsDir.appendingPathComponent(fileName)
            
            let startAccessing = src.startAccessingSecurityScopedResource()
            defer { if startAccessing { src.stopAccessingSecurityScopedResource() } }
            
            if FileManager.default.fileExists(atPath: dst.path) {
                try FileManager.default.removeItem(at: dst)
            }
            try FileManager.default.copyItem(at: src, to: dst)
            return dst
        }
        
        if mode == .mixed {
            guard let url = files.first else { throw NSError(domain: "HistoryStore", code: 400, userInfo: [NSLocalizedDescriptionKey: "Missing file"]) }
            let dst = try copyFile(from: url, suffix: "")
            
            task.localFilePath = dst.path
            task.title = url.deletingPathExtension().lastPathComponent
            
        } else {
            // Separated
            guard files.count >= 2 else { throw NSError(domain: "HistoryStore", code: 400, userInfo: [NSLocalizedDescriptionKey: "Missing files for separated mode"]) }
            let url1 = files[0]
            let url2 = files[1]
            
            let dst1 = try copyFile(from: url1, suffix: "-spk1")
            let dst2 = try copyFile(from: url2, suffix: "-spk2")
            
            task.speaker1AudioPath = dst1.path
            task.speaker2AudioPath = dst2.path
            task.localFilePath = dst1.path // Primary reference
            task.title = url1.deletingPathExtension().lastPathComponent
        }
        
        try await StorageManager.shared.currentProvider.saveTask(task)
        await refresh()
        
        return task
    }

    func importAudio(from sourceURL: URL) async throws -> MeetingTask {
        return try await importTask(mode: .mixed, files: [sourceURL])
    }
}
