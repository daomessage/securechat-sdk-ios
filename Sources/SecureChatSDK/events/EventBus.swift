import Foundation

// ─── 类型 ──────────────────────────────────────────────

public enum NetworkState: String, Sendable, Equatable {
    case disconnected, connecting, connected
}

public enum SyncState: Sendable, Equatable {
    case idle
    case syncing(progress: Double, pendingMessages: Int)
    case done(catchUpDurationMs: Int64)
}

public enum SDKErrorKind: String, Sendable {
    case auth, network, rateLimit, crypto, server, unknown
}

public struct SDKError: Sendable {
    public let kind: SDKErrorKind
    public let message: String
    public let details: [String: String]?
    public let at: Int64

    public init(kind: SDKErrorKind, message: String, details: [String: String]? = nil) {
        self.kind = kind
        self.message = message
        self.details = details
        self.at = Int64(Date().timeIntervalSince1970 * 1000)
    }
}

public struct TypingEvent: Sendable {
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
    public let network: Observable<NetworkState>
    public let sync: Observable<SyncState>
    public let error: Observable<SDKError?>
    public let typing: Observable<TypingEvent?>
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

    public func emitNetwork(_ s: NetworkState) { network.next(s) }
    public func emitSync(_ s: SyncState) { sync.next(s) }
    public func emitError(_ e: SDKError) { error.next(e) }
    public func emitTyping(_ e: TypingEvent) { typing.next(e) }
    public func emitStatus(_ e: MessageStatusEvent) { messageStatus.next(e) }
    public func emitGoaway(_ e: GoawayEvent) { goaway.next(e) }
}
