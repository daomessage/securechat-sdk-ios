import Foundation

// ══════════════════════════════════════════════════════════════════════════
// MARK: - SecureChatSDK 公开导出
// ══════════════════════════════════════════════════════════════════════════
//
// 这个文件定义了 SDK 的公开 API，用户只需导入这个模块即可使用所有功能
//

// ──────────────────────────────────────────────────────────────────────────
// MARK: - 主入口
// ──────────────────────────────────────────────────────────────────────────

public let SecureChat = SecureChatClient.shared()

// ──────────────────────────────────────────────────────────────────────────
// MARK: - 数据模型
// ──────────────────────────────────────────────────────────────────────────

// 消息和会话
public typealias Message = StoredMessage
public typealias Session = SessionRecord
// 注：公开 API 的 `Identity` 指向 `KeyDerivation.Identity`（派生产物，含两对密钥，仅驻内存）
// 持久化请使用 `StoredIdentity`（仅公钥 + 元数据，助记词走 Keychain）
// 这里不再 `typealias Identity = StoredIdentity`，避免与 KeyDerivation.Identity 冲突

// 好友和联系人
public typealias Friend = FriendProfile
public typealias User = UserProfile

// 频道
public typealias Channel = ChannelInfo
public typealias Post = ChannelPost

// 靓号
public typealias Vanity = VanityItem

// ──────────────────────────────────────────────────────────────────────────
// MARK: - 核心密钥函数（供 AI Vibe Coding 使用）
// ──────────────────────────────────────────────────────────────────────────

/// 生成新的 12 词助记词
public func generateMnemonic() -> String {
    return KeyDerivation.newMnemonic()
}

/// 验证助记词
public func validateMnemonic(_ mnemonic: String) -> Bool {
    return KeyDerivation.validateMnemonic(mnemonic)
}

/// 派生身份（从助记词，含两对密钥；私钥只驻内存，不落盘）
public func deriveIdentity(mnemonic: String) throws -> Identity {
    return try KeyDerivation.deriveIdentity(mnemonic: mnemonic)
}

/// 从派生产物 + 服务端分配的 uuid/aliasId 生成持久化元数据（只含公钥）
public func makeStoredIdentity(
    from identity: Identity,
    uuid: String,
    aliasId: String,
    nickname: String
) -> StoredIdentity {
    return StoredIdentity(
        uuid: uuid,
        aliasId: aliasId,
        nickname: nickname,
        mnemonic: identity.mnemonic,
        signingPublicKey: identity.signingKey.publicKey.base64EncodedString(),
        ecdhPublicKey: identity.ecdhKey.publicKey.base64EncodedString()
    )
}

/// 计算安全码（防 MITM）
public func computeSecurityCode(myPublicKey: Data, theirPublicKey: Data) -> String {
    return KeyDerivation.computeSecurityCode(myEcdhPublicKey: myPublicKey, theirEcdhPublicKey: theirPublicKey)
}

// ──────────────────────────────────────────────────────────────────────────
// MARK: - 版本信息
// ──────────────────────────────────────────────────────────────────────────

public struct SecureChatSDK {
    public static let version = "1.0.0"
    public static let protocolVersion = "1.0"
    public static let apiBase = "https://relay.daomessage.com"

    /// SDK 信息
    public static var info: String {
        return """
        SecureChat SDK for iOS
        Version: \(version)
        Protocol: \(protocolVersion)
        API Base: \(apiBase)
        """
    }
}
