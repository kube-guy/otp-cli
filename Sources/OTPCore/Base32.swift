import Foundation

/// RFC 4648 Base32. TOTP 시크릿은 이 인코딩으로 배포된다.
public enum Base32 {
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    private static let reverse: [Character: UInt8] = {
        var table: [Character: UInt8] = [:]
        for (index, character) in alphabet.enumerated() {
            table[character] = UInt8(index)
        }
        return table
    }()

    /// 사람이 옮겨적은 시크릿을 받아들이기 위해 공백·하이픈·패딩을 무시하고 소문자도 허용한다.
    public static func decode(_ input: String) throws -> Data {
        let cleaned = input
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "=", with: "")
            .uppercased()

        guard !cleaned.isEmpty else {
            throw OTPError("시크릿이 비어 있습니다.")
        }

        var bits: UInt32 = 0
        var bitCount: UInt32 = 0
        var output = Data()

        for character in cleaned {
            guard let value = reverse[character] else {
                throw OTPError("Base32 에 없는 문자가 있습니다: '\(character)'")
            }
            bits = (bits << 5) | UInt32(value)
            bitCount += 5
            if bitCount >= 8 {
                bitCount -= 8
                output.append(UInt8((bits >> bitCount) & 0xFF))
            }
        }

        guard !output.isEmpty else {
            throw OTPError("시크릿이 너무 짧습니다.")
        }
        return output
    }
}
