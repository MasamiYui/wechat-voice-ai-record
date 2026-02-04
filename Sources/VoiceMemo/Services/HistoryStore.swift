import Foundation
import Combine

class HistoryStore: ObservableObject {
    @Published var tasks: [MeetingTask] = []
    @Published var isLoading = false
    @Published var error: Error?
    @Published var lastRefreshDate: Date?
    
    private var cancellables = Set<AnyCancellable>()
    private var notificationObserver: NSObjectProtocol?
    
    init() {
        // 使用传统的NotificationCenter监听方式
        notificationObserver = NotificationCenter.default.addObserver(
            forName: .meetingTaskDidUpdate,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            print("HistoryStore received meetingTaskDidUpdate notification: \(notification.object ?? "nil")")
            Task { await self.refresh() }
        }
        
        Task { await refresh() }
    }
    
    deinit {
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    @MainActor
    func refresh() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        
        do {
            tasks = try await StorageManager.shared.currentProvider.fetchTasks()
            lastRefreshDate = Date()
            print("HistoryStore refreshed successfully with \(tasks.count) tasks")
        } catch {
            self.error = error
            print("HistoryStore refresh error: \(error)")
        }
    }
    
    func deleteTask(at offsets: IndexSet) {
        let tasksToDelete = offsets.map { tasks[$0] }
        Task { @MainActor in
            do {
                for task in tasksToDelete {
                    try await StorageManager.shared.currentProvider.deleteTask(id: task.id)
                }
                await refresh()
            } catch {
                self.error = error
                print("HistoryStore delete error: \(error)")
            }
        }
    }

    func deleteTask(_ task: MeetingTask) {
        Task { @MainActor in
            do {
                try await StorageManager.shared.currentProvider.deleteTask(id: task.id)
                await refresh()
            } catch {
                self.error = error
                print("HistoryStore delete error: \(error)")
            }
        }
    }

    func deleteTasks(_ tasks: [MeetingTask]) {
        Task { @MainActor in
            do {
                for task in tasks {
                    try await StorageManager.shared.currentProvider.deleteTask(id: task.id)
                }
                await refresh()
            } catch {
                self.error = error
                print("HistoryStore delete error: \(error)")
            }
        }
    }

    func updateTitle(for task: MeetingTask, newTitle: String) {
        Task { @MainActor in
            do {
                try await StorageManager.shared.currentProvider.updateTaskTitle(id: task.id, newTitle: newTitle)
                await refresh()
            } catch {
                self.error = error
                print("HistoryStore update title error: \(error)")
            }
        }
    }
    
    func importTask(files: [URL]) async throws -> MeetingTask {
        guard !files.isEmpty else {
            throw NSError(domain: "HistoryStore", code: 400, userInfo: [NSLocalizedDescriptionKey: "No files provided"])
        }
        
        let uuid = UUID().uuidString
        let recordingsDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("VoiceMemo/recordings")
        
        try FileManager.default.createDirectory(at: recordingsDir, withIntermediateDirectories: true)
        
        let task = MeetingTask(recordingId: uuid, localFilePath: "", title: "")
        
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
        
        guard let url = files.first else { throw NSError(domain: "HistoryStore", code: 400, userInfo: [NSLocalizedDescriptionKey: "Missing file"]) }
        let dst = try copyFile(from: url, suffix: "")
        
        task.localFilePath = dst.path
        task.title = url.deletingPathExtension().lastPathComponent
        
        try await StorageManager.shared.currentProvider.saveTask(task)
        await refresh()
        
        return task
    }

    func importAudio(from sourceURL: URL) async throws -> MeetingTask {
        return try await importTask(files: [sourceURL])
    }
}
