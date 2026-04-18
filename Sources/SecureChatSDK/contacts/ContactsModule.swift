import Foundation

/// ContactsModule — 0.3.0 iOS 响应式好友系统
///
/// 对标:
///   - sdk-typescript/src/contacts/module.ts
///   - sdk-android/.../contacts/ContactsManager.kt (0.3.0)
///
/// 用法:
///   for await friends in client.contacts.observeFriends().values {
///       render(friends)
///   }
///   try await client.contacts.accept(friendshipId: 42)
public actor ContactsModule {
    private let inner: ContactsManager
    private let events: EventBus
    private let _friends = Observable<[FriendProfile]>(initial: [])
    private var primed: Bool = false
    private var refreshTask: Task<Void, Error>?

    public init(inner: ContactsManager, events: EventBus) {
        self.inner = inner
        self.events = events
    }

    // ─── 观察式 ─────────────────────────────────────────

    /// 所有好友列表流
    public func observeFriends() -> Observable<[FriendProfile]> {
        if !primed {
            primed = true
            Task { try? await self.refresh() }
        }
        return _friends
    }

    public func observeAccepted() -> Observable<[FriendProfile]> {
        _friends.map { list in list.filter { $0.status == .accepted } }
    }

    /// 快照读取
    public var friends: [FriendProfile] {
        _friends.value
    }

    // ─── 命令式(乐观更新 + rollback) ────────────────────

    public func lookupUser(aliasId: String) async throws -> UserProfile {
        return try await inner.lookupUser(aliasId: aliasId)
    }

    public func sendRequest(toAliasId: String) async throws {
        do {
            try await inner.sendFriendRequest(aliasId: toAliasId)
            try await refresh()
        } catch {
            events.emitError(SDKError(kind: .network, message: "sendRequest: \(error)"))
            throw error
        }
    }

    public func accept(friendshipId: Int64) async throws -> String {
        let before = _friends.value
        // 乐观更新
        let optimistic = before.map { f -> FriendProfile in
            var copy = f
            if f.friendshipId == friendshipId {
                copy = FriendProfile(
                    friendshipId: f.friendshipId,
                    aliasId: f.aliasId,
                    nickname: f.nickname,
                    status: .accepted,
                    direction: f.direction,
                    conversationId: f.conversationId,
                    x25519PublicKey: f.x25519PublicKey,
                    ed25519PublicKey: f.ed25519PublicKey,
                    createdAt: f.createdAt
                )
            }
            return copy
        }
        _friends.next(optimistic)

        do {
            let convId = try await inner.acceptFriendRequest(friendshipId: friendshipId)
            try await refresh()
            return convId
        } catch {
            _friends.next(before)
            events.emitError(SDKError(kind: .network, message: "accept: \(error)"))
            throw error
        }
    }

    public func reject(friendshipId: Int64) async throws {
        let before = _friends.value
        let optimistic = before.map { f -> FriendProfile in
            if f.friendshipId == friendshipId {
                return FriendProfile(
                    friendshipId: f.friendshipId,
                    aliasId: f.aliasId,
                    nickname: f.nickname,
                    status: .rejected,
                    direction: f.direction,
                    conversationId: f.conversationId,
                    x25519PublicKey: f.x25519PublicKey,
                    ed25519PublicKey: f.ed25519PublicKey,
                    createdAt: f.createdAt
                )
            }
            return f
        }
        _friends.next(optimistic)

        do {
            try await inner.rejectFriendRequest(friendshipId: friendshipId)
            try await refresh()
        } catch {
            _friends.next(before)
            events.emitError(SDKError(kind: .network, message: "reject: \(error)"))
            throw error
        }
    }

    public func refresh() async throws {
        if let existing = refreshTask {
            return try await existing.value
        }
        let task = Task<Void, Error> {
            let list = try await inner.syncFriends()
            _friends.next(list)
        }
        refreshTask = task
        defer { refreshTask = nil }
        try await task.value
    }

    // ─── 0.2.x 命令式兼容层 ─────────────────────────────

    /// @deprecated 请使用 observeFriends()
    public func syncFriends() async throws -> [FriendProfile] {
        try await refresh()
        return _friends.value
    }

    /// @deprecated 请使用 accept()
    public func acceptFriendRequest(friendshipId: Int64) async throws -> String {
        return try await accept(friendshipId: friendshipId)
    }

    /// @deprecated 请使用 reject()
    public func rejectFriendRequest(friendshipId: Int64) async throws {
        try await reject(friendshipId: friendshipId)
    }

    /// @deprecated 请使用 sendRequest()
    public func sendFriendRequest(aliasId: String) async throws {
        try await sendRequest(toAliasId: aliasId)
    }
}
