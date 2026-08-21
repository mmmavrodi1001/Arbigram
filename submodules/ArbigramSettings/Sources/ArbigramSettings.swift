import Foundation

/// The fork's own switches.
///
/// These cannot live in TelegramUIPreferences with the rest of the app's
/// settings. That module sits *above* TelegramCore, and one of the switches has
/// to be read from inside TelegramCore — the sponsored-message request is
/// refused there, before it is ever issued, rather than hidden afterwards.
/// UserDefaults in the shared app group is the one store both ends can reach,
/// and it answers synchronously, which the call sites need: a chat opening and
/// a chat-list layout pass have nowhere to await a signal.
public final class ArbigramSettings {
    public static let shared = ArbigramSettings()

    /// Posted after any switch changes.
    ///
    /// The chat list decides on its stories header during layout rather than
    /// from a subscription, so without this nothing would tell it to look
    /// again until the next unrelated update arrived.
    public static let changedNotification = Notification.Name("ArbigramSettingsChanged")

    private enum Key: String, CaseIterable {
        case hideStories = "arbigram.hideStories"
        case hideSponsoredMessages = "arbigram.hideSponsoredMessages"
        case showPeerId = "arbigram.showPeerId"
    }

    private let defaults: UserDefaults

    private init() {
        // The container the signing profile grants; the same name is pinned in
        // Telegram/BUILD and in the two runtime lookups in AppDelegate.
        self.defaults = UserDefaults(suiteName: "group.dfbc88d056a46f1b.1") ?? UserDefaults.standard
        // Every switch ships on, so a fresh install behaves the way the fork did
        // when these were compiled-in constants.
        self.defaults.register(defaults: Dictionary(uniqueKeysWithValues: Key.allCases.map { ($0.rawValue, true) }))
    }

    public var hideStories: Bool {
        get { return self.defaults.bool(forKey: Key.hideStories.rawValue) }
        set { self.set(.hideStories, newValue) }
    }

    public var hideSponsoredMessages: Bool {
        get { return self.defaults.bool(forKey: Key.hideSponsoredMessages.rawValue) }
        set { self.set(.hideSponsoredMessages, newValue) }
    }

    public var showPeerId: Bool {
        get { return self.defaults.bool(forKey: Key.showPeerId.rawValue) }
        set { self.set(.showPeerId, newValue) }
    }

    private func set(_ key: Key, _ value: Bool) {
        if self.defaults.bool(forKey: key.rawValue) == value {
            return
        }
        self.defaults.set(value, forKey: key.rawValue)
        NotificationCenter.default.post(name: ArbigramSettings.changedNotification, object: nil)
    }
}
