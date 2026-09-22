import AppKit
import Foundation
import OTPCore

/// 단축키를 기다리다가, 눌리면 포커스된 입력란에 코드를 타이핑하는 상주 프로세스.
enum Agent {
    static func run(hotKeyText: String, accountOverride: String?) throws -> Never {
        let combo = try HotKey.parse(hotKeyText)

        // 등록된 계정이 있는지 먼저 확인해, 단축키를 눌렀을 때야 실패하는 상황을 막는다.
        let resolved = try accountOverride ?? Settings.resolveAccountName()
        _ = try Keychain.load(name: resolved)

        if !Typing.isTrusted() {
            FileHandle.standardError.write(Data("""
                손쉬운 사용 권한이 없어 코드를 타이핑할 수 없습니다.
                시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용 에서 otp 를 허용한 뒤
                이 명령을 다시 실행하세요.

                """.utf8))
            _ = Typing.isTrusted(prompt: true)
        }

        let hotKey = HotKey()
        try hotKey.register(combo) {
            do {
                let name = try accountOverride ?? Settings.resolveAccountName()
                let code = try Keychain.load(name: name).totp().code()
                Typing.type(code)
            } catch {
                NSSound.beep()
                FileHandle.standardError.write(
                    Data("otp: \(error.localizedDescription)\n".utf8))
            }
        }

        print("단축키 \(combo.display) 대기 중 — 계정 '\(resolved)' · Ctrl+C 로 종료")
        print("OTP 입력란에 커서를 두고 단축키를 누르면 코드가 입력됩니다.")

        // Carbon 단축키는 애플리케이션 이벤트 루프가 있어야 전달된다.
        // .prohibited 로 Dock 아이콘과 메뉴 막대 없이 백그라운드로만 돈다.
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        app.run()
        fatalError("unreachable")
    }
}
