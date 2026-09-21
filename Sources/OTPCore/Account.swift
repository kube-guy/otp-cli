import Foundation

/// Keychain 에 JSON 으로 저장되는 계정 정보.
public struct Account: Codable {
    public var secret: String            // Base32
    public var digits: Int = 6
    public var period: Int = 30
    public var algorithm: OTPAlgorithm = .sha1
    public var issuer: String?

    public init(
        secret: String,
        digits: Int = 6,
        period: Int = 30,
        algorithm: OTPAlgorithm = .sha1,
        issuer: String? = nil
    ) {
        self.secret = secret
        self.digits = digits
        self.period = period
        self.algorithm = algorithm
        self.issuer = issuer
    }

    public func totp() throws -> TOTP {
        try TOTP(
            secret: Base32.decode(secret),
            digits: digits,
            period: period,
            algorithm: algorithm
        )
    }

    public func encoded() throws -> String {
        let data = try JSONEncoder().encode(self)
        guard let json = String(data: data, encoding: .utf8) else {
            throw OTPError("계정 정보를 인코딩하지 못했습니다.")
        }
        return json
    }

    public static func decode(_ raw: String) throws -> Account {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8) else {
            throw OTPError("Keychain 값을 읽지 못했습니다.")
        }
        return try JSONDecoder().decode(Account.self, from: data)
    }

    /// `otpauth://totp/Issuer:account?secret=...&digits=6&period=30&algorithm=SHA1`
    public static func parse(uri: String) throws -> (name: String?, account: Account) {
        guard let components = URLComponents(string: uri),
              components.scheme?.lowercased() == "otpauth"
        else {
            throw OTPError("otpauth:// 형식이 아닙니다.")
        }
        guard components.host?.lowercased() == "totp" else {
            throw OTPError("TOTP 만 지원합니다. (HOTP 는 미지원)")
        }

        let items = components.queryItems ?? []
        func value(_ key: String) -> String? {
            items.first { $0.name.lowercased() == key }?.value
        }

        guard let secret = value("secret"), !secret.isEmpty else {
            throw OTPError("URI 에 secret 파라미터가 없습니다.")
        }

        var account = Account(secret: secret)
        if let digits = value("digits"), let parsed = Int(digits) { account.digits = parsed }
        if let period = value("period"), let parsed = Int(period) { account.period = parsed }
        if let algorithm = value("algorithm") { account.algorithm = try OTPAlgorithm(parsing: algorithm) }
        account.issuer = value("issuer")

        // path 는 "/Issuer:account" 또는 "/account" 형태다.
        var label = components.path
        if label.hasPrefix("/") { label.removeFirst() }
        label = label.removingPercentEncoding ?? label

        var name: String? = label.isEmpty ? nil : label
        if let colon = label.firstIndex(of: ":") {
            let issuerPart = String(label[label.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
            let accountPart = String(label[label.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if account.issuer == nil, !issuerPart.isEmpty { account.issuer = issuerPart }
            name = accountPart.isEmpty ? nil : accountPart
        }

        // 설정이 유효한지 여기서 한 번 확인해 등록 시점에 실패하도록 한다.
        _ = try account.totp()
        return (name, account)
    }
}
