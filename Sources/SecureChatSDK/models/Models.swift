import Foundation

// ──────────────────────────────────────────────────────────────────────────
// MARK: - 消息和会话数据模型
// ──────────────────────────────────────────────────────────────────────────

/// 存储的消息（对标 TS SDK StoredMessage）
public struct StoredMessage: Codable, Equatable, Identifiable {
    /// 消息唯一 ID
    public let id: String
    /// 对话 ID（derived from min(myAlias, theirAlias))
    public let conversationId: String
    /// 消息内容（文本或格式化的媒体描述）
    public let text: String
    /// 是否是我发送的消息
    public let isMe: Bool
    /// 发送/接收时间戳（毫秒）
    public let time: Int64
    /// 消息状态
    public let status: MessageStatus
    /// 消息类型（可选：text/image/file/voice/retracted）
    public var msgType: String? = nil
    /// 媒体 URL 或 key（可选，如"[img]media_key"）
    public var mediaUrl: String? = nil
    /// 媒体标题/文件名/语音时长（可选）
    public var caption: String? = nil
    /// 服务端序列号（可选，用于同步确认）
    public var seq: Int64? = nil
    /// 发送方别名 ID（可选，用于多端设备识别）
    public var fromAliasId: String? = nil
    /// 回复目标消息 ID（可选）
    public var replyToId: String? = nil

    public init(
        id: String,
        conversationId: String,
        text: String,
        isMe: Bool,
        time: Int64,
        status: MessageStatus,
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
}

/// 消息状态
public enum MessageStatus: String, Codable {
    /// 正在发送
    case sending = "sending"
    /// 已发送
    case sent = "sent"
    /// 已递送（对方客户端收到）
    case delivered = "delivered"
    /// 已读
    case read = "read"
    /// 发送失败
    case failed = "failed"
}

/// 会话记录（对标 TS SDK SessionRecord）
public struct SessionRecord: Codable, Equatable {
    /// 对话 ID（pk）
    public let conversationId: String
    /// 对方别名 ID
    public let theirAliasId: String
    /// 对方 ECDH 公钥（Base64）
    public let theirEcdhPublicKey: String
    /// 对方 Ed25519 公钥（可选）
    public var theirEd25519PublicKey: String? = nil
    /// 会话密钥（Base64，32B）
    public let sessionKeyBase64: String
    /// 信任状态（unverified/verified）
    public let trustState: TrustState
    /// 创建时间戳（毫秒）
    public let createdAt: Int64

    public init(
        conversationId: String,
        theirAliasId: String,
        theirEcdhPublicKey: String,
        sessionKeyBase64: String,
        trustState: TrustState,
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

/// 信任状态
public enum TrustState: String, Codable {
    /// 未验证（默认，存在 MITM 风险）
    case unverified = "unverified"
    /// 已验证（用户手动比对安全码）
    case verified = "verified"
}

/// 存储的身份（对标 TS SDK StoredIdentity）
public struct StoredIdentity: Codable, Equatable {
    /// 用户 UUID（服务端分配，用于 WS 连接和认证）
    public let uuid: String
    /// 别名 ID（用户对外展示的号码，如 u12345678）
    public let aliasId: String
    /// 昵称（自定义用户名）
    public let nickname: String
    /// 12 词 BIP39 助记词（加密存储）
    public let mnemonic: String
    /// Ed25519 签名公钥（Base64）
    public let signingPublicKey: String
    /// X25519 ECDH 公钥（Base64）
    public let ecdhPublicKey: String

    public init(
        uuid: String,
        aliasId: String,
        nickname: String,
        mnemonic: String,
        signingPublicKey: String,
        ecdhPublicKey: String
    ) {
        self.uuid = uuid
        self.aliasId = aliasId
        self.nickname = nickname
        self.mnemonic = mnemonic
        self.signingPublicKey = signingPublicKey
        self.ecdhPublicKey = ecdhPublicKey
    }
}

// ──────────────────────────────────────────────────────────────────────────
// MARK: - 通讯录和好友相关
// ──────────────────────────────────────────────────────────────────────────

/// 好友资料（对标 TS SDK FriendProfile）
public struct FriendProfile: Codable, Equatable {
    /// 好友关系 ID（服务端生成）
    public let friendshipId: Int
    /// 好友的别名 ID
    public let aliasId: String
    /// 好友昵称
    public let nickname: String
    /// 好友请求状态
    public let status: FriendshipStatus
    /// 请求方向（sent/received）
    public let direction: String
    /// 对话 ID
    public let conversationId: String
    /// 对方 X25519 公钥（Base64）
    public let x25519PublicKey: String
    /// 对方 Ed25519 公钥（Base64）
    public let ed25519PublicKey: String
    /// 创建时间（ISO 8601）
    public let createdAt: String

    public init(
        friendshipId: Int,
        aliasId: String,
        nickname: String,
        status: FriendshipStatus,
        direction: String,
        conversationId: String,
        x25519PublicKey: String,
        ed25519PublicKey: String,
        createdAt: String
    ) {
        self.friendshipId = friendshipId
        self.aliasId = aliasId
        self.nickname = nickname
        self.status = status
        self.direction = direction
        self.conversationId = conversationId
        self.x25519PublicKey = x25519PublicKey
        self.ed25519PublicKey = ed25519PublicKey
        self.createdAt = createdAt
    }
}

/// 好友关系状态
public enum FriendshipStatus: String, Codable {
    case pending = "pending"
    case accepted = "accepted"
    case rejected = "rejected"
}

/// 用户资料查询结果
public struct UserProfile: Codable, Equatable {
    /// 别名 ID
    public let aliasId: String
    /// 昵称
    public let nickname: String
    /// X25519 公钥（Base64）
    public let x25519PublicKey: String
    /// Ed25519 公钥（Base64）
    public let ed25519PublicKey: String
}

// ──────────────────────────────────────────────────────────────────────────
// MARK: - 频道相关
// ──────────────────────────────────────────────────────────────────────────

/// 频道信息（对标 TS SDK ChannelInfo）
public struct ChannelInfo: Codable, Equatable {
    /// 频道 ID
    public let id: String
    /// 频道名称
    public let name: String
    /// 频道描述
    public let description: String
    /// 当前用户的角色（可选）
    public var role: String? = nil
    /// 是否已订阅
    public var isSubscribed: Bool? = nil
    /// 是否处于出售状态
    public var forSale: Bool? = nil
    /// 出售价格（USDT）
    public var salePrice: Int? = nil

    enum CodingKeys: String, CodingKey {
        case id, name, description, role
        case isSubscribed = "is_subscribed"
        case forSale = "for_sale"
        case salePrice = "sale_price"
    }

    public init(
        id: String,
        name: String,
        description: String,
        role: String? = nil,
        isSubscribed: Bool? = nil,
        forSale: Bool? = nil,
        salePrice: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.role = role
        self.isSubscribed = isSubscribed
        self.forSale = forSale
        self.salePrice = salePrice
    }
}

/// 频道帖子
public struct ChannelPost: Codable, Equatable {
    /// 帖子 ID
    public let id: String
    /// 内容类型
    public let type: String
    /// 内容
    public let content: String
    /// 创建时间（ISO 8601）
    public let createdAt: String
    /// 作者别名 ID
    public let authorAliasId: String

    enum CodingKeys: String, CodingKey {
        case id, type, content
        case createdAt = "created_at"
        case authorAliasId = "author_alias_id"
    }
}

/// 频道交易订单
public struct ChannelTradeOrder: Codable, Equatable {
    /// 订单 ID
    public let orderId: String
    /// 价格（USDT）
    public let priceUsdt: Int
    /// TRON 收款地址
    public let payTo: String
    /// 订单过期时间（ISO 8601）
    public let expiredAt: String

    enum CodingKeys: String, CodingKey {
        case orderId = "order_id"
        case priceUsdt = "price_usdt"
        case payTo = "pay_to"
        case expiredAt = "expired_at"
    }
}

// ──────────────────────────────────────────────────────────────────────────
// MARK: - 靓号相关
// ──────────────────────────────────────────────────────────────────────────

/// 靓号列表项（对标 TS SDK VanityItem）
public struct VanityItem: Codable, Equatable {
    /// 靓号别名 ID
    public let aliasId: String
    /// 价格（USDT）
    public let priceUsdt: Int
    /// 靓号等级（top/premium/standard）
    public let tier: String
    /// 是否精选
    public let isFeatured: Bool

    enum CodingKeys: String, CodingKey {
        case aliasId = "alias_id"
        case priceUsdt = "price_usdt"
        case tier
        case isFeatured = "is_featured"
    }
}

/// 购买靓号返回的支付订单
public struct PurchaseOrder: Codable, Equatable {
    /// 订单 ID
    public let orderId: String
    /// 靓号别名
    public let aliasId: String
    /// 价格（USDT）
    public let priceUsdt: Int
    /// NOWPayments 支付页 URL（可选）
    public var paymentUrl: String? = nil
    /// TRON 收款地址（旧版，NOWPayments 接入后不使用）
    public var payTo: String? = nil
    /// 订单过期时间（ISO 8601）
    public let expiredAt: String

    enum CodingKeys: String, CodingKey {
        case orderId = "order_id"
        case aliasId = "alias_id"
        case priceUsdt = "price_usdt"
        case paymentUrl = "payment_url"
        case payTo = "pay_to"
        case expiredAt = "expired_at"
    }
}

// ──────────────────────────────────────────────────────────────────────────
// MARK: - 媒体和多媒体
// ──────────────────────────────────────────────────────────────────────────

/// 媒体上传结果
public struct MediaUploadResult: Codable, Equatable {
    /// 媒体 key（服务端返回的唯一标识）
    public let mediaKey: String
    /// 媒体大小（字节）
    public let size: Int
    /// 媒体类型（MIME）
    public let contentType: String
}

// ──────────────────────────────────────────────────────────────────────────
// MARK: - 输入事件
// ──────────────────────────────────────────────────────────────────────────

/// 输入中事件
public struct TypingEvent: Codable, Equatable {
    /// 发送方别名 ID
    public let fromAliasId: String
    /// 对话 ID
    public let conversationId: String
}

/// 消息状态变更事件
public struct MessageStatusChange: Codable, Equatable {
    /// 消息 ID
    public let messageId: String
    /// 新状态
    public let status: MessageStatus
}

// ──────────────────────────────────────────────────────────────────────────
// MARK: - 安全和加密相关
// ──────────────────────────────────────────────────────────────────────────

/// 安全码（MITM 防御）
public struct SecurityCode: Equatable {
    /// 60 字符十六进制安全码
    public let code: String
    /// 生成时间
    public let generatedAt: Date

    public init(code: String, generatedAt: Date = Date()) {
        self.code = code
        self.generatedAt = generatedAt
    }
}

// ──────────────────────────────────────────────────────────────────────────
// MARK: - 错误类型
// ──────────────────────────────────────────────────────────────────────────

/// SDK 错误类型
public enum SDKError: LocalizedError {
    /// 网络错误
    case networkError(String)
    /// 加密失败
    case encryptionFailed(String)
    /// 解密失败
    case decryptionFailed(String)
    /// 认证失败
    case authenticationFailed(String)
    /// 无效的助记词
    case invalidMnemonic(String)
    /// WebSocket 连接错误
    case connectionError(String)
    /// 数据库错误
    case databaseError(String)
    /// 消息验证失败
    case validationError(String)
    /// 会话不存在
    case sessionNotFound(String)
    /// 一般错误
    case generalError(String)

    public var errorDescription: String? {
        switch self {
        case .networkError(let msg):
            return "网络错误: \(msg)"
        case .encryptionFailed(let msg):
            return "加密失败: \(msg)"
        case .decryptionFailed(let msg):
            return "解密失败: \(msg)"
        case .authenticationFailed(let msg):
            return "认证失败: \(msg)"
        case .invalidMnemonic(let msg):
            return "无效的助记词: \(msg)"
        case .connectionError(let msg):
            return "连接错误: \(msg)"
        case .databaseError(let msg):
            return "数据库错误: \(msg)"
        case .validationError(let msg):
            return "验证错误: \(msg)"
        case .sessionNotFound(let msg):
            return "会话不存在: \(msg)"
        case .generalError(let msg):
            return "错误: \(msg)"
        }
    }
}

// ── 存储估算 ─────────────────────────────────────────────────────────
public struct StorageEstimate: Codable, Equatable {
    public let usedBytes: Int64
    public let quotaBytes: Int64
    public let messageCount: Int

    enum CodingKeys: String, CodingKey {
        case usedBytes = "used_bytes"
        case quotaBytes = "quota_bytes"
        case messageCount = "message_count"
    }

    public init(usedBytes: Int64 = 0, quotaBytes: Int64 = 0, messageCount: Int = 0) {
        self.usedBytes = usedBytes
        self.quotaBytes = quotaBytes
        self.messageCount = messageCount
    }
}
