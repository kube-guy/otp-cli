import Darwin
import OTPCore
import Foundation

let version = "0.6.0"

// brew services 로그처럼 파일로 리다이렉트되면 stdout 이 블록 버퍼링이라
// 상주 모드(agent)의 안내가 한참 뒤에야 보인다. 줄 단위로 내보낸다.
setvbuf(stdout, nil, _IOLBF, 0)

func usage() -> String {
    """
    usage: otp <이름> [--copy] [--watch]
           otp add <이름> [otpauth:// URI]
           otp list
           otp rename <옛이름> <새이름>
           otp remove <이름>
           otp agent [--hotkey <조합>] [--account <이름>]
           otp default [<이름>]
           otp hotkey [<조합>]
           otp scan [이미지경로]

    TOTP(RFC 6238) 코드를 생성합니다. 시크릿은 macOS Keychain 에 저장됩니다.

    명령:
      <이름>              현재 코드를 출력합니다
      add <이름> [URI]    시크릿을 등록합니다. URI 를 생략하면 화면에 표시하지 않고 입력받습니다
      scan [경로]          QR 이미지를 읽어 등록합니다. 경로를 생략하면 클립보드에서 읽습니다
      list                등록된 이름을 나열합니다
      selftest            RFC 6238 테스트 벡터로 코드 생성이 맞는지 검증합니다
      agent               단축키를 기다리다 포커스된 입력란에 코드를 타이핑합니다
      default [<이름>]     단축키가 쓸 기본 계정을 보거나 지정합니다
      hotkey [<조합>]      단축키를 보거나 바꿉니다. 예: otp hotkey "ctrl+opt+/"
      rename <옛> <새>    등록된 이름을 바꿉니다
      remove <이름>       등록을 삭제합니다

    옵션:
      -c, --copy          코드를 클립보드에 복사합니다
      -w, --watch         남은 시간과 함께 계속 갱신해 표시합니다 (Ctrl+C 로 종료)
      --hotkey <조합>     agent 가 쓸 단축키 (기본 cmd+opt+o). 예: "ctrl+shift+9"
      --account <이름>    agent 가 쓸 계정을 이번 실행에만 지정합니다
      -v, --version       버전을 출력합니다
      -h, --help          이 도움말을 출력합니다

    예:
      otp add gitlab                          시크릿을 붙여넣어 등록
      otp add gitlab "otpauth://totp/..."     QR 에서 얻은 URI 로 등록
      otp scan                                ⌃⌘⇧4 로 캡처한 QR 을 클립보드에서 읽어 등록
      otp scan ~/Desktop/qr.png               저장한 QR 이미지에서 등록
      otp gitlab --copy                       코드를 클립보드로
      otp default gitlab                      단축키가 쓸 기본 계정 지정
      brew services start otp                 단축키 대기를 로그인 시 자동 실행
    """
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("otp: \(message)\n".utf8))
    exit(1)
}

func copyToClipboard(_ text: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/pbcopy")
    let pipe = Pipe()
    process.standardInput = pipe
    guard (try? process.run()) != nil else { return }
    pipe.fileHandleForWriting.write(Data(text.utf8))
    pipe.fileHandleForWriting.closeFile()
    process.waitUntilExit()
}

/// 터미널에 남지 않도록 화면 표시 없이 입력받는다.
func readSecretly(prompt: String) -> String {
    guard let raw = getpass(prompt) else { return "" }
    return String(cString: raw).trimmingCharacters(in: .whitespacesAndNewlines)
}

// MARK: - 명령 구현

func commandAdd(arguments: [String]) throws {
    guard let name = arguments.first, !name.hasPrefix("-") else {
        throw OTPError("등록할 이름이 필요합니다. 예: otp add gitlab")
    }

    let given = arguments.dropFirst().first
    var account: Account
    var resolvedName = name

    if let given, given.lowercased().hasPrefix("otpauth://") {
        let parsed = try Account.parse(uri: given)
        account = parsed.account
        if let label = parsed.name {
            FileHandle.standardError.write(Data("URI 의 계정 이름: \(label)\n".utf8))
        }
    } else {
        let entered = given ?? readSecretly(prompt: "'\(name)' 의 시크릿 (화면에 표시되지 않습니다): ")
        guard !entered.isEmpty else {
            throw OTPError("시크릿이 입력되지 않았습니다.")
        }
        if entered.lowercased().hasPrefix("otpauth://") {
            let parsed = try Account.parse(uri: entered)
            account = parsed.account
        } else {
            account = Account(secret: entered)
            // 등록 시점에 Base32 와 설정이 유효한지 확인한다
            _ = try account.totp()
        }
    }

    if Keychain.names().contains(resolvedName) {
        FileHandle.standardError.write(Data("'\(resolvedName)' 은(는) 이미 있습니다. 덮어씁니다.\n".utf8))
    }

    try Keychain.save(name: resolvedName, account: account)

    let totp = try account.totp()
    print("등록했습니다: \(resolvedName)")
    print("  알고리즘 \(totp.algorithm.rawValue) · \(totp.digits)자리 · \(totp.period)초")
    if let issuer = account.issuer { print("  발급자 \(issuer)") }
    print("  지금 코드 \(totp.code())  (확인용 — 서비스에 표시된 값과 같아야 합니다)")
    resolvedName = ""
}

func commandHotKey(arguments: [String]) throws {
    guard let text = arguments.first else {
        let combo = try? HotKey.parse(Settings.hotKey)
        print("\(Settings.hotKey)\(combo.map { "  (\($0.display))" } ?? "")")
        return
    }
    // 저장 전에 파싱해 잘못된 조합이 들어가지 않게 한다.
    let combo = try HotKey.parse(text)
    Settings.hotKey = text
    print("단축키: \(text)  (\(combo.display))")
    print("이미 실행 중이면 다시 시작해야 반영됩니다: brew services restart otp")
}

func commandRename(arguments: [String]) throws {
    guard arguments.count >= 2 else {
        throw OTPError("사용법: otp rename <옛이름> <새이름>")
    }
    let oldName = arguments[0]
    let newName = arguments[1].trimmingCharacters(in: .whitespaces)

    guard !newName.isEmpty else { throw OTPError("새 이름이 비어 있습니다.") }
    guard oldName != newName else { throw OTPError("이름이 같습니다.") }

    let names = Keychain.names()
    guard names.contains(oldName) else {
        throw OTPError("'\(oldName)' 이(가) 등록되어 있지 않습니다.")
    }
    guard !names.contains(newName) else {
        throw OTPError("'\(newName)' 이(가) 이미 있습니다. 다른 이름을 쓰거나 먼저 지우세요.")
    }

    // 새 이름으로 저장이 끝난 뒤에 지운다. 중간에 실패해도 시크릿이 사라지지 않는다.
    let account = try Keychain.load(name: oldName)
    try Keychain.save(name: newName, account: account)
    try Keychain.delete(name: oldName)

    if Settings.defaultAccount == oldName {
        Settings.defaultAccount = newName
        print("이름을 바꿨습니다: \(oldName) → \(newName)  (기본 계정도 함께 변경)")
    } else {
        print("이름을 바꿨습니다: \(oldName) → \(newName)")
    }
}

func commandList() {
    let names = Keychain.names()
    if names.isEmpty {
        print("등록된 항목이 없습니다. `otp add <이름>` 으로 등록하세요.")
        return
    }
    for name in names { print(name) }
}

func commandRemove(arguments: [String]) throws {
    guard let name = arguments.first else {
        throw OTPError("삭제할 이름이 필요합니다. 예: otp remove gitlab")
    }
    try Keychain.delete(name: name)
    // 지운 이름이 기본 계정으로 남으면, 계정이 2개 이상일 때 단축키가 실패한다.
    if Settings.defaultAccount == name {
        Settings.defaultAccount = nil
        print("삭제했습니다: \(name)  (기본 계정 지정도 함께 해제)")
    } else {
        print("삭제했습니다: \(name)")
    }
}

func commandCode(name: String, copy: Bool, watch: Bool) throws {
    let account = try Keychain.load(name: name)
    let totp = try account.totp()

    if !watch {
        let code = totp.code()
        if copy { copyToClipboard(code) }
        // 파이프로 넘길 때 코드만 깔끔히 나가도록, 부가 정보는 stderr 로 보낸다.
        print(code)
        let suffix = copy ? " · 클립보드에 복사함" : ""
        FileHandle.standardError.write(
            Data("\(totp.secondsRemaining())초 남음\(suffix)\n".utf8))
        return
    }

    print("\(name) — Ctrl+C 로 종료")
    var lastCode = ""
    while true {
        let code = totp.code()
        let remaining = totp.secondsRemaining()
        if code != lastCode {
            lastCode = code
            if copy { copyToClipboard(code) }
        }
        let filled = Int((Double(remaining) / Double(totp.period) * 20).rounded())
        let bar = String(repeating: "█", count: filled) + String(repeating: "░", count: 20 - filled)
        // \r 로 같은 줄을 갱신한다
        print("\r  \(code)  \(bar) \(remaining)초 ", terminator: "")
        fflush(stdout)
        Thread.sleep(forTimeInterval: 1)
    }
}

// MARK: - 인자 처리

var arguments = Array(CommandLine.arguments.dropFirst())
var copy = false
var watch = false
var hotKeyText = Settings.hotKey
var accountOverride: String?

var filtered: [String] = []
var index = 0
while index < arguments.count {
    let argument = arguments[index]
    switch argument {
    case "-c", "--copy":
        copy = true
    case "-w", "--watch":
        watch = true
    case "--hotkey", "--account":
        guard index + 1 < arguments.count else {
            fail("\(argument) 에 값이 필요합니다.")
        }
        index += 1
        if argument == "--hotkey" { hotKeyText = arguments[index] } else { accountOverride = arguments[index] }
    default:
        filtered.append(argument)
    }
    index += 1
}
arguments = filtered

guard let first = arguments.first else {
    print(usage())
    exit(0)
}
let rest = Array(arguments.dropFirst())

do {
    switch first {
    case "-h", "--help":
        print(usage())
    case "-v", "--version":
        print("otp \(version)")
    case "add":
        try commandAdd(arguments: rest)
    case "list", "ls":
        commandList()
    case "scan":
        try Scan.run(arguments: rest)
    case "agent":
        try Agent.run(hotKeyText: hotKeyText, accountOverride: accountOverride)
    case "default":
        if let name = rest.first {
            guard Keychain.names().contains(name) else {
                throw OTPError("'\(name)' 이(가) 등록되어 있지 않습니다.")
            }
            Settings.defaultAccount = name
            print("기본 계정: \(name)")
        } else if let current = Settings.defaultAccount {
            print(current)
        } else {
            print("기본 계정이 지정되어 있지 않습니다. `otp default <이름>` 으로 지정하세요.")
        }
    case "selftest":
        let results = SelfTest.run()
        for result in results {
            print("\(result.passed ? "PASS" : "FAIL")  \(result.name)\(result.detail.isEmpty ? "" : " — " + result.detail)")
        }
        let failed = results.filter { !$0.passed }.count
        print("\(results.count - failed)/\(results.count) 통과")
        if failed > 0 { exit(1) }
    case "hotkey":
        try commandHotKey(arguments: rest)
    case "rename", "mv":
        try commandRename(arguments: rest)
    case "remove", "rm", "delete":
        try commandRemove(arguments: rest)
    default:
        if first.hasPrefix("-") {
            fail("알 수 없는 옵션입니다: \(first)\n\n\(usage())")
        }
        try commandCode(name: first, copy: copy, watch: watch)
    }
} catch let error as OTPError {
    fail(error.message)
} catch {
    fail(error.localizedDescription)
}
