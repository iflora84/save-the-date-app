import Foundation

/// When to ask for an App Store rating: at a happy moment people actually reach,
/// at most once per app version, and only once they have three dates of their
/// own. iOS itself also caps the prompt at three times a year.
enum ReviewPrompt {
    static let askedVersionKey: String = "reviewPromptVersion"
    static let minimumOwnDates: Int = 3

    static var appVersion: String {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    static func shouldAsk(ownDates: Int, version: String = appVersion, defaults: UserDefaults = .standard) -> Bool {
        if DemoMode.isActive { return false }
        return ownDates >= minimumOwnDates && defaults.string(forKey: askedVersionKey) != version
    }

    static func markAsked(version: String = appVersion, defaults: UserDefaults = .standard) {
        defaults.set(version, forKey: askedVersionKey)
    }
}
