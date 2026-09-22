import ApplicationServices
import Foundation

/// 포커스된 입력란에 문자열을 타이핑한다.
///
/// 클립보드를 거치지 않으므로 코드가 클립보드 이력에 남지 않는다.
/// 합성 키 이벤트를 보내려면 손쉬운 사용(Accessibility) 권한이 필요하다.
public enum Typing {
    /// 손쉬운 사용 권한이 허용되어 있는지. `prompt: true` 면 시스템 설정 안내 창을 띄운다.
    public static func isTrusted(prompt: Bool = false) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
        let options = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// 한 글자씩 유니코드 문자열로 이벤트를 만들어 보낸다.
    /// 가상 키코드 매핑을 쓰지 않으므로 키보드 배열(한/영, 쿼티 여부)에 영향받지 않는다.
    public static func type(_ text: String, characterDelay: TimeInterval = 0.012) {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        // 사용자가 누르고 있는 수정키(⌥⌘ 등)가 합성 입력에 섞이지 않도록 지운다.
        source.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents], state: .eventSuppressionStateSuppressionInterval)

        for character in text.unicodeScalars {
            var unit = UniChar(character.value)
            guard
                let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            else { continue }

            keyDown.flags = []
            keyUp.flags = []
            keyDown.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unit)
            keyUp.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unit)

            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)

            // 간격이 없으면 원격 데스크톱 등 일부 대상이 입력을 흘린다.
            if characterDelay > 0 { Thread.sleep(forTimeInterval: characterDelay) }
        }
    }
}
