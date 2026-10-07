import XCTest
@testable import SaveTheDate

private func utcCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone.current
    calendar.locale = Locale(identifier: "en_US_POSIX")
    return calendar
}

private func event(_ title: String, _ year: Int, _ month: Int, _ day: Int,
                   birthdayCalendar: Bool = false, yearly: Bool = false) throws -> CalendarEventInfo {
    var c = DateComponents()
    c.year = year; c.month = month; c.day = day; c.hour = 10
    let start = try XCTUnwrap(utcCalendar().date(from: c))
    return CalendarEventInfo(id: "ev-\(title)", title: title, start: start,
                             isBirthdayCalendar: birthdayCalendar, repeatsYearly: yearly)
}

final class CalendarScannerTests: XCTestCase {

    func testBirthdayCalendarGivesAYearlyBirthdayWithoutAYear() throws {
        let found = try XCTUnwrap(CalendarClassifier.classify(
            try event("Alex’s 30th Birthday", 2027, 4, 9, birthdayCalendar: true), calendar: utcCalendar()))
        XCTAssertEqual(found.name, "Alex")
        XCTAssertEqual(found.kind, .birthday)
        XCTAssertNil(found.year, "the event's year is this year's party, not the birth year")
        XCTAssertFalse(found.oneTime)
        XCTAssertEqual(found.id, "calendar|ev-Alex’s 30th Birthday")
    }

    func testNameCleanup() {
        XCTAssertEqual(CalendarClassifier.cleanedName("Mum's birthday"), "Mum")
        XCTAssertEqual(CalendarClassifier.cleanedName("Birthday: Sam"), "Sam")
        XCTAssertEqual(CalendarClassifier.cleanedName("Mum & Dad’s Anniversary"), "Mum & Dad")
        XCTAssertEqual(CalendarClassifier.cleanedName("Our anniversary"), "Our anniversary")
        XCTAssertEqual(CalendarClassifier.cleanedName("Birthday"), "Birthday")
    }

    func testFlightIsAOneTimeTripWithItsYear() throws {
        let found = try XCTUnwrap(CalendarClassifier.classify(
            try event("Flight to Kyoto UA837", 2027, 2, 4), calendar: utcCalendar()))
        XCTAssertEqual(found.kind, .custom)
        XCTAssertEqual(found.emoji, "✈️")
        XCTAssertTrue(found.oneTime)
        XCTAssertEqual(found.year, 2027)
        XCTAssertEqual(found.kindLabel, "Trip")

        let occasion = found.makeOccasion(palette: .ocean, reminderHour: 9, reminderMinute: 0)
        XCTAssertTrue(occasion.isOneTime)
        XCTAssertEqual(occasion.contactIdentifier, found.id)
    }

    func testYearlyRepeatingEventIsKeptAndMeetingsAreNot() throws {
        let lease = try XCTUnwrap(CalendarClassifier.classify(
            try event("Lease renewal", 2027, 6, 1, yearly: true), calendar: utcCalendar()))
        XCTAssertFalse(lease.oneTime)
        XCTAssertNil(lease.year)

        XCTAssertNil(CalendarClassifier.classify(try event("Weekly sync", 2027, 6, 2), calendar: utcCalendar()))
        XCTAssertNil(CalendarClassifier.classify(try event("   ", 2027, 6, 2), calendar: utcCalendar()))
    }

    func testPromptNumbersEachTitle() throws {
        let prompt = CalendarClassifier.prompt(for: [try event("Dentist", 2027, 1, 1), try event("Jo & Lee wedding", 2027, 5, 1)])
        XCTAssertTrue(prompt.contains("0. Dentist"))
        XCTAssertTrue(prompt.contains("1. Jo & Lee wedding"))
    }

    func testParserKeepsGoodLinesAndSkipsJunk() throws {
        let events = [
            try event("Dentist", 2027, 1, 1),
            try event("Jo & Lee", 2027, 5, 1),
            try event("Taylor Swift", 2027, 7, 12),
            try event("Grandma 90", 2027, 8, 3)
        ]
        let reply = """
        Sure! Here are the milestones:
        1|event|Jo & Lee's wedding|💒
        - 2 | event | Taylor Swift concert | 🎤
        3|birthday|Grandma|
        7|trip|Out of range|✈️
        0|meeting|Dentist|🦷
        2|event|Duplicate index|🎉
        1|event||🎉
        """
        let found = CalendarClassifier.parse(reply, events: events, calendar: utcCalendar())
        XCTAssertEqual(found.map { $0.name }, ["Jo & Lee's wedding", "Taylor Swift concert", "Grandma"])
        XCTAssertEqual(found.map { $0.emoji }, ["💒", "🎤", "🎂"])
        XCTAssertEqual(found.map { $0.oneTime }, [true, true, false])
        XCTAssertEqual(found.first?.year, 2027)
    }
}
