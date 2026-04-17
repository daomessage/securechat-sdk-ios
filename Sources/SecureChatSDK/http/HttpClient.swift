import Foundation

/// HTTP 客户端（基于 URLSession）
public actor HttpClient {

    // API 服务器基地址（硬编码，对标 Android SDK）
    public static let CORE_API_BASE = "https://relay.daomessage.com"

    private var token: String?
    private let session: URLSession

    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - Token 管理
    // ──────────────────────────────────────────────────────────────────────

    /// 设置 JWT 令牌（认证后）
    public func setToken(_ token: String) {
        self.token = token
    }

    /// 获取当前 Token
    public func getToken() -> String? {
        return token
    }

    /// 清除 Token（登出时）
    public func clearToken() {
        self.token = nil
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - 请求头构建
    // ──────────────────────────────────────────────────────────────────────

    /// 构建请求头
    private func getHeaders(customHeaders: [String: String] = [:]) -> [String: String] {
        var headers: [String: String] = [
            "Content-Type": "application/json",
            "Accept": "application/json"
        ]

        // 注入 JWT 令牌（如果已认证）
        if let token = token {
            headers["Authorization"] = "Bearer \(token)"
        }

        // 合并自定义头
        headers.merge(customHeaders) { _, custom in custom }
        return headers
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - 通用请求方法
    // ──────────────────────────────────────────────────────────────────────

    /// GET 请求
    public func get<T: Decodable>(_ path: String) async throws -> T {
        let url = URL(string: Self.CORE_API_BASE + path) ?? URL(fileURLWithPath: "")
        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 30)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = getHeaders()

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)

        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: data)
    }

    /// POST 请求
    public func post<T: Decodable>(_ path: String, body: some Encodable) async throws -> T {
        let url = URL(string: Self.CORE_API_BASE + path) ?? URL(fileURLWithPath: "")
        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = getHeaders()

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)

        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: data)
    }

    /// PUT 请求
    public func put<T: Decodable>(_ path: String, body: some Encodable) async throws -> T {
        let url = URL(string: Self.CORE_API_BASE + path) ?? URL(fileURLWithPath: "")
        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 30)
        request.httpMethod = "PUT"
        request.allHTTPHeaderFields = getHeaders()

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)

        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: data)
    }

    /// POST 请求（不需要返回值）
    public func postVoid(_ path: String, body: some Encodable) async throws {
        let url = URL(string: Self.CORE_API_BASE + path) ?? URL(fileURLWithPath: "")
        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = getHeaders()

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
    }

    /// PUT 请求（不需要返回值）
    public func putVoid(_ path: String, body: some Encodable) async throws {
        let url = URL(string: Self.CORE_API_BASE + path) ?? URL(fileURLWithPath: "")
        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 30)
        request.httpMethod = "PUT"
        request.allHTTPHeaderFields = getHeaders()

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
    }

    /// DELETE 请求
    public func delete(_ path: String) async throws {
        let url = URL(string: Self.CORE_API_BASE + path) ?? URL(fileURLWithPath: "")
        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 30)
        request.httpMethod = "DELETE"
        request.allHTTPHeaderFields = getHeaders()

        let (_, response) = try await session.data(for: request)
        try validateResponse(response, data: Data())
    }

    /// 原始数据请求（用于媒体 PUT/GET）
    public func fetch(_ url: URL, method: String = "GET", headers: [String: String]? = nil, body: Data? = nil) async throws -> (data: Data, response: HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body

        // 合并默认头和自定义头
        let allHeaders = headers ?? [:]
        for (key, value) in getHeaders() {
            if !allHeaders.keys.contains(key) {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }
        for (key, value) in allHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SDKError.networkError("无效的 HTTP 响应")
        }

        return (data: data, response: httpResponse)
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - 响应验证
    // ──────────────────────────────────────────────────────────────────────

    private func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SDKError.networkError("无效的 HTTP 响应")
        }

        switch httpResponse.statusCode {
        case 200...299:
            return  // 成功
        case 400:
            throw SDKError.validationError("请求参数错误 (400)")
        case 401:
            throw SDKError.authenticationFailed("未授权，请重新登录 (401)")
        case 403:
            throw SDKError.authenticationFailed("禁止访问 (403)")
        case 404:
            throw SDKError.networkError("资源不存在 (404)")
        case 409:
            throw SDKError.validationError("冲突 (409)")
        case 500...599:
            throw SDKError.networkError("服务器错误 (\(httpResponse.statusCode))")
        default:
            throw SDKError.networkError("HTTP \(httpResponse.statusCode) 错误")
        }
    }
}

// ──────────────────────────────────────────────────────────────────────────
// MARK: - API 请求体和响应体
// ──────────────────────────────────────────────────────────────────────────

/// 注册请求
public struct RegisterRequest: Codable {
    public let ed25519PublicKey: String
    public let x25519PublicKey: String
    public let nickname: String
    public let powNonce: String?

    enum CodingKeys: String, CodingKey {
        case ed25519PublicKey = "ed25519_public_key"
        case x25519PublicKey = "x25519_public_key"
        case nickname
        case powNonce = "pow_nonce"
    }

    public init(ed25519PublicKey: String, x25519PublicKey: String, nickname: String, powNonce: String? = nil) {
        self.ed25519PublicKey = ed25519PublicKey
        self.x25519PublicKey = x25519PublicKey
        self.nickname = nickname
        self.powNonce = powNonce
    }
}

/// 注册响应
public struct RegisterResponse: Codable {
    public let uuid: String
    public let aliasId: String

    enum CodingKeys: String, CodingKey {
        case uuid
        case aliasId = "alias_id"
    }
}

/// PoW 挑战请求
public struct PowChallengeRequest: Codable {
    public init() {}
}

/// PoW 挑战响应
public struct PowChallengeResponse: Codable {
    public let challengeString: String
    public let difficulty: Int

    enum CodingKeys: String, CodingKey {
        case challengeString = "challenge_string"
        case difficulty
    }
}

/// 认证挑战请求
public struct AuthChallengeRequest: Codable {
    public let userUUID: String

    enum CodingKeys: String, CodingKey {
        case userUUID = "user_uuid"
    }

    public init(userUUID: String) {
        self.userUUID = userUUID
    }
}

/// 认证挑战响应
public struct AuthChallengeResponse: Codable {
    public let challenge: String
    public let expiresAt: String

    enum CodingKeys: String, CodingKey {
        case challenge
        case expiresAt = "expires_at"
    }
}

/// 认证验证请求
public struct AuthVerifyRequest: Codable {
    public let userUUID: String
    public let challenge: String
    public let signature: String

    enum CodingKeys: String, CodingKey {
        case userUUID = "user_uuid"
        case challenge
        case signature
    }

    public init(userUUID: String, challenge: String, signature: String) {
        self.userUUID = userUUID
        self.challenge = challenge
        self.signature = signature
    }
}

/// 认证验证响应
public struct AuthVerifyResponse: Codable {
    public let token: String
    public let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case token
        case expiresIn = "expires_in"
    }
}

/// 发送消息请求
public struct SendMessageRequest: Codable {
    public let conversationId: String
    public let to: String
    public let text: String
    public let replyToId: String?

    enum CodingKeys: String, CodingKey {
        case conversationId = "conversation_id"
        case to
        case text
        case replyToId = "reply_to_id"
    }

    public init(conversationId: String, to: String, text: String, replyToId: String? = nil) {
        self.conversationId = conversationId
        self.to = to
        self.text = text
        self.replyToId = replyToId
    }
}

/// 发送好友请求
public struct SendFriendRequestRequest: Codable {
    public let toAliasId: String

    enum CodingKeys: String, CodingKey {
        case toAliasId = "to_alias_id"
    }

    public init(toAliasId: String) {
        self.toAliasId = toAliasId
    }
}

/// 接受好友请求
public struct AcceptFriendRequestRequest: Codable {
    public let friendshipId: Int

    enum CodingKeys: String, CodingKey {
        case friendshipId = "friendship_id"
    }

    public init(friendshipId: Int) {
        self.friendshipId = friendshipId
    }
}
