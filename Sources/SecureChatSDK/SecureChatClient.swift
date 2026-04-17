import Foundation

/// ╔══════════════════════════════════════════════════════════════╗
/// ║         SecureChatClient — iOS SDK 门面                      ║
/// ╠══════════════════════════════════════════════════════════════╣
/// ║ 对标 Android SDK SecureChatClient                             ║
/// ║ 版本: 1.0.0  协议: SecureChat v1                             ║
/// ╚══════════════════════════════════════════════════════════════╝
///
/// ## 初始化和连接
/// ```swift
/// let client = SecureChatClient()
/// ```
///
/// ## 新用户注册
/// ```swift
/// let mnemonic = KeyDerivation.newMnemonic()
/// let aliasId = try await client.auth.registerAccount(mnemonic: mnemonic, nickname: "MyName")
/// await client.connect()
/// ```
///
/// ## 老用户恢复
/// ```swift
/// if let (aliasId, nickname) = try await client.restoreSession() {
///     await client.connect()
/// }
/// ```
///
/// ## 接收消息
/// ```swift
/// let id = await client.onMessage { msg in
///     print("消息: \(msg.text)")
/// }
/// // 清理时: await client.unsubscribe(id)
/// ```
///
/// ## 发送消息
/// ```swift
/// let msgId = try await client.sendMessage(
///     conversationId: "conv_id",
///     toAliasId: "u12345678",
///     text: "Hello E2EE!"
/// )
/// ```
///
/// 🛡️ 约束（不得修改）：
/// - API 地址硬编码，不接受外部参数
/// - 密钥派生路径 m/44'/0'/0'/0/0 和 m/44'/1'/0'/0/0 不可变更
/// - AES-GCM 信封格式不可变更（多端互通）

public final class SecureChatClient: Sendable {

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - 静态单例（可选，推荐使用实例）
    // ──────────────────────────────────────────────────────────────────────

    private static var instance: SecureChatClient?

    /// 获取或创建单例实例（可选 API）
    public static func shared() -> SecureChatClient {
        if let existing = instance {
            return existing
        }
        let client = SecureChatClient()
        instance = client
        return client
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - 内部组件
    // ──────────────────────────────────────────────────────────────────────

    private let http = HttpClient()
    private let transport: WSTransport
    private let database: Database
    private let messaging: MessageManager
    // 注：原先的 `eventListeners` 字段从未被使用，Sendable class 也不允许非隔离 var 存储属性，
    // 因此删除。事件订阅直接转发给 messaging actor。

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - 子模块（公开 API）
    // ──────────────────────────────────────────────────────────────────────

    /// 认证管理
    public private(set) var auth: AuthManager?

    /// 好友和联系人
    public private(set) var contacts: ContactsManager?

    /// 频道管理
    public private(set) var channels: ChannelsManager?

    /// 多媒体管理
    public private(set) var media: MediaManager?

    /// 推送管理
    public private(set) var push: PushManager?

    /// 靓号管理
    public private(set) var vanity: VanityManager?

    /// 安全模块（MITM 防御）
    public let security = SecurityModule()

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - 初始化
    // ──────────────────────────────────────────────────────────────────────

    public init() {
        self.transport = WSTransport()
        self.database = Database.shared()
        self.messaging = MessageManager(transport: transport, database: database, http: http)

        // 初始化子模块
        self.auth = AuthManager(http: http, database: database)
        self.contacts = ContactsManager(http: http, database: database)
        self.channels = ChannelsManager(http: http)
        self.media = MediaManager(http: http)
        self.push = PushManager(http: http)
        self.vanity = VanityManager(http: http)
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - 连接管理
    // ──────────────────────────────────────────────────────────────────────

    /// 建立 WebSocket 连接（注册/恢复会话后调用）
    public func connect() async {
        guard let auth = auth else { return }
        guard let uuid = await auth.internalUUID,
              let token = await http.getToken() else {
            return
        }
        await transport.connect(uuid: uuid, token: token)
    }

    /// 断开连接
    public func disconnect() async {
        await transport.disconnect()
    }

    /// 获取网络状态
    public var networkState: NetworkState {
        get async {
            await transport.networkState
        }
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - 会话恢复
    // ──────────────────────────────────────────────────────────────────────

    /// 恢复历史会话
    public func restoreSession() async throws -> (aliasId: String, nickname: String)? {
        return try await auth?.restoreSession()
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - 消息发送
    // ──────────────────────────────────────────────────────────────────────

    /// 发送文本消息
    public func sendMessage(
        conversationId: String,
        toAliasId: String,
        text: String,
        replyToId: String? = nil
    ) async throws -> String {
        return try await messaging.send(
            conversationId: conversationId,
            toAliasId: toAliasId,
            text: text,
            replyToId: replyToId
        )
    }

    /// 发送输入状态
    public func sendTyping(conversationId: String, toAliasId: String) async {
        await messaging.sendTyping(toAliasId: toAliasId, conversationId: conversationId)
    }

    /// 发送图片：先 MediaManager 加密上传，再 messaging 发媒体帧
    @discardableResult
    public func sendImage(
        conversationId: String,
        toAliasId: String,
        imageData: Data,
        replyToId: String? = nil
    ) async throws -> String {
        guard let media = self.media else { throw SDKError.sessionNotFound("MediaManager 未初始化") }
        let mediaKey = try await media.uploadImage(conversationId: conversationId, imageData: imageData)
        return try await messaging.sendMedia(
            conversationId: conversationId,
            toAliasId: toAliasId,
            msgType: "image",
            mediaKey: mediaKey,
            caption: nil,
            replyToId: replyToId
        )
    }

    /// 发送文件
    @discardableResult
    public func sendFile(
        conversationId: String,
        toAliasId: String,
        fileData: Data,
        fileName: String,
        replyToId: String? = nil
    ) async throws -> String {
        guard let media = self.media else { throw SDKError.sessionNotFound("MediaManager 未初始化") }
        let mediaKey = try await media.uploadFile(fileData: fileData, conversationId: conversationId, fileName: fileName)
        return try await messaging.sendMedia(
            conversationId: conversationId,
            toAliasId: toAliasId,
            msgType: "file",
            mediaKey: mediaKey,
            caption: fileName,
            replyToId: replyToId
        )
    }

    /// 发送语音
    @discardableResult
    public func sendVoice(
        conversationId: String,
        toAliasId: String,
        audioData: Data,
        durationMs: Int,
        replyToId: String? = nil
    ) async throws -> String {
        guard let media = self.media else { throw SDKError.sessionNotFound("MediaManager 未初始化") }
        let mediaKey = try await media.uploadVoice(audioData: audioData, conversationId: conversationId, durationMs: durationMs)
        return try await messaging.sendMedia(
            conversationId: conversationId,
            toAliasId: toAliasId,
            msgType: "voice",
            mediaKey: mediaKey,
            caption: String(durationMs),
            replyToId: replyToId
        )
    }

    /// 撤回消息
    public func retractMessage(messageId: String, toAliasId: String, conversationId: String) async {
        await messaging.sendRetract(messageId: messageId, toAliasId: toAliasId, conversationId: conversationId)
    }

    /// 标记已读
    public func markAsRead(conversationId: String, maxSeq: Int64, toAliasId: String) async {
        await messaging.sendRead(conversationId: conversationId, seq: maxSeq, toAliasId: toAliasId)
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - 历史消息
    // ──────────────────────────────────────────────────────────────────────

    /// 获取会话历史
    public func getHistory(conversationId: String, limit: Int = 200, before: Int64? = nil) async throws -> [StoredMessage] {
        return try await messaging.getHistory(conversationId: conversationId, limit: limit, before: before)
    }

    /// 获取单条消息
    public func getMessage(_ messageId: String) async throws -> StoredMessage? {
        return try await messaging.getMessage(messageId)
    }

    /// 获取所有会话
    public func listSessions() async throws -> [SessionEntity] {
        return try await database.getAllSessions()
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - 事件订阅
    // ──────────────────────────────────────────────────────────────────────

    /// 订阅消息事件
    public func onMessage(_ handler: @Sendable @escaping (StoredMessage) -> Void) async -> UUID {
        let id = UUID()
        await messaging.setOnMessage(handler)
        return id
    }

    /// 订阅状态变更事件
    public func onStatusChange(_ handler: @Sendable @escaping (MessageStatusChange) -> Void) async -> UUID {
        let id = UUID()
        await messaging.setOnStatusChange(handler)
        return id
    }

    /// 订阅输入状态事件
    public func onTyping(_ handler: @Sendable @escaping (TypingEvent) -> Void) async -> UUID {
        let id = UUID()
        await messaging.setOnTyping(handler)
        return id
    }

    /// 订阅网络状态变更
    public func onNetworkStateChange(_ handler: @escaping (NetworkState) -> Void) -> UUID {
        return UUID()  // 简化版，完整版需要真正实现
    }

    /// 取消订阅
    public func unsubscribe(_ id: UUID) async {
        // 简化版，完整版需要真正实现
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - 登出和清理
    // ──────────────────────────────────────────────────────────────────────

    /// 登出（清除本地数据）
    public func logout() async throws {
        await disconnect()
        try await messaging.clearAllMessages()
        try await auth?.logout()
    }

    /// 清除指定会话的本地消息历史
    public func clearHistory(conversationId: String) async throws {
        try await database.clearMessages(conversationId: conversationId)
    }

    /// 查询服务端存储占用（字节）— GET /api/v1/storage/estimate
    public func getStorageEstimate() async throws -> StorageEstimate {
        return try await http.get("/api/v1/storage/estimate") as StorageEstimate
    }

    /// 获取本地身份的助记词（已登录账号才有）
    public func getMnemonic() async throws -> String? {
        return try await database.loadIdentity()?.mnemonic
    }

    /// 清空所有历史消息
    public func clearAllHistory() async throws {
        try await messaging.clearAllMessages()
    }

    /// 导出指定会话为 NDJSON（与 Android 行为对齐）
    public func exportConversation(conversationId: String) async throws -> String {
        return try await messaging.exportConversation(conversationId)
    }

    /// 导出全部会话为 NDJSON（按 sessionId 分隔）
    public func exportAllConversations() async throws -> String {
        let sessions = try await listSessions()
        var sb = ""
        for s in sessions {
            sb += "# === \(s.conversationId) ===\n"
            sb += try await messaging.exportConversation(s.conversationId)
        }
        return sb
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - 安全相关
    // ──────────────────────────────────────────────────────────────────────

    /// 获取安全码（用于 MITM 防御）
    public func getSecurityCode(conversationId: String) async throws -> SecurityCode {
        guard let session = try await database.loadSession(conversationId),
              let identity = try await database.loadIdentity() else {
            throw SDKError.sessionNotFound("未找到会话或身份")
        }

        let myEcdhKey = try CryptoModule.fromBase64(identity.ecdhPublicKey)
        let theirEcdhKey = try CryptoModule.fromBase64(session.theirEcdhPublicKey)

        return SecurityModule.getSecurityCode(
            contactId: session.theirAliasId,
            myEcdhPublicKey: myEcdhKey,
            theirEcdhPublicKey: theirEcdhKey
        )
    }
}
