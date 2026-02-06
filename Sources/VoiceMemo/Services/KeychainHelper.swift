import Foundation
import Security

class KeychainHelper {
    static let shared = KeychainHelper()
    private let service = "cn.mistbit.voicememo.secrets"
    
    private init() {}
    
    func save(_ data: Data, account: String) {
        // Query for deletion (no data)
        let deleteQuery = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ] as CFDictionary
        
        SecItemDelete(deleteQuery)
        
        // Query for adding (with data)
        let addQuery = [
            kSecValueData: data,
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ] as CFDictionary
        
        let status = SecItemAdd(addQuery, nil)
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
