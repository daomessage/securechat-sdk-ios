import Foundation

// ─── 类型 ──────────────────────────────────────────────
//
// 注意命名约定:
//   models/NetworkState.swift 已有 NetworkState (enum with associated values, WSTransport 用)
//   models/Models.swift       已有 SDKError (LocalizedError enum, 抛错用)
//   models/Models.swift       已有 TypingEvent (Codable, Equatable)
//
// EventBus 想要更轻量的"通知用"类型. 用 Bus 前缀避免和 models/ 冲突.
// 真实使用时 (e.g. ContactsModule) 调用 emitError(BusError(kind: .network, ...))
// 不会和 models/ 的 SDKError 冲突.

public enum BusNetworkState: String, Sendable, Equatable {
    case disconnected, connecting, connected
}

public enum SyncState: Sendable, Equatable {
    case idle
    case syncing(progress: Double, pendingMessages: Int)
    case done(catchUpDurationMs: Int64)
}

public enum BusErrorKind: String, Sendable {
    case auth, network, rateLimit, crypto, server, unknown
}

public struct BusError: Sendable {
    public let kind: BusErrorKind
    public let message: String
    public let details: [String: String]?
    public let at: Int64

    public init(kind: BusErrorKind, message: String, details: [String: String]? = nil) {
        self.kind = kind
        self.message = message
        self.details = details
        self.at = Int64(Date().timeIntervalSince1970 * 1000)
    }
}

public struct BusTypingEvent: Sendable {
    public let fromAliasId: String
    public let conversationId: String
    public init(fromAliasId: String, conversationId: String) {
        self.fromAliasId = fromAliasId
        self.conversationId = conversationId
    }
}

public struct MessageStatusEvent: Sendable {
    public let id: String
    public let status: String
    public init(id: String, status: String) {
        self.id = id
        self.status = status
    }
}

public struct GoawayEvent: Sendable {
    public let reason: String
    public let at: Int64
    public init(reason: String) {
        self.reason = reason
        self.at = Int64(Date().timeIntervalSince1970 * 1000)
    }
}

// ─── EventBus ──────────────────────────────────────────

/// 内部事件总线(SDK 持有)
public final class EventBus: @unchecked Sendable {
    public let network: Observable<BusNetworkState>
    public let sync: Observable<SyncState>
    public let error: Observable<BusError?>
    public let typing: Observable<BusTypingEvent?>
    public let messageStatus: Observable<MessageStatusEvent?>
    public let goaway: Observable<GoawayEvent?>

    public init() {
        self.network = Observable(initial: .disconnected)
        self.sync = Observable(initial: .idle)
        self.error = Observable(initial: nil)
        self.typing = Observable(initial: nil)
        self.messageStatus = Observable(initial: nil)
        self.goaway = Observable(initial: nil)
    }

    public func emitNetwork(_ s: BusNetworkState) { network.next(s) }
    public func emitSync(_ s: SyncState) { sync.next(s) }
    public func emitError(_ e: BusError) { error.next(e) }
    public func emitTyping(_ e: BusTypingEvent) { typing.next(e) }
    public func emitStatus(_ e: MessageStatusEvent) { messageStatus.next(e) }
    public func emitGoaway(_ e: GoawayEvent) { goaway.next(e) }
}
