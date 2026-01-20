import Foundation
import Combine

class SettingsStore: ObservableObject {
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
    @Published var enableVerboseLogging: Bool {
        didSet { UserDefaults.standard.set(enableVerboseLogging, forKey: "enableVerboseLogging") }
    }
    
    // Secrets (In-memory placeholders, real values in Keychain)
    @Published var hasAccessKeyId: Bool = false
    @Published var hasAccessKeySecret: Bool = false
    
    private let logQueue = DispatchQueue(label: "com.wechatvoicerecorder.log")
    
    init() {
        self.ossRegion = UserDefaults.standard.string(forKey: "ossRegion") ?? "cn-beijing"
        self.ossBucket = UserDefaults.standard.string(forKey: "ossBucket") ?? "wechat-record"
        self.ossPrefix = UserDefaults.standard.string(forKey: "ossPrefix") ?? "wvr/"
        self.ossEndpoint = UserDefaults.standard.string(forKey: "ossEndpoint") ?? "https://oss-cn-beijing.aliyuncs.com"
        
        self.tingwuAppKey = UserDefaults.standard.string(forKey: "tingwuAppKey") ?? ""
        self.language = UserDefaults.standard.string(forKey: "tingwuLanguage") ?? "cn"
        
        self.enableSummary = UserDefaults.standard.object(forKey: "enableSummary") as? Bool ?? true
        self.enableKeyPoints = UserDefaults.standard.object(forKey: "enableKeyPoints") as? Bool ?? true
        self.enableActionItems = UserDefaults.standard.object(forKey: "enableActionItems") as? Bool ?? true
        self.enableRoleSplit = UserDefaults.standard.object(forKey: "enableRoleSplit") as? Bool ?? true
        self.enableVerboseLogging = UserDefaults.standard.object(forKey: "enableVerboseLogging") as? Bool ?? false
        
        checkSecrets()
    }
    
    func checkSecrets() {
        hasAccessKeyId = KeychainHelper.shared.readString(account: "aliyun_ak_id") != nil
        hasAccessKeySecret = KeychainHelper.shared.readString(account: "aliyun_ak_secret") != nil
    }
    
    func saveAccessKeyId(_ value: String) {
        KeychainHelper.shared.save(value, account: "aliyun_ak_id")
        checkSecrets()
    }
    
    func saveAccessKeySecret(_ value: String) {
        KeychainHelper.shared.save(value, account: "aliyun_ak_secret")
        checkSecrets()
    }
    
    func getAccessKeyId() -> String? {
        return KeychainHelper.shared.readString(account: "aliyun_ak_id")
    }
    
    func getAccessKeySecret() -> String? {
        return KeychainHelper.shared.readString(account: "aliyun_ak_secret")
    }
    
    func clearSecrets() {
        KeychainHelper.shared.delete(account: "aliyun_ak_id")
        KeychainHelper.shared.delete(account: "aliyun_ak_secret")
        checkSecrets()
    }
    
    func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)"
        print(line) // 同时输出到控制台方便调试
        
        guard enableVerboseLogging || message.contains("error") || message.contains("failed") || message.contains("test") else { return }
        
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
        let url = logFileURL()
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }
    
    func clearLogFile() {
        let url = logFileURL()
        try? FileManager.default.removeItem(at: url)
    }
    
    func logFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("WeChatVoiceRecorder/Logs/app.log")
    }
}
