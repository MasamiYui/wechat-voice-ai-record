import Foundation
import Combine

class SettingsStore: ObservableObject {
    // Storage Config
    enum StorageType: String, CaseIterable, Identifiable {
        case local
        case mysql
        var id: String { self.rawValue }
    }
    
    // ASR Provider Config
    enum ASRProvider: String, CaseIterable, Identifiable {
        case tingwu
        case volcengine
        var id: String { self.rawValue }
    }

    enum AppTheme: String, CaseIterable, Identifiable {
        case system
        case light
        case dark
        var id: String { self.rawValue }
    }
    
    @Published var storageType: StorageType {
        didSet { UserDefaults.standard.set(storageType.rawValue, forKey: "storageType") }
    }
    
    @Published var asrProvider: ASRProvider {
        didSet { UserDefaults.standard.set(asrProvider.rawValue, forKey: "asrProvider") }
    }

    @Published var appTheme: AppTheme {
        didSet { UserDefaults.standard.set(appTheme.rawValue, forKey: "appTheme") }
    }
    
    // MySQL Config
    @Published var mysqlHost: String {
        didSet { UserDefaults.standard.set(mysqlHost, forKey: "mysqlHost") }
    }
    @Published var mysqlPort: Int {
        didSet { UserDefaults.standard.set(mysqlPort, forKey: "mysqlPort") }
    }
    @Published var mysqlUser: String {
        didSet { UserDefaults.standard.set(mysqlUser, forKey: "mysqlUser") }
    }
    @Published var mysqlDatabase: String {
        didSet { UserDefaults.standard.set(mysqlDatabase, forKey: "mysqlDatabase") }
    }
    @Published var hasMySQLPassword: Bool = false
    
    // OSS Config
    @Published var ossRegion: String {
        didSet { UserDefaults.standard.set(ossRegion, forKey: "ossRegion") }
    }
    @Published var ossBucket: String {
        didSet { UserDefaults.standard.set(ossBucket, forKey: "ossBucket") }
    }
    @Published var ossPrefix: String {
        didSet { UserDefaults.standard.set(ossPrefix, forKey: "ossPrefix") }
    }
    @Published var ossEndpoint: String {
        didSet { UserDefaults.standard.set(ossEndpoint, forKey: "ossEndpoint") }
    }
    
    // Tingwu Config
    @Published var tingwuAppKey: String {
        didSet { UserDefaults.standard.set(tingwuAppKey, forKey: "tingwuAppKey") }
    }
    
    // Volcengine Config
    @Published var volcAppId: String {
        didSet { UserDefaults.standard.set(volcAppId, forKey: "volcAppId") }
    }
    @Published var volcResourceId: String {
        didSet { UserDefaults.standard.set(volcResourceId, forKey: "volcResourceId") }
    }
    
    @Published var language: String {
        didSet { UserDefaults.standard.set(language, forKey: "tingwuLanguage") }
    }
    
    // Feature Switches
    @Published var enableSummary: Bool {
        didSet { UserDefaults.standard.set(enableSummary, forKey: "enableSummary") }
    }
    @Published var enableKeyPoints: Bool {
        didSet { UserDefaults.standard.set(enableKeyPoints, forKey: "enableKeyPoints") }
    }
    @Published var enableActionItems: Bool {
        didSet { UserDefaults.standard.set(enableActionItems, forKey: "enableActionItems") }
    }
    @Published var enableRoleSplit: Bool {
        didSet { UserDefaults.standard.set(enableRoleSplit, forKey: "enableRoleSplit") }
    }
    @Published var speakerCount: Int {
        didSet { UserDefaults.standard.set(speakerCount, forKey: "speakerCount") }
    }
    @Published var enableVerboseLogging: Bool {
        didSet { UserDefaults.standard.set(enableVerboseLogging, forKey: "enableVerboseLogging") }
    }
    
    // Audio Recording Config
    @Published var savePathBookmark: Data? {
        didSet { UserDefaults.standard.set(savePathBookmark, forKey: "savePathBookmark") }
    }
    
    // Secrets (In-memory placeholders, real values in Keychain)
    @Published var hasTingwuAccessKeyId: Bool = false
    @Published var hasTingwuAccessKeySecret: Bool = false
    @Published var hasOSSAccessKeyId: Bool = false
    @Published var hasOSSAccessKeySecret: Bool = false
    @Published var hasVolcAccessToken: Bool = false
    
    private let logQueue = DispatchQueue(label: "cn.mistbit.voicememo.log")
    
    init() {
        self.storageType = StorageType(rawValue: UserDefaults.standard.string(forKey: "storageType") ?? "local") ?? .local
        self.asrProvider = ASRProvider(rawValue: UserDefaults.standard.string(forKey: "asrProvider") ?? "tingwu") ?? .tingwu
        self.appTheme = AppTheme(rawValue: UserDefaults.standard.string(forKey: "appTheme") ?? "system") ?? .system
        
        self.mysqlHost = UserDefaults.standard.string(forKey: "mysqlHost") ?? "localhost"
        let port = UserDefaults.standard.integer(forKey: "mysqlPort")
        self.mysqlPort = (port == 0) ? 3306 : port
        self.mysqlUser = UserDefaults.standard.string(forKey: "mysqlUser") ?? "root"
        self.mysqlDatabase = UserDefaults.standard.string(forKey: "mysqlDatabase") ?? "voicememo"
        
        self.ossRegion = UserDefaults.standard.string(forKey: "ossRegion") ?? "cn-beijing"
        self.ossBucket = UserDefaults.standard.string(forKey: "ossBucket") ?? "wechat-record"
        self.ossPrefix = UserDefaults.standard.string(forKey: "ossPrefix") ?? "wvr/"
        self.ossEndpoint = UserDefaults.standard.string(forKey: "ossEndpoint") ?? "https://oss-cn-beijing.aliyuncs.com"
        
        self.tingwuAppKey = UserDefaults.standard.string(forKey: "tingwuAppKey") ?? ""
        
        self.volcAppId = UserDefaults.standard.string(forKey: "volcAppId") ?? ""
        self.volcResourceId = UserDefaults.standard.string(forKey: "volcResourceId") ?? "volc.bigasr.auc"
        
        self.language = UserDefaults.standard.string(forKey: "tingwuLanguage") ?? "cn"
        
        self.enableSummary = UserDefaults.standard.object(forKey: "enableSummary") as? Bool ?? true
        self.enableKeyPoints = UserDefaults.standard.object(forKey: "enableKeyPoints") as? Bool ?? true
        self.enableActionItems = UserDefaults.standard.object(forKey: "enableActionItems") as? Bool ?? true
        self.enableRoleSplit = UserDefaults.standard.object(forKey: "enableRoleSplit") as? Bool ?? true
        let spkCount = UserDefaults.standard.integer(forKey: "speakerCount")
        self.speakerCount = (spkCount == 0) ? 2 : spkCount
        self.enableVerboseLogging = UserDefaults.standard.object(forKey: "enableVerboseLogging") as? Bool ?? false
        self.savePathBookmark = UserDefaults.standard.data(forKey: "savePathBookmark")
        
        migrateLegacySecrets()
        checkSecrets()
        log("SettingsStore initialized (system). Storage type: \(storageType), ASR Provider: \(asrProvider)")
    }
    
    private func migrateLegacySecrets() {
        // Migrate generic 'aliyun_ak_id' to specific 'tingwu_ak_id' and 'oss_ak_id' if they don't exist
        if let legacyId = KeychainHelper.shared.readString(account: "aliyun_ak_id") {
            if KeychainHelper.shared.readString(account: "tingwu_ak_id") == nil {
                KeychainHelper.shared.save(legacyId, account: "tingwu_ak_id")
            }
            if KeychainHelper.shared.readString(account: "oss_ak_id") == nil {
                KeychainHelper.shared.save(legacyId, account: "oss_ak_id")
            }
        }
        
        if let legacySecret = KeychainHelper.shared.readString(account: "aliyun_ak_secret") {
            if KeychainHelper.shared.readString(account: "tingwu_ak_secret") == nil {
                KeychainHelper.shared.save(legacySecret, account: "tingwu_ak_secret")
            }
            if KeychainHelper.shared.readString(account: "oss_ak_secret") == nil {
                KeychainHelper.shared.save(legacySecret, account: "oss_ak_secret")
            }
        }
    }
    
    func checkSecrets() {
        hasTingwuAccessKeyId = KeychainHelper.shared.readString(account: "tingwu_ak_id") != nil
        hasTingwuAccessKeySecret = KeychainHelper.shared.readString(account: "tingwu_ak_secret") != nil
        hasOSSAccessKeyId = KeychainHelper.shared.readString(account: "oss_ak_id") != nil
        hasOSSAccessKeySecret = KeychainHelper.shared.readString(account: "oss_ak_secret") != nil
        
        hasMySQLPassword = KeychainHelper.shared.readString(account: "mysql_password") != nil
        hasVolcAccessToken = KeychainHelper.shared.readString(account: "volc_access_token") != nil
    }
    
    func saveMySQLPassword(_ value: String) {
        KeychainHelper.shared.save(value, account: "mysql_password")
        checkSecrets()
    }
    
    func getMySQLPassword() -> String? {
        return KeychainHelper.shared.readString(account: "mysql_password")
    }
    
    func saveOSSAccessKeyId(_ value: String) {
        KeychainHelper.shared.save(value, account: "oss_ak_id")
        checkSecrets()
    }
    
    func saveOSSAccessKeySecret(_ value: String) {
        KeychainHelper.shared.save(value, account: "oss_ak_secret")
        checkSecrets()
    }
    
    func getOSSAccessKeyId() -> String? {
        return KeychainHelper.shared.readString(account: "oss_ak_id")
    }
    
    func getOSSAccessKeySecret() -> String? {
        return KeychainHelper.shared.readString(account: "oss_ak_secret")
    }
    
    func saveTingwuAccessKeyId(_ value: String) {
        KeychainHelper.shared.save(value, account: "tingwu_ak_id")
        checkSecrets()
    }
    
    func saveTingwuAccessKeySecret(_ value: String) {
        KeychainHelper.shared.save(value, account: "tingwu_ak_secret")
        checkSecrets()
    }
    
    func getTingwuAccessKeyId() -> String? {
        return KeychainHelper.shared.readString(account: "tingwu_ak_id")
    }
    
    func getTingwuAccessKeySecret() -> String? {
        return KeychainHelper.shared.readString(account: "tingwu_ak_secret")
    }
    
    func saveVolcAccessToken(_ value: String) {
        KeychainHelper.shared.save(value, account: "volc_access_token")
        checkSecrets()
    }
    
    func getVolcAccessToken() -> String? {
        return KeychainHelper.shared.readString(account: "volc_access_token")
    }
    
    func clearTingwuSecrets() {
        KeychainHelper.shared.delete(account: "tingwu_ak_id")
        KeychainHelper.shared.delete(account: "tingwu_ak_secret")
        checkSecrets()
    }
    
    func clearOSSSecrets() {
        KeychainHelper.shared.delete(account: "oss_ak_id")
        KeychainHelper.shared.delete(account: "oss_ak_secret")
        checkSecrets()
    }
    
    func clearVolcSecrets() {
        KeychainHelper.shared.delete(account: "volc_access_token")
        checkSecrets()
    }
    
    func clearSecrets() {
        clearTingwuSecrets()
        clearOSSSecrets()
        clearVolcSecrets()
        checkSecrets()
    }
    
    func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)"
        print(line) // 同时输出到控制台方便调试
        
        guard enableVerboseLogging || message.contains("error") || message.contains("failed") || message.contains("test") || message.contains("system") else { return }
        
        logQueue.async {
            let url = self.logFileURL()
            let dir = url.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if let data = (line + "\n").data(using: .utf8) {
                if FileManager.default.fileExists(atPath: url.path) {
                    if let handle = try? FileHandle(forWritingTo: url) {
                        _ = try? handle.seekToEnd()
                        try? handle.write(contentsOf: data)
                        try? handle.close()
                    }
                } else {
                    try? data.write(to: url)
                }
            }
        }
    }
    
    func readLogText() -> String {
        return readLogText(maxLines: 1000, filter: nil)
    }
    
    func readAllLogLines() -> [String] {
        var lines: [String] = []
        logQueue.sync {
            let url = logFileURL()
            guard let fullContent = try? String(contentsOf: url, encoding: .utf8) else {
                return
            }
            lines = fullContent.components(separatedBy: .newlines).reversed()
        }
        return lines
    }
    
    func readLogText(maxLines: Int, filter: String? = nil) -> String {
        var logContent = ""
        logQueue.sync {
            let url = logFileURL()
            guard let fullContent = try? String(contentsOf: url, encoding: .utf8) else {
                return
            }
            
            var lines = fullContent.components(separatedBy: .newlines)
            
            if let filter = filter, !filter.isEmpty {
                lines = lines.filter { $0.localizedCaseInsensitiveContains(filter) }
            }
            
            if lines.count > maxLines {
                lines = Array(lines.suffix(maxLines))
            }
            
            logContent = lines.joined(separator: "\n")
        }
        return logContent
    }
    
    func clearLogFile() {
        let url = logFileURL()
        try? FileManager.default.removeItem(at: url)
    }
    
    func logFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("VoiceMemo/Logs/app.log")
    }
    
    // MARK: - Save Path Management
    
    func getSavePath() -> URL {
        if let bookmark = savePathBookmark {
            var isStale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) {
                if isStale {
                    log("Warning: Save path bookmark is stale")
                    // If stale, we might need to recreate it, but we need a valid URL first.
                    // Usually we just use it and hope for the best or prompt user.
                }
                return url
            }
        }
        
        // Default: Downloads/VoiceMemoRecordings
        let fileManager = FileManager.default
        let downloads = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        return downloads.appendingPathComponent("VoiceMemoRecordings")
    }
    
    func setSavePath(_ url: URL) {
        do {
            let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            savePathBookmark = bookmark
            log("Updated save path to: \(url.path)")
        } catch {
            log("Failed to create bookmark for \(url.path): \(error)")
        }
    }
}
