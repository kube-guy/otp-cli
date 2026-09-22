import Foundation

/// 비밀이 아닌 설정값. 시크릿은 Keychain 에만 둔다.
public enum Settings {
    private static let defaults = UserDefaults(suiteName: "otp-cli") ?? .standard
    private static let accountKey = "defaultAccount"
    private static let hotKeyKey = "hotKey"

    public static let defaultHotKey = "cmd+opt+o"

    public static var defaultAccount: String? {
        get { defaults.string(forKey: accountKey) }
        set { defaults.set(newValue, forKey: accountKey) }
    }

    public static var hotKey: String {
        get { defaults.string(forKey: hotKeyKey) ?? defaultHotKey }
        set { defaults.set(newValue, forKey: hotKeyKey) }
    }

    /// 단축키가 어느 계정을 쓸지 결정한다.
    /// 지정된 기본 계정이 있으면 그것을, 없고 등록이 하나뿐이면 그것을 쓴다.
    public static func resolveAccountName() throws -> String {
        let names = Keychain.names()
        guard !names.isEmpty else {
            throw OTPError("등록된 항목이 없습니다. `otp add <이름>` 으로 먼저 등록하세요.")
        }
        if let chosen = defaultAccount {
            guard names.contains(chosen) else {
                throw OTPError("기본 계정 '\(chosen)' 이(가) 없습니다. `otp default <이름>` 으로 다시 지정하세요.")
            }
            return chosen
        }
        guard names.count == 1 else {
            throw OTPError(
                "등록이 여러 개입니다(\(names.joined(separator: ", "))). `otp default <이름>` 으로 기본 계정을 지정하세요.")
        }
        return names[0]
    }
}

extension Settings {
    /// 선택 목록에 보여줄 순서. 기본 계정을 맨 위로 올려 숫자키 1 이 되게 한다.
    public static func orderedForPicker(names: [String], defaultName: String?) -> [String] {
        guard let defaultName, let index = names.firstIndex(of: defaultName) else { return names }
        var ordered = names
        ordered.remove(at: index)
        ordered.insert(defaultName, at: 0)
        return ordered
    }
}
