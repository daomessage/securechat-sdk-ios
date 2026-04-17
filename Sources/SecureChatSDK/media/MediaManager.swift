import Foundation

/// 多媒体管理器（对标 Android MediaManager）
public actor MediaManager {

    private let http: HttpClient

    public init(http: HttpClient) {
        self.http = http
    }

    /// 上传图片
    public func uploadImage(
        conversationId: String,
        imageData: Data,
        maxDim: Int = 1920,
        quality: Float = 0.8
    ) async throws -> String {
        // 简化版：直接加密并上传（完整版需要图片压缩）
        return try await uploadEncryptedMedia(
            data: imageData,
            conversationId: conversationId,
            mediaType: "image/jpeg",
            fileName: "image.jpg"
        )
    }

    /// 上传文件
    public func uploadFile(
        fileData: Data,
        conversationId: String,
        fileName: String
    ) async throws -> String {
        return try await uploadEncryptedMedia(
            data: fileData,
            conversationId: conversationId,
            mediaType: "application/octet-stream",
            fileName: fileName
        )
    }

    /// 上传语音
    public func uploadVoice(
        audioData: Data,
        conversationId: String,
        durationMs: Int
    ) async throws -> String {
        return try await uploadEncryptedMedia(
            data: audioData,
            conversationId: conversationId,
            mediaType: "audio/mp4",
            fileName: "voice.m4a"
        )
    }

    /// 下载并解密媒体
    public func downloadDecryptedMedia(mediaKey: String, conversationId: String) async throws -> Data {
        // 获取会话密钥（Database 是 actor，需要 await）
        let database = Database.shared()
        guard let session = try await database.loadSession(conversationId),
              let sessionKeyData = Data(base64Encoded: session.sessionKeyBase64) else {
            throw SDKError.sessionNotFound("未找到会话")
        }

        // 从服务端下载加密数据
        let cleanKey = mediaKey.replacingOccurrences(of: "[img]", with: "")
            .replacingOccurrences(of: "[file]", with: "")
            .replacingOccurrences(of: "[voice]", with: "")

        let url = URL(string: "\(HttpClient.CORE_API_BASE)/api/v1/media/\(cleanKey)")!
        let (data, _) = try await http.fetch(url)

        // 解密
        let decrypted = try CryptoModule.decrypt(sessionKey: sessionKeyData, base64Payload: data.base64EncodedString())
        return decrypted.data(using: .utf8) ?? Data()
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - 内部方法
    // ──────────────────────────────────────────────────────────────────────

    private func uploadEncryptedMedia(
        data: Data,
        conversationId: String,
        mediaType: String,
        fileName: String
    ) async throws -> String {
        // 获取会话密钥（Database 是 actor，需要 await）
        let database = Database.shared()
        guard let session = try await database.loadSession(conversationId),
              let sessionKeyData = Data(base64Encoded: session.sessionKeyBase64) else {
            throw SDKError.sessionNotFound("未找到会话")
        }

        // 加密数据
        let plaintext = String(data: data, encoding: .utf8) ?? data.base64EncodedString()
        let encryptedBase64 = try CryptoModule.encrypt(sessionKey: sessionKeyData, plaintext: plaintext)

        // 上传到服务端
        struct UploadRequest: Codable {
            let data: String
            let mediaType: String
            let fileName: String

            enum CodingKeys: String, CodingKey {
                case data
                case mediaType = "media_type"
                case fileName = "file_name"
            }
        }

        let req = UploadRequest(data: encryptedBase64, mediaType: mediaType, fileName: fileName)
        let resp = try await http.post("/api/v1/media/upload", body: req) as [String: String]

        guard let mediaKey = resp["media_key"] else {
            throw SDKError.networkError("上传失败：无法获取媒体 key")
        }

        return mediaKey
    }
}
