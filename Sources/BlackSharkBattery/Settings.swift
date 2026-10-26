import BatteryCore
import Foundation

/// The app's own settings, stored in its own preferences file
/// (~/Library/Preferences/com.matejbasic.BlackSharkBattery.plist).
/// Read them in a terminal with `defaults read com.matejbasic.BlackSharkBattery`.
enum Settings {
    static let domain = "com.matejbasic.BlackSharkBattery"

    /// The app's own UserDefaults. When the binary runs inside the .app
    /// bundle, `.standard` already is that domain. When it runs some other
    /// way, the domain is named explicitly so the same file is used.
    private static let store: UserDefaults = {
        if Bundle.main.bundleIdentifier == domain {
            return .standard
        }
        return UserDefaults(suiteName: domain) ?? .standard
    }()

    private enum Key {
        static let lastLevel = "lastLevel"
        static let lastCharging = "lastCharging"
        static let lastReadingAt = "lastReadingAt"
        static let pollIntervalSeconds = "pollIntervalSeconds"
    }

    /// Level of the last good reading, so the menu can say "Last reading 74%
    /// at 14:05" after a relaunch with the headset off.
    static var lastLevel: Int? {
        get { store.object(forKey: Key.lastLevel) as? Int }
        set { setOptional(newValue, forKey: Key.lastLevel) }
    }

    /// Charging state of the same reading; nil when it was unknown.
    static var lastCharging: Bool? {
        get { store.object(forKey: Key.lastCharging) as? Bool }
        set { setOptional(newValue, forKey: Key.lastCharging) }
    }

    /// When the same reading was taken.
    static var lastReadingAt: Date? {
        get { store.object(forKey: Key.lastReadingAt) as? Date }
        set { setOptional(newValue, forKey: Key.lastReadingAt) }
    }

    /// Hidden override of the 300 s poll interval, for testing:
    /// `defaults write com.matejbasic.BlackSharkBattery pollIntervalSeconds -float 30`.
    /// `PollPolicy.withIntervalOverride` clamps it to at least 30 s.
    static var pollIntervalSeconds: Double? {
        get { store.object(forKey: Key.pollIntervalSeconds) as? Double }
        set { setOptional(newValue, forKey: Key.pollIntervalSeconds) }
    }

    /// The three `last...` values together, or nil when nothing is stored.
    static var lastReading: Reading? {
        get {
            guard let level = lastLevel, let at = lastReadingAt else { return nil }
            return Reading(level: level, charging: lastCharging, at: at)
        }
        set {
            lastLevel = newValue?.level
            lastCharging = newValue?.charging
            lastReadingAt = newValue?.at
        }
    }

    /// Stores a value, or removes the key for nil.
    private static func setOptional(_ value: Any?, forKey key: String) {
        if let value {
            store.set(value, forKey: key)
        } else {
            store.removeObject(forKey: key)
        }
    }
}
