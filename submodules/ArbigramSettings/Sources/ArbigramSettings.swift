import Foundation
// Re-exported so that everything above the engine still sees one store: the
// lower half is an implementation detail of where the build boundary had to go.
@_exported import ArbigramCore

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
    /// Absent from every list until the phrase is typed. Decoded with a default
    /// so metadata written before this existed still reads.
    public var hidden: Bool

    public init(colorIndex: Int = -1, pinned: Bool = false, tags: [String] = [], note: String = "", hidden: Bool = false) {
        self.colorIndex = colorIndex
        self.pinned = pinned
        self.tags = tags
        self.note = note
        self.hidden = hidden
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.colorIndex = try container.decodeIfPresent(Int.self, forKey: .colorIndex) ?? -1
        self.pinned = try container.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        self.tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        self.note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        self.hidden = try container.decodeIfPresent(Bool.self, forKey: .hidden) ?? false
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
/// settings: that module sits above TelegramCore, and some of these are read
/// from inside it. UserDefaults in the shared app group is the one store both
/// ends can reach, and it answers synchronously, which the call sites need — a
/// chat opening and a chat-list layout pass have nowhere to await a signal.
///
/// The half TelegramCore actually reads lives in ArbigramCore, one module down.
/// Everything here sits above the engine, so editing it rebuilds a handful of
/// modules rather than the entire project.
public final class ArbigramSettings {
    public static let shared = ArbigramSettings()

    /// Posted after any switch changes, in either half of the store.
    ///
    /// The chat list decides on its stories header during layout rather than
    /// from a subscription, so without this nothing would tell it to look
    /// again until the next unrelated update arrived.
    public static let changedNotification = ArbigramCoreSettings.changedNotification

    private enum Key: String, CaseIterable {
        case hideStories = "arbigram.hideStories"
        case showPeerId = "arbigram.showPeerId"
        case skipReadHistory = "arbigram.skipReadHistory"
        case hideContactsTab = "arbigram.hideContactsTab"
        case saveSecretMedia = "arbigram.saveSecretMedia"
        case didApplyTheme = "arbigram.didApplyTheme"

        /// The first three replaced constants that were compiled in, so they
        /// keep that behaviour. The rest are new and stay out of the way until
        /// they are asked for.
        var defaultValue: Bool {
            switch self {
            case .hideStories, .showPeerId:
                return true
            case .skipReadHistory, .hideContactsTab, .saveSecretMedia, .didApplyTheme:
                return false
            }
        }
    }

    private let defaults: UserDefaults

    private init() {
        // One suite for both halves, opened by the lower one.
        self.defaults = ArbigramCoreSettings.shared.defaults
        self.defaults.register(defaults: Dictionary(uniqueKeysWithValues: Key.allCases.map { ($0.rawValue, $0.defaultValue) }))
    }

    // The switches TelegramCore reads live one module down, where an edit does
    // not rebuild the whole project. They are forwarded here so that everything
    // above the engine still sees a single store.

    public var hideSponsoredMessages: Bool {
        get { return ArbigramCoreSettings.shared.hideSponsoredMessages }
        set { ArbigramCoreSettings.shared.hideSponsoredMessages = newValue }
    }

    public var hideInputActivity: Bool {
        get { return ArbigramCoreSettings.shared.hideInputActivity }
        set { ArbigramCoreSettings.shared.hideInputActivity = newValue }
    }

    public var ignoreCopyProtection: Bool {
        get { return ArbigramCoreSettings.shared.ignoreCopyProtection }
        set { ArbigramCoreSettings.shared.ignoreCopyProtection = newValue }
    }

    public var keepDeletedMessages: Bool {
        get { return ArbigramCoreSettings.shared.keepDeletedMessages }
        set { ArbigramCoreSettings.shared.keepDeletedMessages = newValue }
    }

    public static let deletedMessagesLimit = ArbigramCoreSettings.deletedMessagesLimit

    public var deletedMessages: [ArbigramDeletedMessage] {
        return ArbigramCoreSettings.shared.deletedMessages
    }

    public func clearDeletedMessages() {
        ArbigramCoreSettings.shared.clearDeletedMessages()
    }

    /// Chat-list stories strip.
    public var hideStories: Bool {
        get { return self.defaults.bool(forKey: Key.hideStories.rawValue) }
        set { self.set(.hideStories, newValue) }
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

    /// Self-destructing photos and videos, copied to the camera roll as they
    /// are opened. The file is already downloaded by then — this only keeps it.
    public var saveSecretMedia: Bool {
        get { return self.defaults.bool(forKey: Key.saveSecretMedia.rawValue) }
        set { self.set(.saveSecretMedia, newValue) }
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
    private static let secretPhraseKey = "arbigram.secretPhrase"

    /// Deliberately not persisted: closing the app hides everything again, so
    /// forgetting to switch it off is not a way to leak anything.
    private var hiddenRevealedValue = false

    public var hiddenRevealed: Bool {
        return self.hiddenRevealedValue
    }

    /// The phrase that toggles hidden accounts. Empty means the feature is off.
    public var secretPhrase: String {
        get { return self.defaults.string(forKey: ArbigramSettings.secretPhraseKey) ?? "" }
        set {
            // No notification: the phrase changes nothing that is on screen, and
            // this setter runs on every keystroke.
            self.defaults.set(newValue, forKey: ArbigramSettings.secretPhraseKey)
        }
    }

    public var hasHiddenAccounts: Bool {
        return self.accountMeta.values.contains(where: { $0.hidden })
    }

    /// Called with whatever was typed into chat search. Returns true when the
    /// text was the phrase, in which case it is swallowed and never searched
    /// for — the point is that nothing on screen reacts.
    public func consumeSecretPhrase(_ text: String) -> Bool {
        let phrase = self.secretPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
        if phrase.isEmpty {
            return false
        }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).compare(phrase, options: .caseInsensitive) != .orderedSame {
            return false
        }
        self.hiddenRevealedValue = !self.hiddenRevealedValue
        NotificationCenter.default.post(name: ArbigramSettings.changedNotification, object: nil)
        return true
    }

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
            }
        }
    }

    public func meta(for id: Int64) -> ArbigramAccountMeta {
        return self.accountMeta[id] ?? ArbigramAccountMeta.empty
    }

    public func setMeta(_ meta: ArbigramAccountMeta, for id: Int64) {
        var all = self.accountMeta
        let previous = all[id] ?? ArbigramAccountMeta.empty
        all[id] = meta
        self.accountMeta = all
        // Only hiding changes what other screens show, and these setters run on
        // every keystroke of the note and tag fields — so the rest stays quiet.
        if previous.hidden != meta.hidden {
            NotificationCenter.default.post(name: ArbigramSettings.changedNotification, object: nil)
        }
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
