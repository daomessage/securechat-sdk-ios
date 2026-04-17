import Foundation

/// 消息管理器（对标 Android MessageManager）
public actor MessageManager {

    private let transport: WSTransport
    private let database: Database
    private let http: HttpClient

    public var onMessage: (@Sendable (StoredMessage) -> Void)?
    public var onStatusChange: (@Sendable (MessageStatusChange) -> Void)?
    public var onTyping: (@Sendable (TypingEvent) -> Void)?

    public func setOnMessage(_ handler: (@Sendable (StoredMessage) -> Void)?) {
        self.onMessage = handler
    }
    public func setOnStatusChange(_ handler: (@Sendable (MessageStatusChange) -> Void)?) {
        self.onStatusChange = handler
    }
    public func setOnTyping(_ handler: (@Sendable (TypingEvent) -> Void)?) {
        self.onTyping = handler
    }

    private var messageHandlerId: UUID?
    private var networkStateHandlerId: UUID?

    public init(transport: WSTransport, database: Database, http: HttpClient) {
        self.transport = transport
        self.database = database
        self.http = http
        // 在 actor 初始化后再设置跨 actor 的监听（避免从非隔离上下文调 actor 方法）
        Task { [weak self] in
            await self?.setupTransportListeners()
        }
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - 初始化
    // ──────────────────────────────────────────────────────────────────────

    private func setupTransportListeners() async {
        messageHandlerId = await transport.onMessage { [weak self] text in
            Task {
                await self?.handleFrame(text)
            }
        }
    }

    deinit {
        if let id = messageHandlerId {
            Task {
                await transport.unsubscribe(id)
            }
        }
        if let id = networkStateHandlerId {
            Task {
                await transport.unsubscribe(id)
            }
        }
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - 消息发送
    // ──────────────────────────────────────────────────────────────────────

    /// 发送文本消息
    public func send(conversationId: String, toAliasId: String, text: String, replyToId: String? = nil) async throws -> String {
        // 1. 获取会话
        let session = try await database.loadSession(conversationId)
        guard let session = session else {
            throw SDKError.sessionNotFound("未找到会话: \(conversationId)")
        }

        // 2. 解密会话密钥
        guard let sessionKeyData = Data(base64Encoded: session.sessionKeyBase64) else {
            throw SDKError.decryptionFailed("会话密钥解码失败")
        }

        // 3. 加密文本
        let encryptedText = try CryptoModule.encrypt(sessionKey: sessionKeyData, plaintext: text)

        // 4. 生成消息 ID
        let messageId = UUID().uuidString

        // 5. 生成 WS 帧
        var frame: [String: Any] = [
            "type": "message",
            "id": messageId,
            "from": "",  // 由服务端填充
            "to": toAliasId,
            "conv_id": conversationId,
            "text": encryptedText,
            "time": Int64(Date().timeIntervalSince1970 * 1000)
        ]

        if let replyToId = replyToId {
            frame["reply_to_id"] = replyToId
        }

        // 6. 发送
        if let jsonData = try? JSONSerialization.data(withJSONObject: frame),
           let jsonStr = String(data: jsonData, encoding: .utf8) {
            await transport.send(jsonStr)
        }

        // 7. 本地保存
        let storedMsg = StoredMessage(
            id: messageId,
            conversationId: conversationId,
            text: text,
            isMe: true,
            time: Int64(Date().timeIntervalSince1970 * 1000),
            status: .sending,
            replyToId: replyToId
        )

        let entity = MessageEntity(
            id: messageId,
            conversationId: conversationId,
            text: text,
            isMe: true,
            time: storedMsg.time,
            status: .sending,
            replyToId: replyToId
        )

        try await database.saveMessage(entity)
        onMessage?(storedMsg)

        return messageId
    }

    /// 发送富媒体（图片/文件/语音）— 已上传得到 mediaKey 后调用
    /// 帧格式与 Android SDK 对齐：text 字段填占位「[type]mediaKey」，msgType 标识类型
    public func sendMedia(
        conversationId: String,
        toAliasId: String,
        msgType: String,        // "image" | "file" | "voice"
        mediaKey: String,       // 已上传后服务端返回的密文 key
        caption: String? = nil, // 文件名 / 语音时长（毫秒）
        replyToId: String? = nil
    ) async throws -> String {
        let messageId = UUID().uuidString
        let placeholder = "[\(msgType)]\(mediaKey)"
        var frame: [String: Any] = [
            "type": "message",
            "id": messageId,
            "from": "",
            "to": toAliasId,
            "conv_id": conversationId,
            "text": placeholder,
            "msg_type": msgType,
            "media_url": placeholder,
            "time": Int64(Date().timeIntervalSince1970 * 1000)
        ]
        if let caption = caption { frame["caption"] = caption }
        if let replyToId = replyToId { frame["reply_to_id"] = replyToId }

        if let jsonData = try? JSONSerialization.data(withJSONObject: frame),
           let jsonStr = String(data: jsonData, encoding: .utf8) {
            await transport.send(jsonStr)
        }

        let storedMsg = StoredMessage(
            id: messageId,
            conversationId: conversationId,
            text: placeholder,
            isMe: true,
            time: Int64(Date().timeIntervalSince1970 * 1000),
            status: .sending,
            msgType: msgType,
            mediaUrl: placeholder,
            caption: caption,
            replyToId: replyToId
        )
        let entity = MessageEntity(
            id: messageId,
            conversationId: conversationId,
            text: placeholder,
            isMe: true,
            time: storedMsg.time,
            status: .sending,
            msgType: msgType,
            mediaUrl: placeholder,
            caption: caption,
            replyToId: replyToId
        )
        try await database.saveMessage(entity)
        onMessage?(storedMsg)
        return messageId
    }

    /// 发送输入状态
    public func sendTyping(toAliasId: String, conversationId: String) async {
        let frame: [String: Any] = [
            "type": "typing",
            "to": toAliasId,
            "conv_id": conversationId
        ]

        if let jsonData = try? JSONSerialization.data(withJSONObject: frame),
           let jsonStr = String(data: jsonData, encoding: .utf8) {
            await transport.send(jsonStr)
        }
    }

    /// 撤回消息
    public func sendRetract(messageId: String, toAliasId: String, conversationId: String) async {
        let frame: [String: Any] = [
            "type": "retract",
            "id": messageId,
            "to": toAliasId,
            "conv_id": conversationId
        ]

        if let jsonData = try? JSONSerialization.data(withJSONObject: frame),
           let jsonStr = String(data: jsonData, encoding: .utf8) {
            await transport.send(jsonStr)
        }
    }

    /// 发送已递送回执
    public func sendDelivered(conversationId: String, seq: Int64, toAliasId: String) async {
        let frame: [String: Any] = [
            "type": "delivered",
            "conv_id": conversationId,
            "seq": seq,
            "to": toAliasId
        ]

        if let jsonData = try? JSONSerialization.data(withJSONObject: frame),
           let jsonStr = String(data: jsonData, encoding: .utf8) {
            await transport.send(jsonStr)
        }
    }

    /// 发送已读回执
    public func sendRead(conversationId: String, seq: Int64, toAliasId: String) async {
        let frame: [String: Any] = [
            "type": "read",
            "conv_id": conversationId,
            "seq": seq,
            "to": toAliasId
        ]

        if let jsonData = try? JSONSerialization.data(withJSONObject: frame),
           let jsonStr = String(data: jsonData, encoding: .utf8) {
            await transport.send(jsonStr)
        }
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - 消息接收
    // ──────────────────────────────────────────────────────────────────────

    private func handleFrame(_ text: String) async {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        guard let type = json["type"] as? String else { return }

        switch type {
        case "message":
            await handleIncomingMessage(json)
        case "typing":
            handleTyping(json)
        case "delivered", "read":
            handleReceipt(json)
        case "retract":
            await handleRetract(json)
        default:
            break
        }
    }

    private func handleIncomingMessage(_ frame: [String: Any]) async {
        guard let conversationId = frame["conv_id"] as? String,
              let fromAliasId = frame["from"] as? String,
              let messageId = frame["id"] as? String,
              let encryptedText = frame["text"] as? String else {
            return
        }

        // 解密
        guard let session = try? await database.loadSession(conversationId),
              let sessionKeyData = Data(base64Encoded: session.sessionKeyBase64) else {
            return
        }

        guard let plaintext = try? CryptoModule.decrypt(sessionKey: sessionKeyData, base64Payload: encryptedText) else {
            return
        }

        // 保存消息
        let time = (frame["time"] as? Int64) ?? Int64(Date().timeIntervalSince1970 * 1000)
        let seq = frame["seq"] as? Int64
        let replyToId = frame["reply_to_id"] as? String

        let entity = MessageEntity(
            id: messageId,
            conversationId: conversationId,
            text: plaintext,
            isMe: false,
            time: time,
            status: .delivered,
            seq: seq,
            fromAliasId: fromAliasId,
            replyToId: replyToId
        )

        try? await database.saveMessage(entity)

        let storedMsg = entity.toStoredMessage()
        onMessage?(storedMsg)

        // 自动发送已递送回执
        if let seq = seq {
            await sendDelivered(conversationId: conversationId, seq: seq, toAliasId: fromAliasId)
        }
    }

    private func handleTyping(_ frame: [String: Any]) {
        guard let fromAliasId = frame["from"] as? String,
              let conversationId = frame["conv_id"] as? String else {
            return
        }

        let event = TypingEvent(fromAliasId: fromAliasId, conversationId: conversationId)
        onTyping?(event)
    }

    private func handleReceipt(_ frame: [String: Any]) {
        guard let type = frame["type"] as? String else { return }
        let status: MessageStatus = type == "delivered" ? .delivered : .read

        // TODO: 更新本地消息状态
    }

    private func handleRetract(_ frame: [String: Any]) async {
        guard let messageId = frame["id"] as? String,
              let conversationId = frame["conv_id"] as? String else {
            return
        }

        var entity = MessageEntity(
            id: messageId,
            conversationId: conversationId,
            text: "消息已撤回",
            isMe: false,
            time: Int64(Date().timeIntervalSince1970 * 1000),
            status: .delivered,
            msgType: "retracted"
        )

        try? await database.saveMessage(entity)
        onMessage?(entity.toStoredMessage())
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - 历史查询
    // ──────────────────────────────────────────────────────────────────────

    /// 获取消息历史
    public func getHistory(conversationId: String, limit: Int = 200, before: Int64? = nil) async throws -> [StoredMessage] {
        let entities = try await database.getMessageHistory(conversationId, limit: limit, before: before)
        return entities.map { $0.toStoredMessage() }
    }

    /// 获取单条消息
    public func getMessage(_ messageId: String) async throws -> StoredMessage? {
        guard let entity = try await database.loadMessage(messageId) else {
            return nil
        }
        return entity.toStoredMessage()
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - 清理
    // ──────────────────────────────────────────────────────────────────────

    /// 清空所有消息
    public func clearAllMessages() async throws {
        try await database.clearAllMessages()
    }

    /// 导出指定会话为 NDJSON
    public func exportConversation(_ conversationId: String) async throws -> String {
        let messages = try await database.getMessageHistory(conversationId, limit: Int.max, before: nil)
            .map { $0.toStoredMessage() }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        var sb = ""
        for m in messages {
            let data = try encoder.encode(m)
            if let line = String(data: data, encoding: .utf8) {
                sb += line + "\n"
            }
        }
        return sb
    }
}
