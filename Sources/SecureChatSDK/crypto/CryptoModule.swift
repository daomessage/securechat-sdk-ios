import Foundation
import CryptoKit

/// 加密模块 — AES-256-GCM 对称加密 + PoW
public struct CryptoModule {

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - AES-256-GCM 对称加密
    // ──────────────────────────────────────────────────────────────────────

    /// 加密：生成随机 12B IV，AES-GCM 加密，返回 Base64(iv + ciphertext+tag)
    /// 对标 TS/Android SDK: encrypt(sessionKey, plaintext)
    public static func encrypt(sessionKey: Data, plaintext: String) throws -> String {
        guard sessionKey.count == 32 else {
            throw SDKError.encryptionFailed("会话密钥必须是 32 字节")
        }

        let plaintextData = plaintext.data(using: .utf8) ?? Data()

        // 生成随机 12 字节 IV
        var iv = [UInt8](repeating: 0, count: 12)
        let status = SecRandomCopyBytes(kSecRandomDefault, iv.count, &iv)
        guard status == errSecSuccess else {
            throw SDKError.encryptionFailed("生成随机 IV 失败")
        }

        // AES-256-GCM 加密
        let symmetricKey = SymmetricKey(data: sessionKey)
        let sealedBox = try AES.GCM.seal(plaintextData, using: symmetricKey, nonce: AES.GCM.Nonce(data: Data(iv)))

        // 拼接：IV + ciphertext + tag
        // AES.GCM.SealedBox 的 ciphertext 已包含 tag
        var payload = Data(iv)
        payload.append(sealedBox.ciphertext)
        payload.append(sealedBox.tag)

        // 返回 Base64
        return payload.base64EncodedString()
    }

    /// 解密：Base64 解码，拆 IV，AES-GCM 解密
    /// 对标 TS/Android SDK: decrypt(sessionKey, base64Payload)
    public static func decrypt(sessionKey: Data, base64Payload: String) throws -> String {
        guard sessionKey.count == 32 else {
            throw SDKError.decryptionFailed("会话密钥必须是 32 字节")
        }

        guard let payload = Data(base64Encoded: base64Payload) else {
            throw SDKError.decryptionFailed("无效的 Base64 编码")
        }

        // 拆解：IV(12) + ciphertext + tag(16)
        guard payload.count > 28 else {
            throw SDKError.decryptionFailed("加密数据太短（<28 字节）")
        }

        let iv = payload.prefix(12)
        let ciphertext = payload.dropFirst(12).dropLast(16)
        let tag = payload.suffix(16)

        // 重建 SealedBox
        let sealedBox = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: iv), ciphertext: ciphertext, tag: tag)

        // AES-GCM 解密
        let symmetricKey = SymmetricKey(data: sessionKey)
        let decrypted = try AES.GCM.open(sealedBox, using: symmetricKey)

        guard let plaintext = String(data: decrypted, encoding: .utf8) else {
            throw SDKError.decryptionFailed("解密数据编码转换失败")
        }

        return plaintext
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - Proof of Work（PoW）
    // ──────────────────────────────────────────────────────────────────────

    /// 计算 PoW nonce
    /// 算法：迭代计算 SHA256(challenge || nonce)，直到结果前 difficulty 位为 0
    /// 对标 TS/Android SDK: computePow(challenge, difficulty)
    public static func computePow(challenge: String, difficulty: Int) async -> String {
        var nonce: UInt64 = 0
        let targetPrefix = String(repeating: "0", count: difficulty)

        while true {
            let input = (challenge + String(nonce)).data(using: .utf8) ?? Data()
            let hash = SHA256.hash(data: input)
            let hashHex = hash.map { String(format: "%02x", $0) }.joined()

            if hashHex.hasPrefix(targetPrefix) {
                return String(nonce)
            }

            nonce += 1

            // 每 10000 次迭代让出线程，避免阻塞 UI
            if nonce % 10000 == 0 {
                await Task.yield()
            }
        }
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - 便利方法
    // ──────────────────────────────────────────────────────────────────────

    /// 从 Base64 解码
    public static func fromBase64(_ b64: String) throws -> Data {
        guard let data = Data(base64Encoded: b64) else {
            throw SDKError.validationError("无效的 Base64 字符串")
        }
        return data
    }

    /// 转换为 Base64
    public static func toBase64(_ data: Data) -> String {
        return data.base64EncodedString()
    }

    /// 从十六进制字符串解码
    public static func fromHex(_ hex: String) throws -> Data {
        var data = Data()
        var i = hex.startIndex

        while i < hex.endIndex {
            let nextIndex = hex.index(i, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            let byteStr = String(hex[i..<nextIndex])

            guard let byte = UInt8(byteStr, radix: 16) else {
                throw SDKError.validationError("无效的十六进制字符：\(byteStr)")
            }

            data.append(byte)
            i = nextIndex
        }

        return data
    }

    /// 转换为十六进制字符串
    public static func toHex(_ data: Data) -> String {
        return data.map { String(format: "%02x", $0) }.joined()
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - SHA-256 哈希
    // ──────────────────────────────────────────────────────────────────────

    /// SHA-256 哈希
    public static func sha256(_ data: Data) -> Data {
        let hash = SHA256.hash(data: data)
        return Data(hash)
    }

    /// SHA-256 哈希（字符串输入）
    public static func sha256(_ text: String) -> Data {
        let data = text.data(using: .utf8) ?? Data()
        return sha256(data)
    }
}
