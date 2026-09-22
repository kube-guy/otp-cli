import Foundation

/// Google Authenticator 의 "계정 내보내기" QR (`otpauth-migration://offline?data=...`) 을 읽는다.
///
/// 내용은 base64 로 감싼 protobuf 이고 스키마는 아래와 같다. 계정 여러 개가 한 QR 에 들어간다.
///
///     message MigrationPayload { repeated OtpParameters otp_parameters = 1; ... }
///     message OtpParameters {
///         bytes secret = 1; string name = 2; string issuer = 3;
///         Algorithm algorithm = 4;  // 1=SHA1 2=SHA256 3=SHA512 4=MD5
///         DigitCount digits = 5;    // 1=SIX 2=EIGHT
///         OtpType type = 6;         // 1=HOTP 2=TOTP
///     }
///
/// 필요한 필드만 읽는 최소 구현이라 protobuf 의존성이 없다.
public enum Migration {
    public struct Entry {
        public let name: String
        public let account: Account
    }

    public static func isMigrationURI(_ text: String) -> Bool {
        text.lowercased().hasPrefix("otpauth-migration://")
    }

    public static func parse(uri: String) throws -> [Entry] {
        guard let components = URLComponents(string: uri),
              let encoded = components.queryItems?.first(where: { $0.name == "data" })?.value
        else {
            throw OTPError("내보내기 QR 에서 data 파라미터를 찾지 못했습니다.")
        }

        // URL 안전 문자로 치환된 경우까지 받아들이고 패딩을 복원한다.
        var base64 = encoded
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }

        guard let payload = Data(base64Encoded: base64) else {
            throw OTPError("내보내기 데이터를 해석하지 못했습니다.")
        }

        var entries: [Entry] = []
        var reader = Reader(payload)
        while let field = try reader.nextField() {
            // otp_parameters = 1 (length-delimited)
            if field.number == 1, case .bytes(let data) = field.value {
                if let entry = try parseParameters(data) { entries.append(entry) }
            }
        }

        guard !entries.isEmpty else {
            throw OTPError("내보내기 QR 에서 TOTP 계정을 찾지 못했습니다. (HOTP 는 지원하지 않습니다)")
        }
        return entries
    }

    private static func parseParameters(_ data: Data) throws -> Entry? {
        var secret = Data()
        var name = ""
        var issuer = ""
        var algorithm = OTPAlgorithm.sha1
        var digits = 6
        var isTOTP = true

        var reader = Reader(data)
        while let field = try reader.nextField() {
            switch (field.number, field.value) {
            case (1, .bytes(let value)):
                secret = value
            case (2, .bytes(let value)):
                name = String(data: value, encoding: .utf8) ?? ""
            case (3, .bytes(let value)):
                issuer = String(data: value, encoding: .utf8) ?? ""
            case (4, .varint(let value)):
                switch value {
                case 2: algorithm = .sha256
                case 3: algorithm = .sha512
                case 4: throw OTPError("MD5 알고리즘은 지원하지 않습니다.")
                default: algorithm = .sha1
                }
            case (5, .varint(let value)):
                digits = (value == 2) ? 8 : 6
            case (6, .varint(let value)):
                // 1=HOTP 2=TOTP. 0 은 미지정인데 실제로는 TOTP 로 쓰인다.
                isTOTP = (value != 1)
            default:
                break
            }
        }

        guard isTOTP else { return nil }  // HOTP 는 건너뛴다
        guard !secret.isEmpty else { return nil }

        let account = Account(
            secret: base32Encode(secret),
            digits: digits,
            period: 30,  // 내보내기 형식에 period 가 없다. Google Authenticator 는 30초 고정이다.
            algorithm: algorithm,
            issuer: issuer.isEmpty ? nil : issuer
        )
        // 설정이 유효한지 확인해 등록 전에 걸러낸다.
        _ = try account.totp()

        let label = name.isEmpty ? issuer : name
        return Entry(name: suggestedName(label: label, issuer: issuer), account: account)
    }

    /// "Issuer:account" 또는 "account" 라벨에서 쓰기 좋은 이름을 만든다.
    private static func suggestedName(label: String, issuer: String) -> String {
        var text = label
        if let colon = text.firstIndex(of: ":") {
            text = String(text[text.index(after: colon)...])
        }
        text = text.trimmingCharacters(in: .whitespaces)
        let base = issuer.isEmpty ? text : issuer
        let cleaned = base.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
        return cleaned.isEmpty ? "imported" : cleaned
    }

    private static func base32Encode(_ data: Data) -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        var output = ""
        var buffer = 0
        var bits = 0
        for byte in data {
            buffer = (buffer << 8) | Int(byte)
            bits += 8
            while bits >= 5 {
                bits -= 5
                output.append(alphabet[(buffer >> bits) & 0x1F])
            }
        }
        if bits > 0 {
            output.append(alphabet[(buffer << (5 - bits)) & 0x1F])
        }
        return output
    }

    // MARK: - 최소 protobuf 리더

    private enum Value {
        case varint(UInt64)
        case bytes(Data)
    }

    private struct Field {
        let number: Int
        let value: Value
    }

    private struct Reader {
        private let data: Data
        private var index: Data.Index

        init(_ data: Data) {
            self.data = data
            self.index = data.startIndex
        }

        private mutating func readVarint() throws -> UInt64 {
            var result: UInt64 = 0
            var shift: UInt64 = 0
            while index < data.endIndex {
                let byte = data[index]
                index = data.index(after: index)
                result |= UInt64(byte & 0x7F) << shift
                if byte & 0x80 == 0 { return result }
                shift += 7
                if shift > 63 { throw OTPError("내보내기 데이터가 손상되었습니다.") }
            }
            throw OTPError("내보내기 데이터가 중간에 끊겼습니다.")
        }

        mutating func nextField() throws -> Field? {
            guard index < data.endIndex else { return nil }
            let key = try readVarint()
            let number = Int(key >> 3)
            let wireType = Int(key & 0x7)

            switch wireType {
            case 0:
                return Field(number: number, value: .varint(try readVarint()))
            case 2:
                let length = Int(try readVarint())
                guard length >= 0, data.index(index, offsetBy: length, limitedBy: data.endIndex) != nil
                else { throw OTPError("내보내기 데이터의 길이 정보가 잘못되었습니다.") }
                let end = data.index(index, offsetBy: length)
                let slice = Data(data[index..<end])
                index = end
                return Field(number: number, value: .bytes(slice))
            case 5:  // 32bit
                guard data.index(index, offsetBy: 4, limitedBy: data.endIndex) != nil else {
                    throw OTPError("내보내기 데이터가 중간에 끊겼습니다.")
                }
                index = data.index(index, offsetBy: 4)
                return Field(number: number, value: .varint(0))
            case 1:  // 64bit
                guard data.index(index, offsetBy: 8, limitedBy: data.endIndex) != nil else {
                    throw OTPError("내보내기 데이터가 중간에 끊겼습니다.")
                }
                index = data.index(index, offsetBy: 8)
                return Field(number: number, value: .varint(0))
            default:
                throw OTPError("지원하지 않는 데이터 형식입니다. (wire type \(wireType))")
            }
        }
    }
}
