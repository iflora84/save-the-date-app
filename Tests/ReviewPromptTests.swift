import XCTest
@testable import SaveTheDate

final class ReviewPromptTests: XCTestCase {

    func testAsksOncePerVersionAndOnlyWithThreeOwnDates() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "review-\(UUID().uuidString)"))
        XCTAssertFalse(ReviewPrompt.shouldAsk(ownDates: 2, version: "1.2", defaults: defaults))
        XCTAssertTrue(ReviewPrompt.shouldAsk(ownDates: 3, version: "1.2", defaults: defaults))

        ReviewPrompt.markAsked(version: "1.2", defaults: defaults)
        XCTAssertFalse(ReviewPrompt.shouldAsk(ownDates: 9, version: "1.2", defaults: defaults), "once per version")
        XCTAssertTrue(ReviewPrompt.shouldAsk(ownDates: 9, version: "1.3", defaults: defaults), "a new version may ask again")
    }
}
