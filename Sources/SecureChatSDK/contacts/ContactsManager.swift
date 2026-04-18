import Foundation

/// 好友管理器（对标 Android ContactsManager）
public actor ContactsManager {

    private let http: HttpClient
    private let database: Database

    public init(http: HttpClient, database: Database) {
        self.http = http
        self.database = database
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - 好友操作
    // ──────────────────────────────────────────────────────────────────────

    /// 同步好友列表并自动创建安全会话
    public func syncFriends() async throws -> [FriendProfile] {
        let friends = try await http.get("/api/v1/friends") as [FriendProfile]

        // 获取本地身份
        guard let identity = try await database.loadIdentity() else {
            throw SDKError.sessionNotFound("未找到本地身份")
        }

        // 为已接受的好友创建会话
        for friend in friends where friend.status == .accepted {
            let conversationId = friend.conversationId
            let session = try? await database.loadSession(conversationId)

            if session == nil {
                // 创建新会话
                let theirEcdhPubKey = friend.x25519PublicKey
                let myEcdhPrivateKey = try KeyDerivation.deriveEcdhKey(mnemonic: identity.mnemonic).privateKey

                let sharedSecret = try KeyDerivation.computeSharedSecret(
                    myPrivateKey: myEcdhPrivateKey,
                    theirPublicKey: try CryptoModule.fromBase64(theirEcdhPubKey)
                )
                let sessionKey = try KeyDerivation.deriveSessionKey(sharedSecret: sharedSecret, conversationId: conversationId)

                let sessionEntity = SessionEntity(
                    conversationId: conversationId,
                    theirAliasId: friend.aliasId,
                    theirEcdhPublicKey: theirEcdhPubKey,
                    sessionKeyBase64: sessionKey.base64EncodedString(),
                    createdAt: Int64(Date().timeIntervalSince1970 * 1000)
                )

                try await database.saveSession(sessionEntity)
            }
        }

        return friends
    }

    /// 发送好友请求
    public func sendFriendRequest(toAliasId: String) async throws {
        let req = SendFriendRequestRequest(toAliasId: toAliasId)
        try await http.postVoid("/api/v1/friends/request", body: req)
    }

    /// 接受好友请求
    public func acceptFriendRequest(friendshipId: Int) async throws {
        let req = AcceptFriendRequestRequest(friendshipId: friendshipId)
        try await http.postVoid("/api/v1/friends/accept", body: req)
    }

    /// 拒绝好友请求
    /// 服务端 POST /api/v1/friends/{friendshipId}/reject，与 accept 路径风格对齐。
    public func rejectFriendRequest(friendshipId: Int) async throws {
        let emptyBody: [String: String] = [:]
        try await http.postVoid("/api/v1/friends/\(friendshipId)/reject", body: emptyBody)
    }

    /// 查找用户
    public func lookupUser(aliasId: String) async throws -> UserProfile {
        return try await http.get("/api/v1/users/\(aliasId)") as UserProfile
    }
}
