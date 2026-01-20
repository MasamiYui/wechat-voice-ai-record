import Foundation
import Combine

class HistoryStore: ObservableObject {
    @Published var tasks: [MeetingTask] = []
    
    init() {
        refresh()
    }
    
    func refresh() {
        tasks = DatabaseManager.shared.fetchTasks()
    }
    
    func deleteTask(at offsets: IndexSet) {
        for index in offsets {
            let task = tasks[index]
            DatabaseManager.shared.deleteTask(id: task.id)
        }
        refresh()
    }
}
