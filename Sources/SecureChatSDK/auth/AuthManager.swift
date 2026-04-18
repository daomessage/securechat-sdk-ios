import Foundation

/// 认证管理器（对标 Android AuthManager）
public actor AuthManager {

    private let http: HttpClient
    private let database: Database

    public private(set) var internalUUID: String?

    public init(http: HttpClient, database: Database) {
        self.http = http
        self.database = database
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - 注册新账号
    // ──────────────────────────────────────────────────────────────────────

    /// 注册新账号（完整流程：PoW → 注册 → 认证 → 存储）
    /// 对标 TS/Android SDK: registerAccount(mnemonic, nickname)
    public func registerAccount(mnemonic: String, nickname: String) async throws -> String {
        // 1. 验证助记词
        guard KeyDerivation.validateMnemonic(mnemonic) else {
            throw SDKError.invalidMnemonic("无效的 BIP-39 助记词")
        }

        // 2. 派生密钥
        let identity = try KeyDerivation.deriveIdentity(mnemonic: mnemonic)
        let sigPublicKeyBase64 = identity.signingKey.publicKey.base64EncodedString()
        let ecdhPublicKeyBase64 = identity.ecdhKey.publicKey.base64EncodedString()

        // 3. PoW 验证（可选，失败不阻塞）
        var powNonce: String? = nil
        do {
            let powChallenge = try await http.get("/api/v1/pow/challenge") as PowChallengeResponse
            powNonce = await CryptoModule.computePow(challenge: powChallenge.challengeString, difficulty: powChallenge.difficulty)
        } catch {
            // PoW 失败不阻塞注册
            print("PoW 计算失败: \(error)")
        }

        // 4. 注册账号
        let registerReq = RegisterRequest(
            ed25519PublicKey: sigPublicKeyBase64,
            x25519PublicKey: ecdhPublicKeyBase64,
            nickname: nickname,
            powNonce: powNonce
        )
        let registerResp = try await http.post("/api/v1/register", body: registerReq) as RegisterResponse

        // 5. 认证获取 JWT
        let token = try await authenticate(userUUID: registerResp.uuid, signingPrivateKey: identity.signingKey.privateKey)
        await http.setToken(token)
        internalUUID = registerResp.uuid

        // 6. 保存身份到数据库
        let storedIdentity = StoredIdentity(
            uuid: registerResp.uuid,
            aliasId: registerResp.aliasId,
            nickname: nickname,
            mnemonic: mnemonic,
            signingPublicKey: sigPublicKeyBase64,
            ecdhPublicKey: ecdhPublicKeyBase64
        )
        try await database.saveIdentity(storedIdentity)

        return registerResp.aliasId
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - 恢复历史会话
    // ──────────────────────────────────────────────────────────────────────

    /// 恢复历史会话（从本地数据库读取身份并认证）
    /// 对标 TS/Android SDK: restoreSession()
    public func restoreSession() async throws -> (aliasId: String, nickname: String)? {
        let stored = try await database.loadIdentity()
        guard let stored = stored else {
            return nil
        }

        // 从助记词派生私钥（不能用公钥）
        let identity = try KeyDerivation.deriveIdentity(mnemonic: stored.mnemonic)
        do {
            let token = try await authenticate(userUUID: stored.uuid, signingPrivateKey: identity.signingKey.privateKey)
            await http.setToken(token)
            internalUUID = stored.uuid
            return (stored.aliasId, stored.nickname)
        } catch {
            // 认证失败
            print("会话恢复失败: \(error)")
            return nil
        }
    }

    /// 从助记词恢复（异地登录）
    public func loginWithMnemonic(_ mnemonic: String) async throws -> String {
        guard KeyDerivation.validateMnemonic(mnemonic) else {
            throw SDKError.invalidMnemonic("无效的 BIP-39 助记词")
        }

        let identity = try KeyDerivation.deriveIdentity(mnemonic: mnemonic)
        let sigPublicKeyBase64 = identity.signingKey.publicKey.base64EncodedString()
        let ecdhPublicKeyBase64 = identity.ecdhKey.publicKey.base64EncodedString()

        // 尝试注册，如果返回 409 则说明账号已存在
        var userUUID = ""
        var aliasId = ""

        let registerReq = RegisterRequest(
            ed25519PublicKey: sigPublicKeyBase64,
            x25519PublicKey: ecdhPublicKeyBase64,
            nickname: "Restored User"
        )

        do {
            let resp = try await http.post("/api/v1/register", body: registerReq) as RegisterResponse
            userUUID = resp.uuid
            aliasId = resp.aliasId
        } catch let error as SDKError {
            if case .validationError(let msg) = error, msg.contains("409") {
                // 解析 409 响应体获取 uuid 和 alias_id
                throw SDKError.authenticationFailed("账号已存在，请直接注册新账号")
            }
            throw error
        }

        guard !userUUID.isEmpty else {
            throw SDKError.authenticationFailed("恢复失败：无法获取身份标识")
        }

        // 认证并获取 JWT
        let token = try await authenticate(userUUID: userUUID, signingPrivateKey: identity.signingKey.privateKey)
        await http.setToken(token)
        internalUUID = userUUID

        // 保存到数据库
        let storedIdentity = StoredIdentity(
            uuid: userUUID,
            aliasId: aliasId,
            nickname: "Restored User",
            mnemonic: mnemonic,
            signingPublicKey: sigPublicKeyBase64,
            ecdhPublicKey: ecdhPublicKeyBase64
        )
        try await database.saveIdentity(storedIdentity)

        return aliasId
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - 内部：Challenge-Response 认证
    // ──────────────────────────────────────────────────────────────────────

    /// Challenge-Response 认证（获取 JWT）
    /// 对标 TS/Android SDK: performAuthChallenge()
    private func authenticate(userUUID: String, signingPrivateKey: Data) async throws -> String {
        // 1. 获取挑战
        let challengeReq = AuthChallengeRequest(userUUID: userUUID)
        let challengeResp = try await http.post("/api/v1/auth/challenge", body: challengeReq) as AuthChallengeResponse

        // 2. 签名挑战
        let challengeData = challengeResp.challenge.data(using: .utf8) ?? Data()
        let signature = try KeyDerivation.signChallenge(challenge: challengeData, privateKey: signingPrivateKey)
        let signatureBase64 = signature.base64EncodedString()

        // 3. 验证并获取 JWT
        let verifyReq = AuthVerifyRequest(userUUID: userUUID, challenge: challengeResp.challenge, signature: signatureBase64)
        let verifyResp = try await http.post("/api/v1/auth/verify", body: verifyReq) as AuthVerifyResponse

        return verifyResp.token
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - 登出
    // ──────────────────────────────────────────────────────────────────────

    /// 登出（清除身份和 Token）
    public func logout() async throws {
        internalUUID = nil
        await http.clearToken()
        try await database.clearIdentity()
    }
}
