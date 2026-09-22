import AppKit
import Foundation
import OTPCore

/// 단축키를 기다리다가, 눌리면 포커스된 입력란에 코드를 타이핑하는 상주 프로세스.
///
/// 등록이 여러 개면 마우스 위치에 목록을 띄워 고르게 한다. 목록이 뜨는 동안에는
/// 포커스가 이쪽으로 넘어오므로, 고른 뒤 원래 앱을 다시 활성화하고 타이핑한다.
enum Agent {
    private static let picker = Picker()

    static func run(hotKeyText: String, accountOverride: String?) throws -> Never {
        let combo = try HotKey.parse(hotKeyText)

        // 등록이 하나도 없으면 단축키를 눌렀을 때야 알게 되므로 여기서 먼저 막는다.
        let names = Keychain.names()
        guard !names.isEmpty else {
            throw OTPError("등록된 항목이 없습니다. `otp add <이름>` 으로 먼저 등록하세요.")
        }
        if let accountOverride {
            guard names.contains(accountOverride) else {
                throw OTPError("'\(accountOverride)' 이(가) 등록되어 있지 않습니다.")
            }
        }

        if !Typing.isTrusted() {
            FileHandle.standardError.write(Data("""
                손쉬운 사용 권한이 없어 코드를 타이핑할 수 없습니다.
                시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용 에서 otp 를 허용한 뒤
                이 명령을 다시 실행하세요.

                """.utf8))
            _ = Typing.isTrusted(prompt: true)
        }

        let hotKey = HotKey()
        try hotKey.register(combo) { handleHotKey(accountOverride: accountOverride) }

        if let accountOverride {
            print("단축키 \(combo.display) 대기 중 — 계정 '\(accountOverride)' 고정 · Ctrl+C 로 종료")
        } else {
            print("단축키 \(combo.display) 대기 중 — 등록 \(names.count)개 · Ctrl+C 로 종료")
            if names.count > 1 {
                print("여러 개라 단축키를 누르면 목록이 뜹니다. 숫자키 1~9 로 바로 고를 수 있습니다.")
            }
        }
        print("OTP 입력란에 커서를 두고 단축키를 누르면 코드가 입력됩니다.")

        // Carbon 단축키는 애플리케이션 이벤트 루프가 있어야 전달된다.
        // .accessory 는 Dock 아이콘과 메뉴 막대 없이 도는 정책이면서 메뉴는 띄울 수 있다.
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.run()
        fatalError("unreachable")
    }

    private static func handleHotKey(accountOverride: String?) {
        do {
            let name: String
            if let accountOverride {
                name = accountOverride
            } else {
                let names = Keychain.names()
                guard !names.isEmpty else {
                    throw OTPError("등록된 항목이 없습니다.")
                }
                if names.count == 1 {
                    name = names[0]
                } else {
                    // 목록이 뜨면 포커스가 넘어오므로 원래 앱을 기억해 둔다.
                    let previous = NSWorkspace.shared.frontmostApplication
                    guard let picked = picker.pick(names: names, defaultName: Settings.defaultAccount)
                    else { return }  // 취소
                    name = picked
                    restoreFocus(to: previous)
                }
            }

            let code = try Keychain.load(name: name).totp().code()
            Typing.type(code)
        } catch {
            NSSound.beep()
            FileHandle.standardError.write(Data("otp: \(error.localizedDescription)\n".utf8))
        }
    }

    /// 목록을 고른 뒤 원래 앱으로 포커스를 돌려준다.
    /// 활성화가 반영되기 전에 타이핑하면 입력이 엉뚱한 곳으로 가므로 잠깐 기다린다.
    private static func restoreFocus(to application: NSRunningApplication?) {
        guard let application, !application.isActive else { return }
        application.activate(options: [])
        for _ in 0..<40 {  // 최대 약 0.4초
            if application.isActive { break }
            Thread.sleep(forTimeInterval: 0.01)
        }
        Thread.sleep(forTimeInterval: 0.05)
    }
}
