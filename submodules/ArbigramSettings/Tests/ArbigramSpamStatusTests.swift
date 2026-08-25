import XCTest
import ArbigramSettings

/// The spam bot answers in prose, and prose is where quiet mistakes live. These
/// pin the readings that matter, starting with the one that would have broken
/// the feature for every healthy account.
final class ArbigramSpamStatusTests: XCTestCase {
    private let now: Int32 = 1_756_000_000

    /// The Russian all-clear contains the word "ограничений". Match the trouble
    /// markers first and every clean account is reported as limited — which is
    /// worse than useless, because it is wrong in the direction he would act on.
    func testTheRussianAllClearIsNotReadAsALimit() {
        let status = ArbigramSpamStatus.parse(
            "Хорошие новости, никаких ограничений на ваш аккаунт сейчас не наложено.",
            at: self.now
        )
        XCTAssertEqual(status.state, .clean)
        XCTAssertEqual(status.until, "")
    }

    func testTheEnglishAllClearReadsClean() {
        let status = ArbigramSpamStatus.parse(
            "Good news, no limits are currently applied to your account.",
            at: self.now
        )
        XCTAssertEqual(status.state, .clean)
    }

    func testARussianLimitCarriesItsDate() {
        let status = ArbigramSpamStatus.parse(
            "К сожалению, некоторые ограничения были наложены на ваш аккаунт. "
                + "Ограничения будут автоматически сняты 25 августа 2026 г.",
            at: self.now
        )
        XCTAssertEqual(status.state, .limited)
        XCTAssertEqual(status.until, "25 августа 2026")
    }

    func testAnEnglishLimitCarriesItsDate() {
        let status = ArbigramSpamStatus.parse(
            "Your account will be automatically released on 25 August 2026.",
            at: self.now
        )
        XCTAssertEqual(status.state, .limited)
        XCTAssertEqual(status.until, "25 August 2026")
    }

    /// A limit with no date is a real answer, not a parse failure — it must
    /// still read as limited rather than falling through to unknown.
    func testALimitWithoutADateIsStillALimit() {
        let status = ArbigramSpamStatus.parse(
            "К сожалению, ваш аккаунт ограничен.",
            at: self.now
        )
        XCTAssertEqual(status.state, .limited)
        XCTAssertEqual(status.until, "")
    }

    /// Anything unrecognised keeps its text, because the screen shows the reply
    /// in full and a person can read what this could not.
    func testAnUnrecognisedReplyKeepsItsText() {
        let text = "Something the bot has never said before."
        let status = ArbigramSpamStatus.parse(text, at: self.now)
        XCTAssertEqual(status.state, .unknown)
        XCTAssertEqual(status.raw, text)
        XCTAssertEqual(status.checkedAt, self.now)
    }

    func testTheDateSurvivesAMissingYear() {
        XCTAssertEqual(ArbigramSpamStatus.extractDate("сняты 3 июля, честное слово"), "3 июля")
    }

    func testASentenceWithoutAMonthYieldsNoDate() {
        XCTAssertEqual(ArbigramSpamStatus.extractDate("никаких дат тут нет, 25 и всё"), "")
    }
}

final class ArbigramSpamStatusStorageTests: XCTestCase {
    private var suiteName = ""
    private var settings: ArbigramSettings!

    override func setUp() {
        super.setUp()
        let allowed = self.name.map { character -> Character in
            return character.isLetter || character.isNumber ? character : "_"
        }
        self.suiteName = "arbigram.tests.spam." + String(allowed)
        UserDefaults().removePersistentDomain(forName: self.suiteName)
        self.settings = ArbigramSettings(defaults: UserDefaults(suiteName: self.suiteName)!)
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: self.suiteName)
        self.settings = nil
        super.tearDown()
    }

    func testAVerdictSurvivesAReopen() {
        self.settings.setSpamStatus(
            ArbigramSpamStatus(state: .limited, until: "25 августа 2026", raw: "текст", checkedAt: 111),
            for: 42
        )

        let reopened = ArbigramSettings(defaults: UserDefaults(suiteName: self.suiteName)!)
        let stored = reopened.spamStatus(for: 42)
        XCTAssertEqual(stored?.state, .limited)
        XCTAssertEqual(stored?.until, "25 августа 2026")
        XCTAssertEqual(stored?.raw, "текст")
        XCTAssertEqual(stored?.checkedAt, 111)
        XCTAssertNil(reopened.spamStatus(for: 43))
    }

    func testCheckingOneAccountLeavesTheOthers() {
        self.settings.setSpamStatus(ArbigramSpamStatus(state: .clean, checkedAt: 1), for: 1)
        self.settings.setSpamStatus(ArbigramSpamStatus(state: .limited, checkedAt: 2), for: 2)
        self.settings.setSpamStatus(ArbigramSpamStatus(state: .limited, checkedAt: 3), for: 1)

        XCTAssertEqual(self.settings.spamStatus(for: 1)?.checkedAt, 3)
        XCTAssertEqual(self.settings.spamStatus(for: 2)?.state, .limited)
        XCTAssertEqual(self.settings.spamStatuses.count, 2)
    }
}
