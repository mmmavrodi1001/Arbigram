import Foundation

/// What Telegram's own spam bot last said about an account.
///
/// The bot answers in prose, in the account's language, and the answer is the
/// only place this information exists — there is no field to read. So the text
/// is parsed for the one thing that matters (limited or not), the date is
/// lifted out when the sentence contains one, and the whole reply is kept
/// regardless, because a wording this code has never seen must still be
/// readable by a person.
public struct ArbigramSpamStatus: Codable, Equatable {
    public enum State: String, Codable {
        /// Never asked, or the reply made no sense to the parser.
        case unknown
        case clean
        case limited
    }

    public var state: State
    /// The date the bot named, exactly as it wrote it — "25 августа 2026".
    /// Empty when the sentence carried no date, which happens on permanent
    /// limits and on wordings this does not recognise.
    public var until: String
    /// The reply in full. Shown on the account's own screen so an unparsed
    /// answer is still worth something.
    public var raw: String
    public var checkedAt: Int32

    public init(state: State, until: String = "", raw: String = "", checkedAt: Int32) {
        self.state = state
        self.until = until
        self.raw = raw
        self.checkedAt = checkedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.state = try container.decodeIfPresent(State.self, forKey: .state) ?? .unknown
        self.until = try container.decodeIfPresent(String.self, forKey: .until) ?? ""
        self.raw = try container.decodeIfPresent(String.self, forKey: .raw) ?? ""
        self.checkedAt = try container.decodeIfPresent(Int32.self, forKey: .checkedAt) ?? 0
    }

    // MARK: - Reading the bot

    /// Phrases that mean the account is fine.
    ///
    /// Checked before the limited ones on purpose: the Russian all-clear is
    /// "никаких ограничений … не наложено", which contains the very word that
    /// otherwise means trouble. Matching in the other order calls every healthy
    /// account limited.
    private static let cleanMarkers = [
        "никаких ограничений",
        "не наложено",
        "хорошие новости",
        "no limits are currently applied",
        "good news"
    ]

    private static let limitedMarkers = [
        "ограничен",
        "ограничения",
        "будут сняты",
        "освобождён",
        "освобожден",
        "limited",
        "restricted",
        "will be automatically released",
        "released on"
    ]

    private static let monthNames: Set<String> = [
        "января", "февраля", "марта", "апреля", "мая", "июня",
        "июля", "августа", "сентября", "октября", "ноября", "декабря",
        "январь", "февраль", "март", "апрель", "май", "июнь",
        "июль", "август", "сентябрь", "октябрь", "ноябрь", "декабрь",
        "january", "february", "march", "april", "may", "june",
        "july", "august", "september", "october", "november", "december"
    ]

    public static func parse(_ text: String, at time: Int32) -> ArbigramSpamStatus {
        let haystack = text.lowercased()

        if self.cleanMarkers.contains(where: { haystack.contains($0) }) {
            return ArbigramSpamStatus(state: .clean, raw: text, checkedAt: time)
        }
        if self.limitedMarkers.contains(where: { haystack.contains($0) }) {
            return ArbigramSpamStatus(state: .limited, until: self.extractDate(text), raw: text, checkedAt: time)
        }
        return ArbigramSpamStatus(state: .unknown, raw: text, checkedAt: time)
    }

    /// The date out of a sentence, without trying to turn it into a timestamp.
    ///
    /// A month name is the anchor, since it is the one token that cannot be
    /// anything else. The day is whatever number sits before it and the year
    /// whatever number sits after; either may be missing, and a missing piece
    /// is simply left out rather than guessed.
    public static func extractDate(_ text: String) -> String {
        let separators = CharacterSet.whitespacesAndNewlines
        let tokens = text.components(separatedBy: separators).filter { !$0.isEmpty }

        func trimmed(_ token: String) -> String {
            return token.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        }
        func bare(_ token: String) -> String {
            return trimmed(token).lowercased()
        }
        func number(_ token: String) -> String? {
            let stripped = token.trimmingCharacters(in: CharacterSet.decimalDigits.inverted)
            return stripped.isEmpty ? nil : stripped
        }

        for (index, token) in tokens.enumerated() where self.monthNames.contains(bare(token)) {
            var parts: [String] = []
            if index > 0, let day = number(tokens[index - 1]) {
                parts.append(day)
            }
            parts.append(trimmed(token))
            if index + 1 < tokens.count, let year = number(tokens[index + 1]) {
                parts.append(year)
            }
            return parts.joined(separator: " ")
        }
        return ""
    }
}

public extension ArbigramSettings {
    private static var spamStatusKey: String { return "arbigram.spamStatuses" }

    /// One blob for the same reason the account metadata is one: the shape
    /// changes as the fork grows, and a single value keeps the write atomic.
    var spamStatuses: [Int64: ArbigramSpamStatus] {
        get {
            var result: [Int64: ArbigramSpamStatus] = [:]
            if let data = self.defaults.data(forKey: ArbigramSettings.spamStatusKey),
               let decoded = try? JSONDecoder().decode([String: ArbigramSpamStatus].self, from: data) {
                for (key, value) in decoded {
                    if let id = Int64(key) {
                        result[id] = value
                    }
                }
            }
            return result
        }
        set {
            var encodable: [String: ArbigramSpamStatus] = [:]
            for (id, value) in newValue {
                encodable["\(id)"] = value
            }
            if let data = try? JSONEncoder().encode(encodable) {
                self.defaults.set(data, forKey: ArbigramSettings.spamStatusKey)
            }
        }
    }

    func spamStatus(for id: Int64) -> ArbigramSpamStatus? {
        return self.spamStatuses[id]
    }

    func setSpamStatus(_ status: ArbigramSpamStatus, for id: Int64) {
        var all = self.spamStatuses
        all[id] = status
        self.spamStatuses = all
    }
}
