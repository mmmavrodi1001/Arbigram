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

    public init(chatId: Int64, chatTitle: String, authorTitle: String, text: String, mediaKind: String, timestamp: Int32, deletedAt: Int32) {
        self.chatId = chatId
        self.chatTitle = chatTitle
        self.authorTitle = authorTitle
        self.text = text
        self.mediaKind = mediaKind
        self.timestamp = timestamp
        self.deletedAt = deletedAt
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

        /// Hiding ads replaced a constant that was compiled in and keeps that
        /// behaviour. The rest are new and stay out of the way until asked for.
        var defaultValue: Bool {
            switch self {
            case .hideSponsoredMessages:
                return true
            case .hideInputActivity, .ignoreCopyProtection, .keepDeletedMessages:
                return false
            }
        }
    }

    public let defaults: UserDefaults

    private init() {
        self.defaults = UserDefaults(suiteName: ArbigramCoreSettings.appGroupName) ?? UserDefaults.standard
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

    private static let deletedMessagesKey = "arbigram.deletedMessages"

    /// Bounded on purpose. This is a record of what was said, not an archive,
    /// and an unbounded list in defaults would grow until it hurt launch time.
    public static let deletedMessagesLimit = 500

    public var deletedMessages: [ArbigramDeletedMessage] {
        guard let data = self.defaults.data(forKey: ArbigramCoreSettings.deletedMessagesKey),
              let decoded = try? JSONDecoder().decode([ArbigramDeletedMessage].self, from: data) else {
            return []
        }
        return decoded
    }

    public func appendDeletedMessages(_ records: [ArbigramDeletedMessage]) {
        if records.isEmpty {
            return
        }
        var all = self.deletedMessages
        all.append(contentsOf: records)
        if all.count > ArbigramCoreSettings.deletedMessagesLimit {
            all.removeFirst(all.count - ArbigramCoreSettings.deletedMessagesLimit)
        }
        if let data = try? JSONEncoder().encode(all) {
            self.defaults.set(data, forKey: ArbigramCoreSettings.deletedMessagesKey)
        }
    }

    public func clearDeletedMessages() {
        self.defaults.removeObject(forKey: ArbigramCoreSettings.deletedMessagesKey)
    }

    private func set(_ key: Key, _ value: Bool) {
        if self.defaults.bool(forKey: key.rawValue) == value {
            return
        }
        self.defaults.set(value, forKey: key.rawValue)
        NotificationCenter.default.post(name: ArbigramCoreSettings.changedNotification, object: nil)
    }
}
