import Foundation

public enum DoNotDisturbPolicy {
    public static let defaultsKey = "doNotDisturbEnabled"
    public static let sharedDefaultsSuiteName = "com.superlisten.hibiki"
    public static let blockedRequestMessage = "Do Not Disturb is enabled in Hibiki."
    public static let cliSuppressedNotice = "Do Not Disturb is ON in Hibiki. Request skipped."

    public static func isEnabled(
        defaults: UserDefaults = .standard,
        sharedDefaults: UserDefaults? = UserDefaults(suiteName: sharedDefaultsSuiteName)
    ) -> Bool {
        if let sharedDefaults,
           sharedDefaults.object(forKey: defaultsKey) != nil {
            return sharedDefaults.bool(forKey: defaultsKey)
        }

        if defaults.object(forKey: defaultsKey) != nil {
            return defaults.bool(forKey: defaultsKey)
        }

        return false
    }

    public static func setEnabled(
        _ enabled: Bool,
        defaults: UserDefaults = .standard,
        sharedDefaults: UserDefaults? = UserDefaults(suiteName: sharedDefaultsSuiteName)
    ) {
        defaults.set(enabled, forKey: defaultsKey)
        sharedDefaults?.set(enabled, forKey: defaultsKey)
    }
}
