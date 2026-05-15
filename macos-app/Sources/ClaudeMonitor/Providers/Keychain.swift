import Foundation
import Security

enum KeychainResult {
    case found(Data)
    case notFound
    case denied
    case error(OSStatus)
}

enum Keychain {
    static func readGenericPassword(service: String) -> KeychainResult {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            if let data = item as? Data { return .found(data) }
            return .error(status)
        case errSecItemNotFound:
            return .notFound
        case errSecAuthFailed, errSecUserCanceled, errSecInteractionNotAllowed:
            return .denied
        default:
            return .error(status)
        }
    }
}
