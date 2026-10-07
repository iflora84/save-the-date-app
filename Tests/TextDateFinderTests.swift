import XCTest
@testable import SaveTheDate

private func utcCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone.current
    calendar.locale = Locale(identifier: "en_US_POSIX")
    return calendar
}

private func date(_ year: Int, _ month: Int, _ day: Int, calendar: Calendar) throws -> Date {
    var c = DateComponents()
    c.year = year; c.month = month; c.day = day; c.hour = 12
    return try XCTUnwrap(calendar.date(from: c))
}

private let flightDate = TextDateFinder.DetectedDate(month: 2, day: 4, year: 2027, snippet: "Thursday 4 February 2027")

final class TextDateFinderTests: XCTestCase {

    /// Build 24 showed "Found 4 dates" for a text holding one: the model invented a
    /// wedding, a birthday and an anniversary. Labels can only name detected dates.
    func testLabelsCanOnlyNameDetectedDates() {
        let reply = """
        0|trip|Flight to Osaka|✈️
        1|event|Wedding|👰
        2|birthday|Birthday|🎉
        3|anniversary|Anniversary|💍
        """
        let found = TextDateFinder.parseLabels(reply, dates: [flightDate])
        XCTAssertEqual(found.count, 1)
        let flight = found.first
        XCTAssertEqual(flight?.name, "Flight to Osaka")
        XCTAssertEqual(flight?.year, 2027)
        XCTAssertEqual(flight?.month, 2)
        XCTAssertEqual(flight?.day, 4)
        XCTAssertEqual(flight?.oneTime, true)
    }

    func testLabelsSkipAndJunk() {
        let dates = [
            flightDate,
            TextDateFinder.DetectedDate(month: 1, day: 20, year: 2027, snippet: "pay by 20 January"),
            TextDateFinder.DetectedDate(month: 3, day: 3, year: 2027, snippet: "March 3")
        ]
        let reply = """
        Sure! Here are the labels:
        0. | trip | Flight to Osaka | ✈️
        1|skip
        2|birthday|Grandma|
        0|event|Duplicate|🎉
        2|meeting|Standup|📅
        """
        let found = TextDateFinder.parseLabels(reply, dates: dates)
        XCTAssertEqual(found.map { $0.name }, ["Flight to Osaka", "Grandma"])
        XCTAssertEqual(found.map { $0.emoji }, ["✈️", "🎂"])
        XCTAssertNil(found.last?.year, "a birthday never takes the year of the mention")
        XCTAssertEqual(found.first?.kindLabel, "Trip")
    }

    func testDetectorReadsTheSuggestedTestSentence() throws {
        let calendar = utcCalendar()
        let now = try date(2026, 10, 7, calendar: calendar)
        let found = TextDateFinder.detectDates(in: "Flight UA 837 to Osaka on Thursday 4 February 2027", now: now, calendar: calendar)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual([found.first?.year, found.first?.month, found.first?.day], [2027, 2, 4])
        XCTAssertFalse(found.first?.snippet.isEmpty ?? true)
    }

    func testDetectorDropsPastDates() throws {
        let calendar = utcCalendar()
        let now = try date(2026, 10, 7, calendar: calendar)
        let email = """
        Booking confirmed
        Your flight UA 837 San Francisco to Osaka departs on February 4, 2027.
        Your last trip was on March 3, 2025.
        """
        let found = TextDateFinder.detectDates(in: email, now: now, calendar: calendar)
        XCTAssertEqual(found.map { [$0.year, $0.month, $0.day] }, [[2027, 2, 4]])
    }

    func testFallbackNamesATripAfterItsDestination() {
        let trip = TextDateFinder.fallbackDate(flightDate, text: "Flight UA 837 to Osaka on Thursday 4 February 2027")
        XCTAssertEqual(trip.name, "Trip to Osaka")
        XCTAssertEqual(trip.emoji, "✈️")
        XCTAssertTrue(trip.oneTime)
    }

    func testFallbackNamesAPlainEventFromItsFirstLine() {
        let party = TextDateFinder.fallbackDate(flightDate, text: "Sam's graduation party\nJoin us at the park.")
        XCTAssertEqual(party.name, "Sam's graduation party")
        XCTAssertEqual(party.emoji, "🎉")
    }

    func testPromptListsEachDetectedDateWithItsWords() {
        let prompt = TextDateFinder.labelPrompt(text: "Flight to Osaka", dates: [flightDate])
        XCTAssertTrue(prompt.contains("0. 2027-02-04 (\"Thursday 4 February 2027\")"))
        XCTAssertTrue(TextDateFinder.labelInstructions.contains("number|kind|name|emoji"))
    }

    func testDraftForATripIsOneTimeWithShortReminders() {
        let trip = FoundDate(name: "Kyoto", kind: .custom, emoji: "✈️", month: 2, day: 4, year: 2027, oneTime: true)
        let draft = trip.draft(palette: .ocean, reminderHour: 8, reminderMinute: 30)
        XCTAssertTrue(draft.isOneTime)
        XCTAssertEqual(draft.reminderOffsets, [7, 1])
        XCTAssertEqual(draft.reminderHour, 8)
    }
}
