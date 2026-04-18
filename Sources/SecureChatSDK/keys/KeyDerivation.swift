// sdk-ios/Sources/SecureChatSDK/keys/KeyDerivation.swift
// ⚠️ 警告：不得修改派生路径或 HMAC 密钥，否则与 TS/Android SDK 双端公钥不一致

import Foundation
import CryptoKit
import CommonCrypto

// MARK: - 密钥体系核心

/// 密钥体系核心 — 完全对标 Android SDK
///
/// 派生路径（SLIP-0010 硬化派生）：
///   Ed25519: m/44'/0'/0'/0/0  — 身份认证/签名
///   X25519:  m/44'/1'/0'/0/0  — ECDH 消息加密
public struct KeyDerivation {

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - 助记词管理
    // ──────────────────────────────────────────────────────────────────────

    /// 生成 12 词 BIP-39 英文助记词（128bit 熵）
    /// 对标 TS/Android SDK: newMnemonic()
    public static func newMnemonic() -> String {
        var entropy = [UInt8](repeating: 0, count: 16)
        let status = SecRandomCopyBytes(kSecRandomDefault, entropy.count, &entropy)
        guard status == errSecSuccess else {
            return generateFallbackMnemonic()
        }
        return mnemonicFromEntropy(entropy)
    }

    /// 验证助记词是否合法（12 词，BIP-39 词库）
    /// 对标 TS/Android SDK: validateMnemonic()
    public static func validateMnemonic(_ mnemonic: String) -> Bool {
        let wordArray = mnemonic.trimmingCharacters(in: .whitespaces).split(separator: " ")
        guard wordArray.count == 12 else { return false }

        let wordSet = Set(BIP39Wordlist.words)
        for word in wordArray {
            guard wordSet.contains(String(word)) else { return false }
        }

        guard let entropy = wordsToEntropy(wordArray.map { String($0) }) else {
            return false
        }
        let derived = mnemonicFromEntropy(entropy)
        return derived == mnemonic
    }

    /// 助记词 → BIP-39 Seed（PBKDF2-HMAC-SHA512，2048 轮，无 passphrase）
    /// 对标 TS/Android SDK: mnemonicToSeed()
    public static func mnemonicToSeed(_ mnemonic: String) -> Data {
        let passwordStr = mnemonic.decomposedStringWithCanonicalMapping
        let saltStr = "mnemonic"

        guard let passwordData = passwordStr.data(using: .utf8),
              let saltData = saltStr.data(using: .utf8) else {
            return Data(repeating: 0, count: 64)
        }

        var result = [UInt8](repeating: 0, count: 64)
        let status = passwordData.withUnsafeBytes { passPtr -> Int32 in
            saltData.withUnsafeBytes { saltPtr -> Int32 in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passPtr.baseAddress?.assumingMemoryBound(to: CChar.self),
                    passwordData.count,
                    saltPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    saltData.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA512),
                    2048,
                    &result,
                    64
                )
            }
        }
        guard status == kCCSuccess else {
            return Data(result)
        }
        return Data(result)
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - 密钥派生
    // ──────────────────────────────────────────────────────────────────────

    /// 从助记词派生 Ed25519 签名密钥对
    /// 路径：m/44'/0'/0'/0/0
    public static func deriveSigningKey(mnemonic: String) -> KeyPair {
        let seed = mnemonicToSeed(mnemonic)
        let privateBytes = deriveHardened(seed: seed, path: [44, 0, 0, 0, 0])

        do {
            let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: privateBytes)
            let publicKey = privateKey.publicKey.rawRepresentation
            return KeyPair(privateKey: privateBytes, publicKey: Data(publicKey))
        } catch {
            // 如果派生的字节无效（极罕见），返回空占位
            return KeyPair(privateKey: privateBytes, publicKey: Data(repeating: 0, count: 32))
        }
    }

    /// 从助记词派生 X25519 ECDH 密钥对
    /// 路径：m/44'/1'/0'/0/0
    public static func deriveEcdhKey(mnemonic: String) -> KeyPair {
        let seed = mnemonicToSeed(mnemonic)
        let privateBytes = deriveHardened(seed: seed, path: [44, 1, 0, 0, 0])

        do {
            let privateKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: privateBytes)
            let publicKey = privateKey.publicKey.rawRepresentation
            return KeyPair(privateKey: privateBytes, publicKey: Data(publicKey))
        } catch {
            return KeyPair(privateKey: privateBytes, publicKey: Data(repeating: 0, count: 32))
        }
    }

    /// 从助记词完整派生 Identity（包含两对密钥）
    public static func deriveIdentity(mnemonic: String) throws -> Identity {
        guard validateMnemonic(mnemonic) else {
            throw SDKError.invalidMnemonic("无效的 BIP-39 助记词")
        }
        return Identity(
            mnemonic: mnemonic,
            signingKey: deriveSigningKey(mnemonic: mnemonic),
            ecdhKey: deriveEcdhKey(mnemonic: mnemonic)
        )
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - Ed25519 签名
    // ──────────────────────────────────────────────────────────────────────

    /// Ed25519 签名 challenge（用于 Challenge-Response 认证）
    public static func signChallenge(challenge: Data, privateKey: Data) throws -> Data {
        guard privateKey.count == 32 else {
            throw SDKError.encryptionFailed("Ed25519 私钥必须是 32 字节")
        }
        let privKey = try Curve25519.Signing.PrivateKey(rawRepresentation: privateKey)
        return try privKey.signature(for: challenge)
    }

    /// Ed25519 验签（对标 TS verifySignal / Android verifyChallenge）
    public static func verifyChallenge(message: Data, signature: Data, publicKey: Data) -> Bool {
        guard publicKey.count == 32 else { return false }
        guard let pubKey = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey) else {
            return false
        }
        return pubKey.isValidSignature(signature, for: message)
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - X25519 ECDH
    // ──────────────────────────────────────────────────────────────────────

    /// ECDH 计算共享密钥
    public static func computeSharedSecret(myPrivateKey: Data, theirPublicKey: Data) throws -> Data {
        guard myPrivateKey.count == 32 else {
            throw SDKError.encryptionFailed("X25519 私钥必须是 32 字节")
        }
        guard theirPublicKey.count == 32 else {
            throw SDKError.encryptionFailed("X25519 公钥必须是 32 字节")
        }
        let privKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: myPrivateKey)
        let pubKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: theirPublicKey)
        let sharedSecret = try privKey.sharedSecretFromKeyAgreement(with: pubKey)
        return sharedSecret.withUnsafeBytes { Data($0) }
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - 会话密钥派生
    // ──────────────────────────────────────────────────────────────────────

    /// HKDF-SHA256：将 SharedSecret 派生为 32 字节 AES-256 会话密钥
    /// salt = SHA-256(conversationId)，info = "securechat-session-v1"
    public static func deriveSessionKey(sharedSecret: Data, conversationId: String) throws -> Data {
        let convIdData = conversationId.data(using: .utf8) ?? Data()
        let salt = SHA256.hash(data: convIdData)
        let info = "securechat-session-v1".data(using: .utf8) ?? Data()
        return try hkdf(ikm: sharedSecret, salt: Data(salt), info: info, length: 32)
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - 安全码（MITM 防御）
    // ──────────────────────────────────────────────────────────────────────

    /// 计算 60 字符安全码（用于 UI 展示，用户手动比对防 MITM）
    /// 算法：SHA-256(min(pubA, pubB) ‖ max(pubA, pubB))[0..30] → hex
    public static func computeSecurityCode(myEcdhPublicKey: Data, theirEcdhPublicKey: Data) -> String {
        let cmp = compareData(myEcdhPublicKey, theirEcdhPublicKey)
        let (first, second) = cmp <= 0
            ? (myEcdhPublicKey, theirEcdhPublicKey)
            : (theirEcdhPublicKey, myEcdhPublicKey)
        let concat = first + second
        let hash = SHA256.hash(data: concat)
        let bytes = [UInt8](Data(hash)[0..<30])
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - 内部工具：SLIP-0010 硬化派生
    // ──────────────────────────────────────────────────────────────────────

    private static func deriveHardened(seed: Data, path: [UInt32]) -> Data {
        let hmacKey = "ed25519 seed".data(using: .utf8) ?? Data()
        var key = hmacSHA512(key: hmacKey, data: seed)

        for index in path {
            let hardened = index | 0x80000000
            var buf = Data(count: 37)
            buf[0] = 0x00
            buf.replaceSubrange(1..<33, with: key[0..<32])
            var hardInt = hardened.bigEndian
            withUnsafeBytes(of: &hardInt) { buf.replaceSubrange(33..<37, with: $0) }
            key = hmacSHA512(key: key[32..<64], data: buf)
        }

        return key[0..<32]
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - 密码学原语
    // ──────────────────────────────────────────────────────────────────────

    private static func hmacSHA512(key: Data, data: Data) -> Data {
        var hmac = HMAC<SHA512>(key: SymmetricKey(data: key))
        hmac.update(data: data)
        return Data(hmac.finalize())
    }

    private static func hkdf(ikm: Data, salt: Data, info: Data, length: Int) throws -> Data {
        // Extract
        var prk = HMAC<SHA256>(key: SymmetricKey(data: salt))
        prk.update(data: ikm)
        let prkBytes = Data(prk.finalize())

        // Expand
        var result = Data(capacity: length)
        var prev = Data()
        var counter: UInt8 = 1

        while result.count < length {
            var hmacExpand = HMAC<SHA256>(key: SymmetricKey(data: prkBytes))
            hmacExpand.update(data: prev)
            hmacExpand.update(data: info)
            hmacExpand.update(data: Data([counter]))
            prev = Data(hmacExpand.finalize())
            let toCopy = min(prev.count, length - result.count)
            result.append(prev[0..<toCopy])
            counter += 1
        }

        return result
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - BIP-39 辅助函数
    // ──────────────────────────────────────────────────────────────────────

    private static func mnemonicFromEntropy(_ entropy: [UInt8]) -> String {
        precondition(entropy.count == 16, "Entropy must be 16 bytes")

        let entropyData = Data(entropy)
        let checksum = SHA256.hash(data: entropyData)
        let checksumByte = [UInt8](checksum)[0]
        let checksumBits = checksumByte >> 4  // 前 4 位

        var bits = ""
        for byte in entropy {
            bits += String(byte, radix: 2).leftPadded(toLength: 8)
        }
        bits += String(checksumBits, radix: 2).leftPadded(toLength: 4)

        let wordList = BIP39Wordlist.words
        var mnemonic: [String] = []
        var i = bits.startIndex
        while i < bits.endIndex {
            let end = bits.index(i, offsetBy: 11, limitedBy: bits.endIndex) ?? bits.endIndex
            let chunk = String(bits[i..<end])
            if chunk.count == 11, let idx = UInt16(chunk, radix: 2), Int(idx) < wordList.count {
                mnemonic.append(wordList[Int(idx)])
            }
            i = end
        }

        return mnemonic.joined(separator: " ")
    }

    private static func wordsToEntropy(_ words: [String]) -> [UInt8]? {
        guard words.count == 12 else { return nil }

        let wordList = BIP39Wordlist.words
        var bits = ""
        for word in words {
            guard let index = wordList.firstIndex(of: word) else { return nil }
            bits += String(index, radix: 2).leftPadded(toLength: 11)
        }

        let entropyBits = String(bits.prefix(128))
        let checksumBits = String(bits.dropFirst(128))

        var entropy: [UInt8] = []
        var j = entropyBits.startIndex
        while j < entropyBits.endIndex {
            let end = entropyBits.index(j, offsetBy: 8, limitedBy: entropyBits.endIndex) ?? entropyBits.endIndex
            let chunk = String(entropyBits[j..<end])
            if let byte = UInt8(chunk, radix: 2) {
                entropy.append(byte)
            }
            j = end
        }

        guard entropy.count == 16 else { return nil }

        let entropyData = Data(entropy)
        let checksum = SHA256.hash(data: entropyData)
        let expectedBits = String([UInt8](checksum)[0] >> 4, radix: 2).leftPadded(toLength: 4)

        return expectedBits == checksumBits ? entropy : nil
    }

    private static func generateFallbackMnemonic() -> String {
        let entropy: [UInt8] = (0..<16).map { _ in UInt8.random(in: UInt8.min...UInt8.max) }
        return mnemonicFromEntropy(entropy)
    }

    private static func compareData(_ a: Data, _ b: Data) -> Int {
        let minLen = min(a.count, b.count)
        for i in 0..<minLen {
            if a[i] != b[i] { return Int(a[i]) - Int(b[i]) }
        }
        return a.count - b.count
    }
}

// ──────────────────────────────────────────────────────────────────────────
// MARK: - 数据结构
// ──────────────────────────────────────────────────────────────────────────

/// 密钥对（对标 TS/Android SDK KeyPair）
public struct KeyPair: Equatable {
    public let privateKey: Data
    public let publicKey: Data

    public init(privateKey: Data, publicKey: Data) {
        self.privateKey = privateKey
        self.publicKey = publicKey
    }
}

/// 完整身份（对标 TS/Android SDK Identity）
public struct Identity: Equatable {
    public let mnemonic: String
    public let signingKey: KeyPair
    public let ecdhKey: KeyPair

    public init(mnemonic: String, signingKey: KeyPair, ecdhKey: KeyPair) {
        self.mnemonic = mnemonic
        self.signingKey = signingKey
        self.ecdhKey = ecdhKey
    }
}

// ──────────────────────────────────────────────────────────────────────────
// MARK: - BIP-39 词库（从 Bundle 资源加载）
// ──────────────────────────────────────────────────────────────────────────

private enum BIP39Wordlist {
    static let words: [String] = {
        guard let url = Bundle.module.url(forResource: "bip39-english", withExtension: "txt"),
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }
        return contents.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }()
}

// ──────────────────────────────────────────────────────────────────────────
// MARK: - String 工具扩展
// ──────────────────────────────────────────────────────────────────────────

private extension String {
    func leftPadded(toLength length: Int, withPad pad: Character = "0") -> String {
        guard self.count < length else { return self }
        return String(repeating: pad, count: length - self.count) + self
    }
}
