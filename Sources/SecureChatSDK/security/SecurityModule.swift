import Foundation

/// 安全模块 — MITM 防御（对标 Android SecurityModule）
public struct SecurityModule {

    /// 计算安全码
    public static func computeSecurityCode(myEcdhPublicKey: Data, theirEcdhPublicKey: Data) -> String {
        return KeyDerivation.computeSecurityCode(myEcdhPublicKey: myEcdhPublicKey, theirEcdhPublicKey: theirEcdhPublicKey)
    }

    /// 获取安全码
    public static func getSecurityCode(
        contactId: String,
        myEcdhPublicKey: Data,
        theirEcdhPublicKey: Data
    ) -> SecurityCode {
        let code = computeSecurityCode(myEcdhPublicKey: myEcdhPublicKey, theirEcdhPublicKey: theirEcdhPublicKey)
        return SecurityCode(code: code, generatedAt: Date())
    }

    /// 验证安全码（用户手动比对）
    public static func verifySecurityCode(
        expected: String,
        actual: String
    ) -> Bool {
        // 简单的直接比对（完整版可能需要模糊匹配）
        return expected == actual
    }
}
