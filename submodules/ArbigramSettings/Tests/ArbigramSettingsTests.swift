import XCTest
import ArbigramSettings

/// Both halves of the fork's settings are behaviour over a UserDefaults, so a
/// test is a store of its own and a fresh object on top of it. Nothing here
/// touches the app group, which means a test run cannot rewrite the settings of
/// the app installed beside it.
private func scratchDefaults(_ name: String) -> UserDefaults {
    UserDefaults().removePersistentDomain(forName: name)
    return UserDefaults(suiteName: name)!
}

/// XCTest names a case "-[ClassName testSomething]". A suite name carrying
/// brackets and a space is not one UserDefaults will open, so it is stripped
/// down to something a domain name can be.
private func scratchSuiteName(_ prefix: String, _ testName: String) -> String {
    let allowed = testName.map { character -> Character in
        return character.isLetter || character.isNumber ? character : "_"
    }
    return prefix + String(allowed)
}

final class ArbigramSecretPhraseTests: XCTestCase {
    private var suiteName = ""
    private var settings: ArbigramSettings!

    override func setUp() {
        super.setUp()
        self.suiteName = scratchSuiteName("arbigram.tests.phrase.", self.name)
        self.settings = ArbigramSettings(defaults: scratchDefaults(self.suiteName))
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: self.suiteName)
        self.settings = nil
        super.tearDown()
    }

    /// With no phrase the feature is off, not armed: nothing typed into search
    /// may be swallowed, or the search box would eat a real query.
    func testNoPhraseMeansNothingIsConsumed() {
        XCTAssertFalse(self.settings.consumeSecretPhrase("anything"))
        XCTAssertFalse(self.settings.consumeSecretPhrase(""))
        XCTAssertFalse(self.settings.hiddenRevealed)
    }

    func testTypingThePhraseTogglesTheHiddenAccountsOnceEach() {
        self.settings.secretPhrase = "open sesame"

        XCTAssertFalse(self.settings.consumeSecretPhrase("op"))
        XCTAssertFalse(self.settings.hiddenRevealed)

        XCTAssertTrue(self.settings.consumeSecretPhrase("open sesame"))
        XCTAssertTrue(self.settings.hiddenRevealed)

        // Typing it into a field that already held it is the same phrase, not a
        // second request. It stays swallowed and nothing flips.
        XCTAssertTrue(self.settings.consumeSecretPhrase("open sesame"))
        XCTAssertTrue(self.settings.hiddenRevealed)

        // Clearing the field and entering it again is a fresh request, so the
        // accounts go back to hidden without needing a restart.
        XCTAssertFalse(self.settings.consumeSecretPhrase(""))
        XCTAssertTrue(self.settings.consumeSecretPhrase("open sesame"))
        XCTAssertFalse(self.settings.hiddenRevealed)
    }

    /// Deleting the last character and putting it back is the single most likely
    /// way to type a phrase, and it used to flip the mode twice.
    func testCorrectingATypoStillCountsAsOneEntry() {
        self.settings.secretPhrase = "sunflower"

        XCTAssertTrue(self.settings.consumeSecretPhrase("sunflower"))
        XCTAssertTrue(self.settings.hiddenRevealed)

        XCTAssertFalse(self.settings.consumeSecretPhrase("sunflowe"))
        XCTAssertTrue(self.settings.hiddenRevealed)

        XCTAssertTrue(self.settings.consumeSecretPhrase("sunflower"))
        XCTAssertFalse(self.settings.hiddenRevealed)
    }

    /// A phrase typed on a phone keyboard arrives capitalised and with a space
    /// after it more often than not.
    func testThePhraseIgnoresCaseAndSurroundingSpace() {
        self.settings.secretPhrase = "  Blue Door  "

        XCTAssertTrue(self.settings.consumeSecretPhrase("blue door"))
        XCTAssertTrue(self.settings.hiddenRevealed)

        XCTAssertFalse(self.settings.consumeSecretPhrase(""))
        XCTAssertTrue(self.settings.consumeSecretPhrase("BLUE DOOR "))
        XCTAssertFalse(self.settings.hiddenRevealed)
    }

    func testMatchingThePhraseGatesTheIrreversibleActions() {
        XCTAssertFalse(self.settings.matchesSecretPhrase(""))
        XCTAssertFalse(self.settings.matchesSecretPhrase("anything"))

        self.settings.secretPhrase = "let me out"
        XCTAssertTrue(self.settings.matchesSecretPhrase("Let Me Out"))
        XCTAssertTrue(self.settings.matchesSecretPhrase(" let me out "))
        XCTAssertFalse(self.settings.matchesSecretPhrase("let me ou"))
    }

    /// Whether the accounts are showing is not written down on purpose: a phone
    /// picked up after a restart shows nothing.
    func testRevealingIsForgottenByARestart() {
        self.settings.secretPhrase = "north star"
        XCTAssertTrue(self.settings.consumeSecretPhrase("north star"))
        XCTAssertTrue(self.settings.hiddenRevealed)

        let restarted = ArbigramSettings(defaults: UserDefaults(suiteName: self.suiteName)!)
        XCTAssertEqual(restarted.secretPhrase, "north star")
        XCTAssertFalse(restarted.hiddenRevealed)
    }
}

final class ArbigramAccountMetaTests: XCTestCase {
    private var suiteName = ""
    private var settings: ArbigramSettings!

    override func setUp() {
        super.setUp()
        self.suiteName = scratchSuiteName("arbigram.tests.meta.", self.name)
        self.settings = ArbigramSettings(defaults: scratchDefaults(self.suiteName))
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: self.suiteName)
        self.settings = nil
        super.tearDown()
    }

    /// The metadata is read through a cache, so reading it back on the same
    /// object proves nothing. A second object over the same store does.
    func testMetadataIsWrittenThroughTheCacheAndNotOnlyIntoIt() {
        self.settings.accountMeta = [
            7: ArbigramAccountMeta(colorIndex: 2, pinned: true, tags: ["drop", "main"], hidden: false)
        ]

        let reloaded = ArbigramSettings(defaults: UserDefaults(suiteName: self.suiteName)!)
        let meta = reloaded.meta(for: 7)
        XCTAssertEqual(meta.colorIndex, 2)
        XCTAssertTrue(meta.pinned)
        XCTAssertEqual(meta.tags, ["drop", "main"])
        XCTAssertFalse(meta.hidden)
    }

    /// An account carrying nothing is not stored, so the blob does not grow an
    /// entry for every account ever looked at.
    func testAnAccountWithNothingSetIsNotStored() {
        self.settings.accountMeta = [
            7: ArbigramAccountMeta(colorIndex: 3),
            8: ArbigramAccountMeta()
        ]

        let reloaded = ArbigramSettings(defaults: UserDefaults(suiteName: self.suiteName)!)
        XCTAssertEqual(Array(reloaded.accountMeta.keys), [7])
        XCTAssertEqual(reloaded.meta(for: 8), ArbigramAccountMeta.empty)
    }

    /// A hidden account raising a banner would undo the hiding, so the
    /// suppressed set is the switched-off accounts and the hidden ones together.
    func testSuppressedAccountsAreTheMutedOnesPlusTheHiddenOnes() {
        self.settings.setAccount(11, muted: true)
        self.settings.accountMeta = [
            22: ArbigramAccountMeta(hidden: true),
            33: ArbigramAccountMeta(colorIndex: 1)
        ]

        XCTAssertEqual(self.settings.notificationSuppressedAccountIds, Set([11, 22]))

        self.settings.setAccount(11, muted: false)
        XCTAssertEqual(self.settings.notificationSuppressedAccountIds, Set([22]))
    }
}

final class ArbigramDeletedMessagesTests: XCTestCase {
    private var suiteName = ""
    private var core: ArbigramCoreSettings!

    override func setUp() {
        super.setUp()
        self.suiteName = scratchSuiteName("arbigram.tests.deleted.", self.name)
        self.core = ArbigramCoreSettings(defaults: scratchDefaults(self.suiteName))
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: self.suiteName)
        self.core = nil
        super.tearDown()
    }

    private func record(_ index: Int) -> ArbigramDeletedMessage {
        return ArbigramDeletedMessage(
            chatId: 1,
            chatTitle: "Chat",
            authorTitle: "Author",
            text: "message \(index)",
            mediaKind: "",
            timestamp: Int32(index),
            deletedAt: Int32(index)
        )
    }

    /// Two switches, and the per-account one is an exception to the global one
    /// rather than a second way to turn it on.
    func testKeepingNeedsTheGlobalSwitchAndTheAccountTogether() {
        XCTAssertFalse(self.core.keepsDeletedMessages(accountId: 5))

        self.core.keepDeletedMessages = true
        XCTAssertTrue(self.core.keepsDeletedMessages(accountId: 5))

        self.core.setKeepsDeletedMessages(false, accountId: 5)
        XCTAssertFalse(self.core.keepsDeletedMessages(accountId: 5))
        XCTAssertTrue(self.core.keepsDeletedMessages(accountId: 6))

        // Off globally means off everywhere, whatever the account says.
        self.core.keepDeletedMessages = false
        XCTAssertFalse(self.core.keepsDeletedMessages(accountId: 6))

        // And turning the account back on must not leave it in the exception set.
        self.core.keepDeletedMessages = true
        self.core.setKeepsDeletedMessages(true, accountId: 5)
        XCTAssertTrue(self.core.keepsDeletedMessages(accountId: 5))
        XCTAssertTrue(self.core.deletedMessagesOffAccountIds.isEmpty)
    }

    func testTheLogKeepsTheNewestTwoHundredPerAccount() {
        let limit = ArbigramCoreSettings.deletedMessagesLimit
        for index in 1...(limit + 50) {
            self.core.appendDeletedMessages([self.record(index)], accountId: 1)
        }

        let kept = self.core.deletedMessages(accountId: 1)
        XCTAssertEqual(kept.count, limit)
        XCTAssertEqual(kept.first?.text, "message 51")
        XCTAssertEqual(kept.last?.text, "message \(limit + 50)")
    }

    /// The lists are per account so one account's history cannot show up under
    /// another — which is the whole reason a hidden account can be logged at all.
    func testAccountsKeepSeparateLists() {
        self.core.appendDeletedMessages([self.record(1), self.record(2)], accountId: 1)
        self.core.appendDeletedMessages([self.record(3)], accountId: 2)

        XCTAssertEqual(self.core.deletedMessages(accountId: 1).count, 2)
        XCTAssertEqual(self.core.deletedMessages(accountId: 2).count, 1)

        self.core.clearDeletedMessages(accountId: 1)
        XCTAssertTrue(self.core.deletedMessages(accountId: 1).isEmpty)
        XCTAssertEqual(self.core.deletedMessages(accountId: 2).count, 1)

        self.core.clearDeletedMessages(accountId: nil)
        XCTAssertTrue(self.core.deletedMessages(accountId: 2).isEmpty)
    }

    /// The hook carries the account id because the app decides whether to raise
    /// a banner, and a hidden account must not get one.
    func testRecordingHandsTheAccountIdUp() {
        var seen: [(Int, Int64)] = []
        self.core.onDeletedMessagesRecorded = { records, accountId in
            seen.append((records.count, accountId))
        }

        self.core.appendDeletedMessages([self.record(1), self.record(2)], accountId: 42)
        self.core.appendDeletedMessages([], accountId: 43)

        XCTAssertEqual(seen.count, 1)
        XCTAssertEqual(seen.first?.0, 2)
        XCTAssertEqual(seen.first?.1, 42)
    }

    func testTheLogSurvivesAReopen() {
        self.core.appendDeletedMessages([self.record(1)], accountId: 9)

        let reopened = ArbigramCoreSettings(defaults: UserDefaults(suiteName: self.suiteName)!)
        XCTAssertEqual(reopened.deletedMessages(accountId: 9).first?.text, "message 1")
    }
}
