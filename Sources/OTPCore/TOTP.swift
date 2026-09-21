import CryptoKit
import Foundation

public struct OTPError: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public enum OTPAlgorithm: String, Codable {
    case sha1 = "SHA1"
    case sha256 = "SHA256"
    case sha512 = "SHA512"

    public init(parsing raw: String) throws {
        guard let value = OTPAlgorithm(rawValue: raw.uppercased()) else {
            throw OTPError("지원하지 않는 알고리즘입니다: \(raw) (SHA1/SHA256/SHA512)")
        }
        self = value
    }
}

/// RFC 6238 TOTP.
public struct TOTP {
    public let secret: Data
    public let digits: Int
    public let period: Int
    public let algorithm: OTPAlgorithm

    public init(secret: Data, digits: Int = 6, period: Int = 30, algorithm: OTPAlgorithm = .sha1) throws {
        guard (6...8).contains(digits) else {
            throw OTPError("digits 는 6~8 만 지원합니다: \(digits)")
        }
        guard period > 0 else {
            throw OTPError("period 는 1 이상이어야 합니다: \(period)")
        }
        self.secret = secret
        self.digits = digits
        self.period = period
        self.algorithm = algorithm
    }

    /// 현재 구간이 끝나기까지 남은 초.
    public func secondsRemaining(at date: Date = Date()) -> Int {
        period - Int(date.timeIntervalSince1970) % period
    }

    public func code(at date: Date = Date()) -> String {
        let counter = UInt64(date.timeIntervalSince1970) / UInt64(period)
        var bigEndian = counter.bigEndian
        let message = withUnsafeBytes(of: &bigEndian) { Data($0) }
        let key = SymmetricKey(data: secret)

        let mac: Data
        switch algorithm {
        case .sha1:
            mac = Data(HMAC<Insecure.SHA1>.authenticationCode(for: message, using: key))
        case .sha256:
            mac = Data(HMAC<SHA256>.authenticationCode(for: message, using: key))
        case .sha512:
            mac = Data(HMAC<SHA512>.authenticationCode(for: message, using: key))
        }

        // RFC 4226 dynamic truncation — 마지막 바이트 하위 4비트가 시작 오프셋이다.
        let offset = Int(mac[mac.count - 1] & 0x0F)
        let truncated = (UInt32(mac[offset] & 0x7F) << 24)
            | (UInt32(mac[offset + 1]) << 16)
            | (UInt32(mac[offset + 2]) << 8)
            | UInt32(mac[offset + 3])

        var modulus: UInt32 = 1
        for _ in 0..<digits { modulus *= 10 }
        return String(format: "%0\(digits)u", truncated % modulus)
    }
}
