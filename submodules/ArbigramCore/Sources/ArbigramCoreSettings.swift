import Foundation

/// A message the other side deleted, copied out before the postbox dropped it.
public struct ArbigramDeletedMessage: Codable, Equatable {
    public var chatId: Int64
    public var chatTitle: String
    public var authorTitle: String
    public var text: String
    /// "photo", "voice", "file"… empty when the message was only text.
    public var mediaKind: String
    public var timestamp: Int32
    public var deletedAt: Int32
    /// File name inside the deleted-media folder, when the attachment was
    /// copied out in time. Just the name — the container path moves between
    /// installs, so an absolute path stored here would go stale.
    public var mediaFile: String?

    public init(chatId: Int64, chatTitle: String, authorTitle: String, text: String, mediaKind: String, timestamp: Int32, deletedAt: Int32, mediaFile: String? = nil) {
        self.chatId = chatId
        self.chatTitle = chatTitle
        self.authorTitle = authorTitle
        self.text = text
        self.mediaKind = mediaKind
        self.timestamp = timestamp
        self.deletedAt = deletedAt
        self.mediaFile = mediaFile
    }
}

/// The part of the fork's settings that TelegramCore itself has to read.
///
/// It is split out from ArbigramSettings for one reason: TelegramCore depends on
/// whatever holds these, and a module TelegramCore depends on rebuilds the whole
/// project when it changes. Everything the app can read from above the engine
/// stays in ArbigramSettings, so editing a screen costs minutes instead of half
/// an hour. Only add here what is genuinely read from inside TelegramCore.
///
/// Both halves share one UserDefaults suite and one change notification, so from
/// the outside there is still a single store.
public final class ArbigramCoreSettings {
    public static let shared = ArbigramCoreSettings()

    /// Posted after any switch in either half changes.
    public static let changedNotification = Notification.Name("ArbigramSettingsChanged")

    /// The container the signing profile grants; the same name is pinned in
    /// Telegram/BUILD and in the two runtime lookups in AppDelegate.
    public static let appGroupName = "group.dfbc88d056a46f1b.1"

    private enum Key: String, CaseIterable {
        case hideSponsoredMessages = "arbigram.hideSponsoredMessages"
        case hideInputActivity = "arbigram.hideInputActivity"
        case ignoreCopyProtection = "arbigram.ignoreCopyProtection"
        case keepDeletedMessages = "arbigram.keepDeletedMessages"
        case announceDeletedMessages = "arbigram.announceDeletedMessages"
        case plainNotifications = "arbigram.plainNotifications"

        /// Hiding ads replaced a constant that was compiled in and keeps that
        /// behaviour. The rest are new and stay out of the way until asked for.
        var defaultValue: Bool {
            switch self {
            case .hideSponsoredMessages:
                return true
            case .hideInputActivity, .ignoreCopyProtection, .keepDeletedMessages, .announceDeletedMessages, .plainNotifications:
                return false
            }
        }
    }

    public let defaults: UserDefaults

    /// The deleted log is written from the postbox queue and read from the main
    /// one, and both halves of the app reach it.
    private let lock = NSLock()

    private convenience init() {
        // The app group, which the extensions would share if they were signed.
        self.init(defaults: UserDefaults(suiteName: ArbigramCoreSettings.appGroupName) ?? UserDefaults.standard)
    }

    /// A store of its own. Everything here is behaviour over a UserDefaults, so
    /// this is what a test drives — sharing the app group would mean a test run
    /// silently rewriting the settings of the app installed beside it.
    public init(defaults: UserDefaults) {
        self.defaults = defaults
        self.defaults.register(defaults: Dictionary(uniqueKeysWithValues: Key.allCases.map { ($0.rawValue, $0.defaultValue) }))
    }

    /// Sponsored messages, refused at the request rather than hidden on arrival.
    public var hideSponsoredMessages: Bool {
        get { return self.defaults.bool(forKey: Key.hideSponsoredMessages.rawValue) }
        set { self.set(.hideSponsoredMessages, newValue) }
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

    /// Whether incoming messages are copied out before they are deleted.
    public var keepDeletedMessages: Bool {
        get { return self.defaults.bool(forKey: Key.keepDeletedMessages.rawValue) }
        set { self.set(.keepDeletedMessages, newValue) }
    }

    /// Whether a deletion also raises a notification, so it is seen when it
    /// happens rather than whenever the list is next opened.
    public var announceDeletedMessages: Bool {
        get { return self.defaults.bool(forKey: Key.announceDeletedMessages.rawValue) }
        set { self.set(.announceDeletedMessages, newValue) }
    }

    /// Register for unencrypted push, so the payload carries readable text and
    /// no extension is needed to decrypt it. See the note at the call site.
    public var plainNotifications: Bool {
        get { return self.defaults.bool(forKey: Key.plainNotifications.rawValue) }
        set { self.set(.plainNotifications, newValue) }
    }

    private static let deletedMessagesOffKey = "arbigram.deletedMessagesOffAccounts"

    /// Accounts the deleted-message log skips, by user id.
    ///
    /// An exception list rather than an opt-in list: the switch above is the
    /// master, and an account that has never been touched follows it. Storing
    /// it the other way round would mean a new account silently opting out.
    public var deletedMessagesOffAccountIds: Set<Int64> {
        get {
            let stored = self.defaults.array(forKey: ArbigramCoreSettings.deletedMessagesOffKey) as? [NSNumber] ?? []
            return Set(stored.map { $0.int64Value })
        }
        set {
            self.defaults.set(newValue.sorted().map { NSNumber(value: $0) }, forKey: ArbigramCoreSettings.deletedMessagesOffKey)
            NotificationCenter.default.post(name: ArbigramCoreSettings.changedNotification, object: nil)
        }
    }

    public func keepsDeletedMessages(accountId: Int64) -> Bool {
        return self.keepDeletedMessages && !self.deletedMessagesOffAccountIds.contains(accountId)
    }

    public func setKeepsDeletedMessages(_ value: Bool, accountId: Int64) {
        var ids = self.deletedMessagesOffAccountIds
        if value {
            ids.remove(accountId)
        } else {
            ids.insert(accountId)
        }
        self.deletedMessagesOffAccountIds = ids
    }

    // MARK: - Deleted messages

    private static let deletedMessagesKey = "arbigram.deletedMessagesByAccount"

    /// Per account, because one list across thirty accounts is not a record of
    /// anything — and a hidden account's messages have no business showing up
    /// under a visible one.
    public static let deletedMessagesLimit = 200

    private var cachedDeletedMessages: [Int64: [ArbigramDeletedMessage]]?

    /// Called on the queue the deletion arrived on, with the records just
    /// written. Installed from above the engine, which is where notifications
    /// can be raised.
    public var onDeletedMessagesRecorded: (([ArbigramDeletedMessage], Int64) -> Void)?

    private func loadDeletedMessagesLocked() -> [Int64: [ArbigramDeletedMessage]] {
        if let cached = self.cachedDeletedMessages {
            return cached
        }
        var result: [Int64: [ArbigramDeletedMessage]] = [:]
        if let data = self.defaults.data(forKey: ArbigramCoreSettings.deletedMessagesKey),
           let decoded = try? JSONDecoder().decode([String: [ArbigramDeletedMessage]].self, from: data) {
            for (key, value) in decoded {
                if let id = Int64(key) {
                    result[id] = value
                }
            }
        }
        self.cachedDeletedMessages = result
        return result
    }

    private func storeDeletedMessagesLocked(_ value: [Int64: [ArbigramDeletedMessage]]) {
        self.cachedDeletedMessages = value
        var encodable: [String: [ArbigramDeletedMessage]] = [:]
        for (id, records) in value where !records.isEmpty {
            encodable["\(id)"] = records
        }
        if let data = try? JSONEncoder().encode(encodable) {
            self.defaults.set(data, forKey: ArbigramCoreSettings.deletedMessagesKey)
        }
    }

    public func deletedMessages(accountId: Int64) -> [ArbigramDeletedMessage] {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.loadDeletedMessagesLocked()[accountId] ?? []
    }

    public func appendDeletedMessages(_ records: [ArbigramDeletedMessage], accountId: Int64) {
        if records.isEmpty {
            return
        }
        self.lock.lock()
        var all = self.loadDeletedMessagesLocked()
        var forAccount = all[accountId] ?? []
        forAccount.append(contentsOf: records)
        if forAccount.count > ArbigramCoreSettings.deletedMessagesLimit {
            // Dropping a record has to drop its file too, or the folder grows
            // for ever behind a list that is capped.
            let dropped = forAccount.prefix(forAccount.count - ArbigramCoreSettings.deletedMessagesLimit)
            for record in dropped {
                if let name = record.mediaFile, let path = self.deletedMediaPath(name) {
                    try? FileManager.default.removeItem(atPath: path)
                }
            }
            forAccount.removeFirst(forAccount.count - ArbigramCoreSettings.deletedMessagesLimit)
        }
        all[accountId] = forAccount
        self.storeDeletedMessagesLocked(all)
        self.lock.unlock()

        self.onDeletedMessagesRecorded?(records, accountId)
    }

    /// Passing nil clears every account.
    public func clearDeletedMessages(accountId: Int64?) {
        self.lock.lock()
        defer { self.lock.unlock() }
        var all = self.loadDeletedMessagesLocked()
        let cleared: [ArbigramDeletedMessage]
        if let accountId {
            cleared = all[accountId] ?? []
            all[accountId] = []
        } else {
            cleared = all.values.flatMap { $0 }
            all = [:]
        }
        for record in cleared {
            if let name = record.mediaFile, let path = self.deletedMediaPath(name) {
                try? FileManager.default.removeItem(atPath: path)
            }
        }
        self.storeDeletedMessagesLocked(all)
    }

    /// Where copied-out attachments live. In the shared container so the
    /// files survive as long as the records that name them.
    public var deletedMediaDirectory: URL? {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: ArbigramCoreSettings.appGroupName) else {
            return nil
        }
        let directory = container.appendingPathComponent("arbigram-deleted", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    public func deletedMediaPath(_ name: String) -> String? {
        return self.deletedMediaDirectory?.appendingPathComponent(name).path
    }

    private func set(_ key: Key, _ value: Bool) {
        if self.defaults.bool(forKey: key.rawValue) == value {
            return
        }
        self.defaults.set(value, forKey: key.rawValue)
        NotificationCenter.default.post(name: ArbigramCoreSettings.changedNotification, object: nil)
    }
}
