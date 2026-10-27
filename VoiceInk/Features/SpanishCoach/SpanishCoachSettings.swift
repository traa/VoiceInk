import Foundation

enum SpanishCoachSettings {
    static let isEnabledKey = "SpanishCoachEnabled"
    static let pausedUntilKey = "SpanishCoachPausedUntil"
    static let lastCardShownAtKey = "SpanishCoachLastCardShownAt"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: isEnabledKey)
    }

    static var pausedUntil: Date {
        get { Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: pausedUntilKey)) }
        set { UserDefaults.standard.set(newValue.timeIntervalSince1970, forKey: pausedUntilKey) }
    }

    static var lastCardShownAt: Date {
        get { Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: lastCardShownAtKey)) }
        set { UserDefaults.standard.set(newValue.timeIntervalSince1970, forKey: lastCardShownAtKey) }
    }
}
