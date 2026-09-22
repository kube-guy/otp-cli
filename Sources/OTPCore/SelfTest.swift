import Foundation

/// RFC 6238 Appendix B 테스트 벡터 및 파싱 검증.
///
/// XCTest 는 전체 Xcode 에만 포함되어 Command Line Tools 환경에서는 쓸 수 없다.
/// 검증을 바이너리 안에 두면 `otp selftest` 로 어디서든, 그리고 `brew test` 에서도
/// 같은 검사를 돌릴 수 있다.
public enum SelfTest {
    public struct Result {
        public let name: String
        public let passed: Bool
        public let detail: String
    }

    // ASCII "12345678901234567890" 을 알고리즘별 키 길이만큼 반복한 값
    private static let sha1Secret = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
    private static let sha256Secret = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZA"
    private static let sha512Secret =
        "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNA"

    private static let vectors: [(time: TimeInterval, sha1: String, sha256: String, sha512: String)] = [
        (59, "94287082", "46119246", "90693936"),
        (1111111109, "07081804", "68084774", "25091201"),
        (1111111111, "14050471", "67062674", "99943326"),
        (1234567890, "89005924", "91819424", "93441116"),
        (2000000000, "69279037", "90698825", "38618901"),
        (20000000000, "65353130", "77737706", "47863826"),
    ]

    private static func code(
        _ secret: String, _ algorithm: OTPAlgorithm, at seconds: TimeInterval, digits: Int = 8
    ) throws -> String {
        let totp = try TOTP(
            secret: Base32.decode(secret), digits: digits, period: 30, algorithm: algorithm)
        return totp.code(at: Date(timeIntervalSince1970: seconds))
    }

    public static func run() -> [Result] {
        var results: [Result] = []

        func check(_ name: String, _ body: () throws -> String?) {
            do {
                if let failure = try body() {
                    results.append(Result(name: name, passed: false, detail: failure))
                } else {
                    results.append(Result(name: name, passed: true, detail: ""))
                }
            } catch {
                results.append(Result(name: name, passed: false, detail: "예외: \(error)"))
            }
        }

        for (algorithm, secret, expected) in [
            (OTPAlgorithm.sha1, sha1Secret, vectors.map(\.sha1)),
            (OTPAlgorithm.sha256, sha256Secret, vectors.map(\.sha256)),
            (OTPAlgorithm.sha512, sha512Secret, vectors.map(\.sha512)),
        ] {
            check("RFC 6238 \(algorithm.rawValue) 벡터 6건") {
                for (index, vector) in vectors.enumerated() {
                    let got = try code(secret, algorithm, at: vector.time)
                    if got != expected[index] {
                        return "t=\(Int(vector.time)) 기대 \(expected[index]) 실제 \(got)"
                    }
                }
                return nil
            }
        }

        check("6자리는 8자리 벡터의 하위 6자리") {
            let got = try code(sha1Secret, .sha1, at: 59, digits: 6)
            return got == "287082" ? nil : "기대 287082 실제 \(got)"
        }

        check("남은 시간 계산") {
            let totp = try TOTP(secret: Base32.decode(sha1Secret))
            let cases: [(TimeInterval, Int)] = [(0, 30), (29, 1), (30, 30)]
            for (time, want) in cases {
                let got = totp.secondsRemaining(at: Date(timeIntervalSince1970: time))
                if got != want { return "t=\(Int(time)) 기대 \(want) 실제 \(got)" }
            }
            return nil
        }

        check("Base32 공백·하이픈·소문자·패딩 허용") {
            let plain = try Base32.decode("GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ")
            let messy = try Base32.decode("gezd gnbv gy3t qojq-GEZD-GNBV-GY3T-QOJQ==")
            return plain == messy ? nil : "정규화 결과가 다릅니다"
        }

        check("Base32 잘못된 입력 거부") {
            if (try? Base32.decode("GEZD1NBV")) != nil { return "'1' 을 통과시킴" }
            if (try? Base32.decode("")) != nil { return "빈 문자열을 통과시킴" }
            return nil
        }

        check("digits·period 범위 검증") {
            let secret = try Base32.decode(sha1Secret)
            if (try? TOTP(secret: secret, digits: 5)) != nil { return "digits=5 를 통과시킴" }
            if (try? TOTP(secret: secret, digits: 9)) != nil { return "digits=9 를 통과시킴" }
            if (try? TOTP(secret: secret, period: 0)) != nil { return "period=0 을 통과시킴" }
            return nil
        }

        check("otpauth URI 파싱") {
            let uri = "otpauth://totp/GitLab:1112384?secret=\(sha1Secret)"
                + "&issuer=GitLab&digits=6&period=30&algorithm=SHA1"
            let parsed = try Account.parse(uri: uri)
            guard parsed.name == "1112384" else { return "이름 파싱 실패: \(parsed.name ?? "nil")" }
            guard parsed.account.issuer == "GitLab" else { return "issuer 파싱 실패" }
            guard parsed.account.digits == 6, parsed.account.period == 30 else { return "파라미터 파싱 실패" }
            return nil
        }

        check("otpauth 기본값 적용") {
            let parsed = try Account.parse(uri: "otpauth://totp/plain?secret=\(sha1Secret)")
            let a = parsed.account
            return (a.digits == 6 && a.period == 30 && a.algorithm == .sha1)
                ? nil : "기본값이 6/30/SHA1 이 아님"
        }

        check("HOTP·잘못된 scheme·secret 누락 거부") {
            if (try? Account.parse(uri: "otpauth://hotp/x?secret=\(sha1Secret)&counter=1")) != nil {
                return "HOTP 를 통과시킴"
            }
            if (try? Account.parse(uri: "https://example.com/?secret=\(sha1Secret)")) != nil {
                return "https scheme 을 통과시킴"
            }
            if (try? Account.parse(uri: "otpauth://totp/x")) != nil { return "secret 없는 URI 를 통과시킴" }
            return nil
        }

        check("Keychain 저장 형식 왕복") {
            let account = Account(
                secret: sha1Secret, digits: 8, period: 60, algorithm: .sha256, issuer: "X")
            let restored = try Account.decode(account.encoded())
            guard restored.secret == account.secret, restored.digits == 8,
                  restored.period == 60, restored.algorithm == .sha256, restored.issuer == "X"
            else { return "복원된 값이 다릅니다" }
            return nil
        }

        check("단축키 문자열 파싱") {
            let combo = try HotKey.parse("cmd+opt+o")
            guard combo.keyCode == 31 else { return "keyCode 가 31(o) 이 아님: \(combo.keyCode)" }
            guard combo.display == "⌘⌥O" else { return "표시 문자열: \(combo.display)" }
            if (try? HotKey.parse("o")) != nil { return "수정키 없는 조합을 통과시킴" }
            if (try? HotKey.parse("cmd+opt")) != nil { return "일반 키 없는 조합을 통과시킴" }
            if (try? HotKey.parse("cmd+오")) != nil { return "없는 키를 통과시킴" }
            if (try? HotKey.parse("cmd+a+b")) != nil { return "일반 키 두 개를 통과시킴" }

            // 문자·숫자는 다른 앱과 겹치기 쉬워 기호키도 받아야 한다
            for key in ["/", "-", "=", "[", "]", ";", "'", ",", ".", "\\", "`", "space", "f13"] {
                let combo = try? HotKey.parse("ctrl+opt+\(key)")
                if key == "f13" {
                    if combo != nil { return "지원하지 않는 f13 을 통과시킴" }
                } else if combo == nil {
                    return "기호키 파싱 실패: \(key)"
                }
            }
            return nil
        }

        check("선택 목록 정렬 — 기본 계정이 맨 앞") {
            let names = ["aws", "gitlab", "vpn"]
            let ordered = Settings.orderedForPicker(names: names, defaultName: "vpn")
            guard ordered == ["vpn", "aws", "gitlab"] else { return "결과: \(ordered)" }
            guard Settings.orderedForPicker(names: names, defaultName: nil) == names else {
                return "기본 계정이 없을 때 순서가 바뀜"
            }
            guard Settings.orderedForPicker(names: names, defaultName: "없는이름") == names else {
                return "없는 기본 계정에서 순서가 바뀜"
            }
            guard Settings.orderedForPicker(names: [], defaultName: "x") == [] else {
                return "빈 목록 처리 실패"
            }
            return nil
        }

        check("QR 생성 → 디코드 왕복") {
            let uri = "otpauth://totp/GitLab:me?secret=\(sha1Secret)&issuer=GitLab&digits=6&period=30"
            guard let png = QRCode.generate(from: uri) else { return "QR 생성 실패" }
            let decoded = try QRCode.decode(imageData: png)
            guard decoded.contains(uri) else { return "디코드 결과가 원본과 다름: \(decoded)" }
            let parsed = try Account.parse(uri: decoded[0])
            guard parsed.account.secret == sha1Secret else { return "시크릿이 다름" }
            return nil
        }

        check("Google Authenticator 내보내기 파싱") {
            // OtpParameters { secret=1, name=2, issuer=3, algorithm=4(SHA1), digits=5(SIX), type=6(TOTP) }
            func lengthDelimited(_ field: UInt8, _ payload: Data) -> Data {
                var out = Data([(field << 3) | 2, UInt8(payload.count)])
                out.append(payload)
                return out
            }
            func varint(_ field: UInt8, _ value: UInt8) -> Data {
                Data([(field << 3) | 0, value])
            }

            var parameters = Data()
            parameters.append(lengthDelimited(1, Data("12345678901234567890".utf8)))  // secret
            parameters.append(lengthDelimited(2, Data("me@example.com".utf8)))        // name
            parameters.append(lengthDelimited(3, Data("GitLab".utf8)))                // issuer
            parameters.append(varint(4, 1))  // SHA1
            parameters.append(varint(5, 1))  // 6자리
            parameters.append(varint(6, 2))  // TOTP

            let payload = lengthDelimited(1, parameters)
            let encoded = payload.base64EncodedString()
                .addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
            let entries = try Migration.parse(uri: "otpauth-migration://offline?data=\(encoded)")

            guard entries.count == 1 else { return "계정 수: \(entries.count)" }
            let entry = entries[0]
            guard entry.account.secret == sha1Secret else {
                return "시크릿 복원 실패: \(entry.account.secret)"
            }
            guard entry.account.issuer == "GitLab" else { return "issuer: \(entry.account.issuer ?? "nil")" }
            guard entry.account.digits == 6, entry.account.algorithm == .sha1 else { return "파라미터 불일치" }
            guard entry.name == "gitlab" else { return "이름 제안: \(entry.name)" }

            // 복원한 시크릿으로 RFC 벡터가 재현되어야 한다
            let code = try entry.account.totp().code(at: Date(timeIntervalSince1970: 59))
            guard code == "287082" else { return "복원 시크릿의 코드가 다름: \(code)" }
            return nil
        }

        check("내보내기 형식 오류 처리") {
            if (try? Migration.parse(uri: "otpauth-migration://offline")) != nil { return "data 없는 URI 통과" }
            if (try? Migration.parse(uri: "otpauth-migration://offline?data=!!!")) != nil { return "잘못된 base64 통과" }
            guard Migration.isMigrationURI("otpauth-migration://offline?data=x") else { return "형식 판별 실패" }
            guard !Migration.isMigrationURI("otpauth://totp/x") else { return "일반 URI 를 내보내기로 오인" }
            return nil
        }

        return results
    }
}
