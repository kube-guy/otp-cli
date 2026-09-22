import Carbon
import Foundation

/// `cmd+opt+o` 같은 문자열을 Carbon 단축키로 등록한다.
///
/// Carbon 의 `RegisterEventHotKey` 를 쓰는 이유는, 이벤트 탭으로 키를 감시하는 방식과 달리
/// **등록 자체에는 손쉬운 사용 권한이 필요 없고** 다른 앱의 키 입력을 들여다보지도 않기 때문이다.
/// 권한은 코드를 타이핑하는 순간에만 필요하다.
public final class HotKey {
    public struct Combo {
        public let keyCode: UInt32
        public let modifiers: UInt32
        public let display: String
    }

    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private static var action: (() -> Void)?

    private static let keyCodes: [String: UInt32] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26, "8": 28, "0": 29,
        "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
        "space": 49, "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
        "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
    ]

    /// "cmd+opt+o" → Combo
    public static func parse(_ text: String) throws -> Combo {
        var modifiers: UInt32 = 0
        var key: String?
        var shown: [String] = []

        for rawPart in text.lowercased().split(separator: "+") {
            let part = rawPart.trimmingCharacters(in: .whitespaces)
            switch part {
            case "cmd", "command", "⌘": modifiers |= UInt32(cmdKey); shown.append("⌘")
            case "opt", "option", "alt", "⌥": modifiers |= UInt32(optionKey); shown.append("⌥")
            case "ctrl", "control", "⌃": modifiers |= UInt32(controlKey); shown.append("⌃")
            case "shift", "⇧": modifiers |= UInt32(shiftKey); shown.append("⇧")
            default:
                guard key == nil else {
                    throw OTPError("단축키에 일반 키는 하나만 올 수 있습니다: \(text)")
                }
                key = part
            }
        }

        guard let key else {
            throw OTPError("단축키에 일반 키가 없습니다: \(text)")
        }
        guard let keyCode = keyCodes[key] else {
            throw OTPError("지원하지 않는 키입니다: \(key)")
        }
        guard modifiers != 0 else {
            throw OTPError("수정키(cmd/opt/ctrl/shift) 를 최소 하나 포함해야 합니다: \(text)")
        }

        return Combo(keyCode: keyCode, modifiers: modifiers, display: shown.joined() + key.uppercased())
    }

    public init() {}

    /// 단축키를 등록한다. 다른 앱이 이미 쓰는 조합이면 실패한다.
    public func register(_ combo: Combo, action: @escaping () -> Void) throws {
        HotKey.action = action

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, _ in
                HotKey.action?()
                return noErr
            },
            1, &eventType, nil, &handler)
        guard installStatus == noErr else {
            throw OTPError("이벤트 핸들러를 등록하지 못했습니다. (status \(installStatus))")
        }

        let identifier = EventHotKeyID(signature: OSType(0x4F54_5021), id: 1)  // 'OTP!'
        let status = RegisterEventHotKey(
            combo.keyCode, combo.modifiers, identifier, GetApplicationEventTarget(), 0, &reference)
        guard status == noErr else {
            throw OTPError(
                "단축키 \(combo.display) 를 등록하지 못했습니다. 다른 앱이 이미 쓰고 있을 수 있습니다. (status \(status))")
        }
    }

    deinit {
        if let reference { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
    }
}
