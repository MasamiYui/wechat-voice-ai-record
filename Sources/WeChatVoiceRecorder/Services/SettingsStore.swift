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
    
    // Secrets (In-memory placeholders, real values in Keychain)
    @Published var hasAccessKeyId: Bool = false
    @Published var hasAccessKeySecret: Bool = false
    
    init() {
        self.ossRegion = UserDefaults.standard.string(forKey: "ossRegion") ?? "oss-cn-beijing"
        self.ossBucket = UserDefaults.standard.string(forKey: "ossBucket") ?? "wechat-record"
        self.ossPrefix = UserDefaults.standard.string(forKey: "ossPrefix") ?? "wvr/"
        self.ossEndpoint = UserDefaults.standard.string(forKey: "ossEndpoint") ?? "https://oss-cn-beijing.aliyuncs.com"
        
        self.tingwuAppKey = UserDefaults.standard.string(forKey: "tingwuAppKey") ?? ""
        self.language = UserDefaults.standard.string(forKey: "tingwuLanguage") ?? "cn"
        
        self.enableSummary = UserDefaults.standard.object(forKey: "enableSummary") as? Bool ?? true
        self.enableKeyPoints = UserDefaults.standard.object(forKey: "enableKeyPoints") as? Bool ?? true
        self.enableActionItems = UserDefaults.standard.object(forKey: "enableActionItems") as? Bool ?? true
        self.enableRoleSplit = UserDefaults.standard.object(forKey: "enableRoleSplit") as? Bool ?? true
        
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
}
