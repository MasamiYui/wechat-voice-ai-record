import Foundation
import Combine

class StorageManager: ObservableObject {
    static let shared = StorageManager()
    
    @Published var currentProvider: StorageProvider
    @Published var isSyncing: Bool = false
    @Published var syncProgress: Double = 0
    @Published var syncError: String?
    
    private var settingsStore: SettingsStore?
    private var cancellables = Set<AnyCancellable>()
    
    private let sqliteProvider = SQLiteStorage()
    private var mysqlProvider: MySQLStorage?
    
    private init() {
        self.currentProvider = sqliteProvider
    }
    
    func setup(settings: SettingsStore) {
        self.settingsStore = settings
        
        // Listen to storage type changes
        settings.$storageType
            .sink { [weak self] type in
                self?.switchProvider(to: type)
            }
            .store(in: &cancellables)
            
        // Listen to MySQL config changes to update the provider
        settings.objectWillChange
            .sink { [weak self] _ in
                // Debounce or just check if relevant fields changed?
                // For simplicity, we can update on next access or lazily.
                // But if we are currently using MySQL, we might need to reconnect.
                if self?.settingsStore?.storageType == .mysql {
                    self?.updateMySQLProvider()
                }
            }
            .store(in: &cancellables)
            
        // Initial setup
        switchProvider(to: settings.storageType)
    }
    
    private func switchProvider(to type: SettingsStore.StorageType) {
        switch type {
        case .local:
            mysqlProvider?.shutdown()
            mysqlProvider = nil
            currentProvider = sqliteProvider
        case .mysql:
            updateMySQLProvider()
            if let mysql = mysqlProvider {
                currentProvider = mysql
            }
        }
    }
    
    func updateMySQLProvider() {
        guard let settings = settingsStore else { return }
        mysqlProvider?.shutdown()
        let config = MySQLStorage.Config(
            host: settings.mysqlHost,
            port: settings.mysqlPort,
            user: settings.mysqlUser,
            password: settings.getMySQLPassword() ?? "",
            database: settings.mysqlDatabase
        )
        mysqlProvider = MySQLStorage(config: config)
        mysqlProvider?.logger = { [weak self] msg in
            self?.settingsStore?.log(msg)
        }
        if settings.storageType == .mysql {
            currentProvider = mysqlProvider!
            Task {
                try? await mysqlProvider?.createTableIfNeeded()
            }
        }
    }
    
    func testMySQLConnection() async throws {
        // Create a temporary provider to test connection
        guard let settings = settingsStore else { 
            throw NSError(domain: "StorageManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Settings not initialized"])
        }
        let config = MySQLStorage.Config(
            host: settings.mysqlHost,
            port: settings.mysqlPort,
            user: settings.mysqlUser,
            password: settings.getMySQLPassword() ?? "",
            database: settings.mysqlDatabase
        )
        let provider = MySQLStorage(config: config)
        provider.logger = { [weak self] msg in
            self?.settingsStore?.log(msg)
        }
        defer { provider.shutdown() }
        // Try to create table to test connection and permissions
        try await provider.createTableIfNeeded()
    }
    
    func syncToMySQL() async {
        // Always ensure we have the latest config for sync
        updateMySQLProvider()
        
        guard let mysql = mysqlProvider else {
            await MainActor.run {
                syncError = "MySQL configuration invalid"
            }
            return
        }
        
        await MainActor.run {
            isSyncing = true
            syncProgress = 0
            syncError = nil
        }
        
        do {
            // Ensure table exists
            try await mysql.createTableIfNeeded()
            
            // Fetch local tasks
            let localTasks = try await sqliteProvider.fetchTasks()
            let total = Double(localTasks.count)
            
            if total == 0 {
                await MainActor.run {
                    syncProgress = 1.0
                }
            } else {
                for (index, task) in localTasks.enumerated() {
                    // Check if exists
                    if let _ = try await mysql.getTask(id: task.id) {
                        // Skip if exists (Strategy A)
                    } else {
                        try await mysql.saveTask(task)
                    }
                    
                    await MainActor.run {
                        syncProgress = Double(index + 1) / total
                    }
                }
            }
            
        } catch {
            await MainActor.run {
                syncError = error.localizedDescription
            }
        }
        
        await MainActor.run {
            isSyncing = false
        }
    }
}
