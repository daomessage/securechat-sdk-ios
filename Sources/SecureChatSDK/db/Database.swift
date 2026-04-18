import Foundation

/// CoreData 数据库管理（对标 Android Room）
public actor Database {

    private static var instance: Database?

    private let fileManager = FileManager.default
    private let documentsPath: String
    private var identityData: StoredIdentity?
    private var sessions: [String: SessionEntity] = [:]
    private var messages: [String: MessageEntity] = [:]
    private var trusts: [String: TrustEntity] = [:]

    public static func shared() -> Database {
        if let instance = instance {
            return instance
        }
        let db = Database()
        Database.instance = db
        return db
    }

    init() {
        let paths = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
        self.documentsPath = (paths.first ?? "") + "/securechat"

        // 创建数据目录 — 附加 completeFileProtection 属性
        try? fileManager.createDirectory(atPath: documentsPath, withIntermediateDirectories: true)
        // 对整个目录设置 "complete" 文件保护等级（设备锁屏时加密）
        try? (URL(fileURLWithPath: documentsPath) as NSURL).setResourceValue(
            URLFileProtection.complete,
            forKey: .fileProtectionKey
        )
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - 身份存储（P1.10 加固：Keychain 存敏感字段，文件只存公钥/元数据）
    // ──────────────────────────────────────────────────────────────────────

    /// 保存身份
    /// - mnemonic 走 Keychain（设备解锁可用、不跟随 iCloud 漂移）
    /// - uuid / aliasId / nickname / 公钥 落文件（已启用 completeFileProtection）
    /// - 私钥从不落盘：每次需要时由 mnemonic 重新派生（与 TS/Android SDK 对齐）
    public func saveIdentity(_ identity: StoredIdentity) throws {
        self.identityData = identity

        // 1) 助记词存 Keychain（硬件支持设备自动绑定 TEE）
        if !identity.mnemonic.isEmpty {
            try KeychainStore.set(identity.mnemonic, for: .mnemonic)
        }

        // 2) 非敏感元数据落文件（mnemonic 占位为空，避免副本）
        let publicMeta = StoredIdentity(
            uuid: identity.uuid,
            aliasId: identity.aliasId,
            nickname: identity.nickname,
            mnemonic: "",            // 占位，实际走 Keychain
            signingPublicKey: identity.signingPublicKey,
            ecdhPublicKey: identity.ecdhPublicKey
        )
        let path = "\(documentsPath)/identity.json"
        let encoded = try JSONEncoder().encode(publicMeta)
        let writeOptions: Data.WritingOptions = [.atomic, .completeFileProtection]
        try encoded.write(to: URL(fileURLWithPath: path), options: writeOptions)
    }

    /// 加载身份（合并文件元数据 + Keychain 敏感字段）
    public func loadIdentity() throws -> StoredIdentity? {
        if let cached = identityData {
            return cached
        }
        let path = "\(documentsPath)/identity.json"
        guard fileManager.fileExists(atPath: path) else {
            return nil
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let meta = try JSONDecoder().decode(StoredIdentity.self, from: data)

        // 从 Keychain 取助记词
        let mnemonic = (try? KeychainStore.get(.mnemonic)) ?? ""

        let full = StoredIdentity(
            uuid: meta.uuid,
            aliasId: meta.aliasId,
            nickname: meta.nickname,
            mnemonic: mnemonic,
            signingPublicKey: meta.signingPublicKey,
            ecdhPublicKey: meta.ecdhPublicKey
        )
        self.identityData = full
        return full
    }

    /// 清除身份（同时清 Keychain 敏感项）
    public func clearIdentity() throws {
        self.identityData = nil
        let path = "\(documentsPath)/identity.json"
        try? fileManager.removeItem(atPath: path)
        try? KeychainStore.delete(.mnemonic)
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - 会话存储
    // ──────────────────────────────────────────────────────────────────────

    /// 保存会话
    public func saveSession(_ session: SessionEntity) throws {
        sessions[session.conversationId] = session
        try persistSessions()
    }

    /// 加载会话
    public func loadSession(_ conversationId: String) throws -> SessionEntity? {
        try loadSessionsFromDisk()
        return sessions[conversationId]
    }

    /// 获取所有会话
    public func getAllSessions() throws -> [SessionEntity] {
        try loadSessionsFromDisk()
        return Array(sessions.values)
    }

    /// 删除会话
    public func deleteSession(_ conversationId: String) throws {
        sessions.removeValue(forKey: conversationId)
        try persistSessions()
    }

    /// 标记会话已验证
    public func markSessionVerified(_ conversationId: String) throws {
        if var session = sessions[conversationId] {
            session.trustState = .verified
            sessions[conversationId] = session
            try persistSessions()
        }
    }

    private func persistSessions() throws {
        let path = "\(documentsPath)/sessions.json"
        let encoded = try JSONEncoder().encode(Array(sessions.values))
        try encoded.write(to: URL(fileURLWithPath: path))
    }

    private func loadSessionsFromDisk() throws {
        if !sessions.isEmpty {
            return  // Already loaded
        }
        let path = "\(documentsPath)/sessions.json"
        guard fileManager.fileExists(atPath: path) else {
            return
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let decoded = try JSONDecoder().decode([SessionEntity].self, from: data)
        for session in decoded {
            sessions[session.conversationId] = session
        }
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - 消息存储
    // ──────────────────────────────────────────────────────────────────────

    /// 保存消息
    public func saveMessage(_ message: MessageEntity) throws {
        messages[message.id] = message
        try persistMessages()
    }

    /// 加载消息
    public func loadMessage(_ messageId: String) throws -> MessageEntity? {
        try loadMessagesFromDisk()
        return messages[messageId]
    }

    /// 获取对话历史
    public func getMessageHistory(_ conversationId: String, limit: Int = 200, before: Int64? = nil) throws -> [MessageEntity] {
        try loadMessagesFromDisk()
        var result = messages.values.filter { $0.conversationId == conversationId }

        if let before = before {
            result = result.filter { $0.time < before }
        }

        result.sort { $0.time > $1.time }
        return Array(result.prefix(limit))
    }

    /// 清除所有消息
    public func clearAllMessages() throws {
        messages.removeAll()
        let path = "\(documentsPath)/messages.json"
        try? fileManager.removeItem(atPath: path)
    }

    /// 清除对话消息
    public func clearMessages(conversationId: String) throws {
        messages = messages.filter { $0.value.conversationId != conversationId }
        try persistMessages()
    }

    private func persistMessages() throws {
        let path = "\(documentsPath)/messages.json"
        let encoded = try JSONEncoder().encode(Array(messages.values))
        try encoded.write(to: URL(fileURLWithPath: path))
    }

    private func loadMessagesFromDisk() throws {
        if !messages.isEmpty {
            return  // Already loaded
        }
        let path = "\(documentsPath)/messages.json"
        guard fileManager.fileExists(atPath: path) else {
            return
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let decoded = try JSONDecoder().decode([MessageEntity].self, from: data)
        for message in decoded {
            messages[message.id] = message
        }
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - 信任存储
    // ──────────────────────────────────────────────────────────────────────

    /// 保存信任记录
    public func saveTrust(_ trust: TrustEntity) throws {
        trusts[trust.contactId] = trust
        try persistTrusts()
    }

    /// 加载信任记录
    public func loadTrust(_ contactId: String) throws -> TrustEntity? {
        try loadTrustsFromDisk()
        return trusts[contactId]
    }

    private func persistTrusts() throws {
        let path = "\(documentsPath)/trusts.json"
        let encoded = try JSONEncoder().encode(Array(trusts.values))
        try encoded.write(to: URL(fileURLWithPath: path))
    }

    private func loadTrustsFromDisk() throws {
        if !trusts.isEmpty {
            return
        }
        let path = "\(documentsPath)/trusts.json"
        guard fileManager.fileExists(atPath: path) else {
            return
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let decoded = try JSONDecoder().decode([TrustEntity].self, from: data)
        for trust in decoded {
            trusts[trust.contactId] = trust
        }
    }
}

// ──────────────────────────────────────────────────────────────────────────
// MARK: - 数据库实体
// ──────────────────────────────────────────────────────────────────────────

/// 会话实体
public struct SessionEntity: Codable, Equatable {
    public let conversationId: String
    public let theirAliasId: String
    public let theirEcdhPublicKey: String
    public var theirEd25519PublicKey: String?
    public let sessionKeyBase64: String
    public var trustState: TrustState
    public let createdAt: Int64

    public init(
        conversationId: String,
        theirAliasId: String,
        theirEcdhPublicKey: String,
        sessionKeyBase64: String,
        trustState: TrustState = .unverified,
        createdAt: Int64,
        theirEd25519PublicKey: String? = nil
    ) {
        self.conversationId = conversationId
        self.theirAliasId = theirAliasId
        self.theirEcdhPublicKey = theirEcdhPublicKey
        self.sessionKeyBase64 = sessionKeyBase64
        self.trustState = trustState
        self.createdAt = createdAt
        self.theirEd25519PublicKey = theirEd25519PublicKey
    }
}

/// 消息实体
public struct MessageEntity: Codable, Equatable {
    public let id: String
    public let conversationId: String
    public let text: String
    public let isMe: Bool
    public let time: Int64
    public var status: MessageStatus
    public var msgType: String?
    public var mediaUrl: String?
    public var caption: String?
    public var seq: Int64?
    public var fromAliasId: String?
    public var replyToId: String?

    public init(
        id: String,
        conversationId: String,
        text: String,
        isMe: Bool,
        time: Int64,
        status: MessageStatus = .sent,
        msgType: String? = nil,
        mediaUrl: String? = nil,
        caption: String? = nil,
        seq: Int64? = nil,
        fromAliasId: String? = nil,
        replyToId: String? = nil
    ) {
        self.id = id
        self.conversationId = conversationId
        self.text = text
        self.isMe = isMe
        self.time = time
        self.status = status
        self.msgType = msgType
        self.mediaUrl = mediaUrl
        self.caption = caption
        self.seq = seq
        self.fromAliasId = fromAliasId
        self.replyToId = replyToId
    }

    /// 转换为 StoredMessage
    public func toStoredMessage() -> StoredMessage {
        return StoredMessage(
            id: id,
            conversationId: conversationId,
            text: text,
            isMe: isMe,
            time: time,
            status: status,
            msgType: msgType,
            mediaUrl: mediaUrl,
            caption: caption,
            seq: seq,
            fromAliasId: fromAliasId,
            replyToId: replyToId
        )
    }
}

/// 信任实体
public struct TrustEntity: Codable, Equatable {
    public let contactId: String
    public var status: String
    public var verifiedAt: Int64?
    public var fingerprintSnapshot: String?

    public init(contactId: String, status: String, verifiedAt: Int64? = nil, fingerprintSnapshot: String? = nil) {
        self.contactId = contactId
        self.status = status
        self.verifiedAt = verifiedAt
        self.fingerprintSnapshot = fingerprintSnapshot
    }
}
