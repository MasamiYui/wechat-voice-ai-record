import Foundation
import Security

class KeychainHelper {
    static let shared = KeychainHelper()
    private let service = "com.wechatvoicerecorder.secrets"
    
    private init() {}
    
    func save(_ data: Data, account: String) {
        let query = [
            kSecValueData: data,
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ] as CFDictionary
        
        // Delete existing item first
        SecItemDelete(query)
        
        // Add new item
        let status = SecItemAdd(query, nil)
        if status != errSecSuccess {
            print("Keychain save error: \(status)")
        }
    }
    
    func read(account: String) -> Data? {
        let query = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ] as CFDictionary
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query, &dataTypeRef)
        
        if status == errSecSuccess {
            return dataTypeRef as? Data
        }
        return nil
    }
    
    func delete(account: String) {
        let query = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ] as CFDictionary
        
        SecItemDelete(query)
    }
    
    // String helpers
    func save(_ string: String, account: String) {
        if let data = string.data(using: .utf8) {
            save(data, account: account)
        }
    }
    
    func readString(account: String) -> String? {
        if let data = read(account: account) {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }
}
