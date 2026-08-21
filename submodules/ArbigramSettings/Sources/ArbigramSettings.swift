import Foundation

/// The fork's own switches.
///
/// These cannot live in TelegramUIPreferences with the rest of the app's
/// settings. That module sits *above* TelegramCore, and several of these are
/// read from inside it — the sponsored-message request is refused there, before
/// it is ever issued, rather than filtered afterwards. UserDefaults in the
/// shared app group is the one store both ends can reach, and it answers
/// synchronously, which the call sites need: a chat opening and a chat-list
/// layout pass have nowhere to await a signal.
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
        case skipReadHistory = "arbigram.skipReadHistory"
        case hideInputActivity = "arbigram.hideInputActivity"
        case ignoreCopyProtection = "arbigram.ignoreCopyProtection"
        case hideContactsTab = "arbigram.hideContactsTab"

        /// The first three replaced constants that were compiled in, so they
        /// keep that behaviour. The rest are new and stay out of the way until
        /// they are asked for.
        var defaultValue: Bool {
            switch self {
            case .hideStories, .hideSponsoredMessages, .showPeerId:
                return true
            case .skipReadHistory, .hideInputActivity, .ignoreCopyProtection, .hideContactsTab:
                return false
            }
        }
    }

    private let defaults: UserDefaults

    private init() {
        // The container the signing profile grants; the same name is pinned in
        // Telegram/BUILD and in the two runtime lookups in AppDelegate.
        self.defaults = UserDefaults(suiteName: "group.dfbc88d056a46f1b.1") ?? UserDefaults.standard
        self.defaults.register(defaults: Dictionary(uniqueKeysWithValues: Key.allCases.map { ($0.rawValue, $0.defaultValue) }))
    }

    /// Chat-list stories strip.
    public var hideStories: Bool {
        get { return self.defaults.bool(forKey: Key.hideStories.rawValue) }
        set { self.set(.hideStories, newValue) }
    }

    /// Sponsored messages, refused at the request rather than hidden on arrival.
    public var hideSponsoredMessages: Bool {
        get { return self.defaults.bool(forKey: Key.hideSponsoredMessages.rawValue) }
        set { self.set(.hideSponsoredMessages, newValue) }
    }

    /// The numeric identifier row in profiles.
    public var showPeerId: Bool {
        get { return self.defaults.bool(forKey: Key.showPeerId.rawValue) }
        set { self.set(.showPeerId, newValue) }
    }

    /// Read receipts. Overlaid onto the upstream debug flag of the same name,
    /// which already gates every place a read is reported — messages, reactions
    /// and stories alike.
    public var skipReadHistory: Bool {
        get { return self.defaults.bool(forKey: Key.skipReadHistory.rawValue) }
        set { self.set(.skipReadHistory, newValue) }
    }

    /// Outgoing typing and recording indicators.
    public var hideInputActivity: Bool {
        get { return self.defaults.bool(forKey: Key.hideInputActivity.rawValue) }
        set { self.set(.hideInputActivity, newValue) }
    }

    /// Whether a chat's copy-protection flag is honoured. Both text selection
    /// and media saving hang off the same flag, so one switch covers both.
    public var ignoreCopyProtection: Bool {
        get { return self.defaults.bool(forKey: Key.ignoreCopyProtection.rawValue) }
        set { self.set(.ignoreCopyProtection, newValue) }
    }

    /// The Contacts tab. Calls already has an upstream switch of its own.
    public var hideContactsTab: Bool {
        get { return self.defaults.bool(forKey: Key.hideContactsTab.rawValue) }
        set { self.set(.hideContactsTab, newValue) }
    }

    private func set(_ key: Key, _ value: Bool) {
        if self.defaults.bool(forKey: key.rawValue) == value {
            return
        }
        self.defaults.set(value, forKey: key.rawValue)
        NotificationCenter.default.post(name: ArbigramSettings.changedNotification, object: nil)
    }
}
