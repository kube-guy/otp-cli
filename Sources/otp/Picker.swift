import AppKit
import Foundation
import OTPCore

/// 단축키를 눌렀을 때 마우스 위치에 계정 목록을 띄우고 하나를 고르게 한다.
final class Picker: NSObject {
    private var chosen: String?

    @objc private func select(_ sender: NSMenuItem) {
        chosen = sender.representedObject as? String
    }

    /// 목록을 띄우고 선택된 이름을 반환한다. 취소하면 nil.
    /// `popUp` 은 메뉴가 닫힐 때까지 돌아오지 않으므로 반환 시점에는 선택이 끝나 있다.
    func pick(names: [String], defaultName: String?) -> String? {
        chosen = nil

        let menu = NSMenu()
        menu.autoenablesItems = false

        let header = NSMenuItem(title: "OTP 코드 입력", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        let ordered = Settings.orderedForPicker(names: names, defaultName: defaultName)

        for (index, name) in ordered.enumerated() {
            // 1~9 는 숫자키로 바로 고를 수 있게 한다. 그 이상은 화살표나 첫 글자로 고른다.
            let shortcut = index < 9 ? String(index + 1) : ""
            let item = NSMenuItem(title: name, action: #selector(select(_:)), keyEquivalent: shortcut)
            item.keyEquivalentModifierMask = []
            item.target = self
            item.representedObject = name
            item.isEnabled = true
            if name == defaultName { item.state = .on }
            menu.addItem(item)
        }

        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        return chosen
    }
}
