import Foundation

/// What the fork remembers about an account beyond what Telegram stores.
///
/// Keyed by user id rather than account record id: the record id changes if an
/// account is removed and added back, the user id does not.
public struct ArbigramAccountMeta: Codable, Equatable {
    /// Index into ArbigramAccountMeta.palette; -1 for no colour.
    public var colorIndex: Int
    public var pinned: Bool
    public var tags: [String]
    public var note: String

    public init(colorIndex: Int = -1, pinned: Bool = false, tags: [String] = [], note: String = "") {
        self.colorIndex = colorIndex
        self.pinned = pinned
        self.tags = tags
        self.note = note
    }

    public static let empty = ArbigramAccountMeta()

    /// Distinguishable at a glance at dot size, and readable on both themes.
    public static let palette: [UInt32] = [
        0xe8524f,
        0xf5a623,
        0xf7d04a,
        0x4cd964,
        0x34c8d0,
        0x4a8cf7,
        0x8b6dff,
        0xef5da8,
    ]

    public var isEmpty: Bool {
        return self == ArbigramAccountMeta.empty
    }
}

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
        case didApplyTheme = "arbigram.didApplyTheme"

        /// The first three replaced constants that were compiled in, so they
        /// keep that behaviour. The rest are new and stay out of the way until
        /// they are asked for.
        var defaultValue: Bool {
            switch self {
            case .hideStories, .hideSponsoredMessages, .showPeerId:
                return true
            case .skipReadHistory, .hideInputActivity, .ignoreCopyProtection, .hideContactsTab, .didApplyTheme:
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

    /// Whether the fork's theme has been handed over once. Not a switch, and
    /// deliberately not in the settings screen: after the one-time application
    /// the theme belongs to Appearance like any other.
    public var didApplyTheme: Bool {
        get { return self.defaults.bool(forKey: Key.didApplyTheme.rawValue) }
        set { self.set(.didApplyTheme, newValue) }
    }

    /// Accounts whose push token is withdrawn, by user id.
    ///
    /// Not a Bool, so it sits outside the Key enum. Upstream offers all accounts
    /// or only the active one; this is the middle the multi-account case wants.
    private static let mutedAccountsKey = "arbigram.mutedAccountIds"

    public var mutedAccountIds: Set<Int64> {
        get {
            let stored = self.defaults.array(forKey: ArbigramSettings.mutedAccountsKey) as? [NSNumber] ?? []
            return Set(stored.map { $0.int64Value })
        }
        set {
            let stored = newValue.sorted().map { NSNumber(value: $0) }
            self.defaults.set(stored, forKey: ArbigramSettings.mutedAccountsKey)
            NotificationCenter.default.post(name: ArbigramSettings.changedNotification, object: nil)
        }
    }

    public func isAccountMuted(_ id: Int64) -> Bool {
        return self.mutedAccountIds.contains(id)
    }

    public func setAccount(_ id: Int64, muted: Bool) {
        var ids = self.mutedAccountIds
        if muted {
            ids.insert(id)
        } else {
            ids.remove(id)
        }
        self.mutedAccountIds = ids
    }

    private static let accountMetaKey = "arbigram.accountMeta"

    /// Stored as one JSON blob: the shape changes as the fork grows, and a
    /// single value keeps reads and writes atomic without a schema in defaults.
    public var accountMeta: [Int64: ArbigramAccountMeta] {
        get {
            guard let data = self.defaults.data(forKey: ArbigramSettings.accountMetaKey),
                  let decoded = try? JSONDecoder().decode([String: ArbigramAccountMeta].self, from: data) else {
                return [:]
            }
            var result: [Int64: ArbigramAccountMeta] = [:]
            for (key, value) in decoded {
                if let id = Int64(key) {
                    result[id] = value
                }
            }
            return result
        }
        set {
            var encodable: [String: ArbigramAccountMeta] = [:]
            for (id, value) in newValue where !value.isEmpty {
                encodable["\(id)"] = value
            }
            if let data = try? JSONEncoder().encode(encodable) {
                self.defaults.set(data, forKey: ArbigramSettings.accountMetaKey)
                NotificationCenter.default.post(name: ArbigramSettings.changedNotification, object: nil)
            }
        }
    }

    public func meta(for id: Int64) -> ArbigramAccountMeta {
        return self.accountMeta[id] ?? ArbigramAccountMeta.empty
    }

    public func setMeta(_ meta: ArbigramAccountMeta, for id: Int64) {
        var all = self.accountMeta
        all[id] = meta
        self.accountMeta = all
    }

    /// Every tag in use, for offering them rather than retyping.
    public var knownTags: [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for meta in self.accountMeta.values {
            for tag in meta.tags where !seen.contains(tag.lowercased()) {
                seen.insert(tag.lowercased())
                result.append(tag)
            }
        }
        return result.sorted()
    }

    private func set(_ key: Key, _ value: Bool) {
        if self.defaults.bool(forKey: key.rawValue) == value {
            return
        }
        self.defaults.set(value, forKey: key.rawValue)
        NotificationCenter.default.post(name: ArbigramSettings.changedNotification, object: nil)
    }
}
