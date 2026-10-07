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

final class TextDateFinderTests: XCTestCase {

    func testParserKeepsGoodLinesAndSkipsJunk() {
        let reply = """
        Here is what I found:
        trip|Kyoto|2027-02-04|✈️
        - event | Jo & Lee wedding | 2027-05-01 | 💒
        birthday|Grandma|2027-08-03|
        trip|Kyoto|2027-02-04|✈️
        meeting|Standup|2027-01-01|📅
        event|Bad date|2027-02-30|🎉
        event||2027-06-01|🎉
        event|Too old|1066-10-14|⚔️
        """
        let found = TextDateFinder.parse(reply)
        XCTAssertEqual(found.map { $0.name }, ["Kyoto", "Jo & Lee wedding", "Grandma"])
        XCTAssertEqual(found.map { $0.emoji }, ["✈️", "💒", "🎂"])
        XCTAssertEqual(found.map { $0.oneTime }, [true, true, false])
        XCTAssertEqual(found.first?.year, 2027)
        XCTAssertNil(found.last?.year, "a birthday found in text never takes that year as the birth year")
        XCTAssertEqual(found.first?.kindLabel, "Trip")
    }

    func testDraftForATripIsOneTimeWithShortReminders() {
        let trip = FoundDate(name: "Kyoto", kind: .custom, emoji: "✈️", month: 2, day: 4, year: 2027, oneTime: true)
        let draft = trip.draft(palette: .ocean, reminderHour: 8, reminderMinute: 30)
        XCTAssertTrue(draft.isOneTime)
        XCTAssertEqual(draft.reminderOffsets, [7, 1])
        XCTAssertEqual(draft.reminderHour, 8)
        XCTAssertEqual(draft.name, "Kyoto")
    }

    func testDetectorFallbackFindsFutureDatesAndSpotsATrip() throws {
        let calendar = utcCalendar()
        let now = try date(2026, 10, 7, calendar: calendar)
        let email = """
        Booking confirmed
        Your flight UA 837 San Francisco to Osaka departs on February 4, 2027.
        Your last trip was on March 3, 2025.
        """
        let found = TextDateFinder.detectDates(in: email, now: now, calendar: calendar)
        XCTAssertEqual(found.count, 1, "past dates are dropped")
        let trip = try XCTUnwrap(found.first)
        XCTAssertEqual(trip.name, "Trip")
        XCTAssertEqual(trip.emoji, "✈️")
        XCTAssertEqual([trip.year, trip.month, trip.day], [2027, 2, 4])
        XCTAssertTrue(trip.oneTime)
    }

    func testDetectorFallbackNamesAPlainEventFromItsFirstLine() throws {
        let calendar = utcCalendar()
        let now = try date(2026, 10, 7, calendar: calendar)
        let invite = "Sam's graduation party\nJoin us on June 12, 2027 at the park."
        let found = TextDateFinder.detectDates(in: invite, now: now, calendar: calendar)
        let event = try XCTUnwrap(found.first)
        XCTAssertEqual(event.name, "Sam's graduation party")
        XCTAssertEqual(event.emoji, "🎉")
    }

    func testInstructionsCarryToday() throws {
        let calendar = utcCalendar()
        let text = TextDateFinder.instructions(today: try date(2026, 10, 7, calendar: calendar), calendar: calendar)
        XCTAssertTrue(text.contains("2026-10-07"))
        XCTAssertTrue(text.contains("kind|name|YYYY-MM-DD|emoji"))
    }
}
