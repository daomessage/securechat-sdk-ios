import Foundation
import Security

/// KeychainStore — iOS Keychain 存取助记词 / 私钥
///
/// 2026-04 加固（fix C5）：之前敏感字段明文写 `identity.json`，
/// 越狱 / iTunes backup 即可 dump。现走 Keychain
/// `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` — 设备解锁才能读、
/// 不进备份、不随 iCloud 同步。
public enum KeychainStore {

    public enum Key: String {
        case mnemonic           = "securechat.mnemonic"
        case signingPrivateKey  = "securechat.signingPrivateKey"
        case ecdhPrivateKey     = "securechat.ecdhPrivateKey"
    }

    private static let service = "com.daomessage.securechat"

    public enum KeychainError: Error {
        case encodingFailed
        case unhandled(OSStatus)
    }

    /// 写入（覆盖已存在项）
    public static func set(_ value: String, for key: Key) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
        // 先删除旧值
        SecItemDelete(query as CFDictionary)

        var newItem = query
        newItem[kSecValueData as String] = data
        newItem[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let status = SecItemAdd(newItem as CFDictionary, nil)
        if status != errSecSuccess {
            throw KeychainError.unhandled(status)
        }
    }

    /// 读取
    public static func get(_ key: Key) throws -> String {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return ""
        }
        if status != errSecSuccess {
            throw KeychainError.unhandled(status)
        }
        guard let data = item as? Data, let str = String(data: data, encoding: .utf8) else {
            return ""
        }
        return str
    }

    /// 删除
    public static func delete(_ key: Key) throws {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.unhandled(status)
        }
    }
}
