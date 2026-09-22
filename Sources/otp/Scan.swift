import AppKit
import Foundation
import OTPCore

/// QR 이미지를 읽어 계정을 등록한다. 디코딩은 전부 로컬에서 한다.
enum Scan {
    static func run(arguments: [String]) throws {
        let payloads: [String]
        let source: String

        if let path = arguments.first(where: { !$0.hasPrefix("-") }) {
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            payloads = try QRCode.decode(fileURL: url)
            source = url.lastPathComponent
        } else {
            guard let data = clipboardImageData() else {
                throw OTPError("""
                    클립보드에 이미지가 없습니다.
                      ⌃⌘⇧4 로 QR 영역을 클립보드에 캡처한 뒤 `otp scan` 을 실행하거나,
                      ⌘⇧4 로 저장한 파일 경로를 주세요: otp scan ~/Desktop/qr.png
                    """)
            }
            payloads = try QRCode.decode(imageData: data)
            source = "클립보드"
        }

        var registered = 0
        for payload in payloads {
            if Migration.isMigrationURI(payload) {
                registered += try registerMigration(payload)
            } else if payload.lowercased().hasPrefix("otpauth://") {
                registered += try registerSingle(payload)
            } else {
                FileHandle.standardError.write(
                    Data("OTP QR 이 아닌 코드는 건너뜁니다.\n".utf8))
            }
        }

        guard registered > 0 else {
            throw OTPError("\(source) 에서 등록할 계정을 찾지 못했습니다.")
        }
        print("\(registered)개 등록했습니다. `otp list` 로 확인하세요.")
    }

    private static func registerSingle(_ uri: String) throws -> Int {
        let parsed = try Account.parse(uri: uri)
        let name = uniqueName(from: parsed.name ?? parsed.account.issuer ?? "imported")
        try Keychain.save(name: name, account: parsed.account)
        report(name: name, account: parsed.account)
        return 1
    }

    private static func registerMigration(_ uri: String) throws -> Int {
        let entries = try Migration.parse(uri: uri)
        // 내보내기 QR 에는 여러 계정이 들어 있다. 무엇이 들어오는지 먼저 보여준다.
        print("내보내기 QR 에서 \(entries.count)개를 찾았습니다.")
        var count = 0
        for entry in entries {
            let name = uniqueName(from: entry.name)
            try Keychain.save(name: name, account: entry.account)
            report(name: name, account: entry.account)
            count += 1
        }
        return count
    }

    /// 이미 있는 이름이면 덮어쓰지 않고 뒤에 번호를 붙인다.
    private static func uniqueName(from raw: String) -> String {
        let base = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "-")
        let existing = Set(Keychain.names())
        guard existing.contains(base) else { return base.isEmpty ? "imported" : base }
        var index = 2
        while existing.contains("\(base)-\(index)") { index += 1 }
        return "\(base)-\(index)"
    }

    private static func report(name: String, account: Account) {
        var line = "  \(name)"
        if let issuer = account.issuer { line += "  (\(issuer))" }
        line += "  \(account.algorithm.rawValue) · \(account.digits)자리 · \(account.period)초"
        print(line)
    }

    private static func clipboardImageData() -> Data? {
        let pasteboard = NSPasteboard.general
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            if let data = pasteboard.data(forType: type) { return data }
        }
        // 파일을 복사한 경우
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
           let first = urls.first,
           let data = try? Data(contentsOf: first) {
            return data
        }
        return nil
    }
}
