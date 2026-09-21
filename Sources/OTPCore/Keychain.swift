import Foundation
import Security

/// 시크릿은 login keychain 에 generic password 로 저장한다.
///
/// 쓰기·읽기는 `/usr/bin/security` 를 거친다. Security 프레임워크로 직접 넣으면
/// 서명되지 않은 이 바이너리가 접근 주체가 되는데, 재빌드할 때마다 동일성이 깨져
/// 키체인 승인 창이 다시 뜬다. Apple 서명된 `security` 를 신뢰 주체로 고정하면
/// 한 번 허용한 뒤로는 묻지 않는다.
///
/// 목록 조회만 Security 프레임워크를 쓴다. 속성(계정 이름)만 읽고 비밀값은 요청하지
/// 않으므로 ACL 승인 대상이 아니다.
public enum Keychain {
    public static let service = "otp-cli"
    private static let securityPath = "/usr/bin/security"

    private static func run(_ arguments: [String], input: String? = nil) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: securityPath)
        process.arguments = arguments

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        if input != nil {
            process.standardInput = Pipe()
        }

        do {
            try process.run()
        } catch {
            throw OTPError("security 명령을 실행할 수 없습니다: \(error.localizedDescription)")
        }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(data: data, encoding: .utf8) ?? ""
        return (process.terminationStatus, text)
    }

    public static func save(name: String, account: Account) throws {
        let json = try account.encoded()
        // -U: 같은 이름이 있으면 덮어쓴다
        // -T: security 를 신뢰 주체로 지정해 이후 읽기에서 승인 창이 뜨지 않게 한다
        // -j: 키체인 접근 앱에 표시될 설명
        let result = try run([
            "add-generic-password",
            "-a", name,
            "-s", service,
            "-l", "\(service): \(name)",
            "-j", "otp-cli 가 관리하는 TOTP 시크릿",
            "-w", json,
            "-T", securityPath,
            "-U",
        ])
        guard result.status == 0 else {
            throw OTPError("Keychain 에 저장하지 못했습니다. (security exit \(result.status))")
        }
    }

    public static func load(name: String) throws -> Account {
        let result = try run(["find-generic-password", "-a", name, "-s", service, "-w"])
        guard result.status == 0 else {
            throw OTPError("'\(name)' 이(가) 등록되어 있지 않습니다. `otp add \(name)` 으로 먼저 등록하세요.")
        }
        return try Account.decode(result.output)
    }

    public static func delete(name: String) throws {
        let result = try run(["delete-generic-password", "-a", name, "-s", service])
        guard result.status == 0 else {
            throw OTPError("'\(name)' 을(를) 찾을 수 없습니다.")
        }
    }

    /// 등록된 이름 목록. 비밀값을 읽지 않으므로 승인 창이 뜨지 않는다.
    public static func names() -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: false,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]]
        else {
            return []
        }
        return items
            .compactMap { $0[kSecAttrAccount as String] as? String }
            .sorted()
    }
}
