import XCTest
@testable import SaveTheDate

private func utcCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone.current
    calendar.locale = Locale(identifier: "en_US_POSIX")
    return calendar
}

private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, calendar: Calendar) throws -> Date {
    var c = DateComponents()
    c.year = year; c.month = month; c.day = day; c.hour = hour; c.minute = minute
    return try XCTUnwrap(calendar.date(from: c))
}

final class OccasionMathTests: XCTestCase {

    private func occasion(month: Int, day: Int, year: Int? = nil, kind: OccasionKind = .birthday) -> Occasion {
        return Occasion(name: "Test", kind: kind, month: month, day: day, year: year)
    }

    func testNextOccurrenceLaterThisYear() throws {
        let calendar = utcCalendar()
        let today = try date(2026, 3, 1, calendar: calendar)
        let expected = try date(2026, 3, 14, calendar: calendar)
        let occ = occasion(month: 3, day: 14)
        XCTAssertEqual(OccasionMath.nextOccurrence(of: occ, from: today, calendar: calendar), expected)
        XCTAssertEqual(OccasionMath.daysUntil(occ, from: today, calendar: calendar), 13)
    }

    func testTodayIsTheDay() throws {
        let calendar = utcCalendar()
        let today = try date(2026, 3, 14, calendar: calendar)
        let occ = occasion(month: 3, day: 14)
        XCTAssertEqual(OccasionMath.nextOccurrence(of: occ, from: today, calendar: calendar), today)
        XCTAssertEqual(OccasionMath.daysUntil(occ, from: today, calendar: calendar), 0)
    }

    func testAlreadyPassedRollsToNextYear() throws {
        let calendar = utcCalendar()
        let today = try date(2026, 3, 15, calendar: calendar)
        let expected = try date(2027, 3, 14, calendar: calendar)
        let occ = occasion(month: 3, day: 14)
        XCTAssertEqual(OccasionMath.nextOccurrence(of: occ, from: today, calendar: calendar), expected)
        XCTAssertEqual(OccasionMath.daysUntil(occ, from: today, calendar: calendar), 364)
    }

    func testYearBoundary() throws {
        let calendar = utcCalendar()
        let today = try date(2026, 12, 31, calendar: calendar)
        let expected = try date(2027, 1, 1, calendar: calendar)
        let occ = occasion(month: 1, day: 1)
        XCTAssertEqual(OccasionMath.nextOccurrence(of: occ, from: today, calendar: calendar), expected)
        XCTAssertEqual(OccasionMath.daysUntil(occ, from: today, calendar: calendar), 1)
    }

    func testFeb29OnNonLeapYear() throws {
        let calendar = utcCalendar()
        let today = try date(2026, 1, 10, calendar: calendar)
        let expected = try date(2026, 2, 28, calendar: calendar)
        let occ = occasion(month: 2, day: 29)
        XCTAssertEqual(OccasionMath.nextOccurrence(of: occ, from: today, calendar: calendar), expected)
        XCTAssertEqual(OccasionMath.daysUntil(occ, from: today, calendar: calendar), 49)
    }

    func testFeb29OnLeapYear() throws {
        let calendar = utcCalendar()
        let today = try date(2028, 1, 10, calendar: calendar)
        let expected = try date(2028, 2, 29, calendar: calendar)
        let occ = occasion(month: 2, day: 29)
        XCTAssertEqual(OccasionMath.nextOccurrence(of: occ, from: today, calendar: calendar), expected)
        XCTAssertEqual(OccasionMath.daysUntil(occ, from: today, calendar: calendar), 50)
    }

    func testFeb29AfterFebruaryInNonLeapYear() throws {
        let calendar = utcCalendar()
        let today = try date(2027, 3, 1, calendar: calendar)
        let expected = try date(2028, 2, 29, calendar: calendar)
        let occ = occasion(month: 2, day: 29)
        XCTAssertEqual(OccasionMath.nextOccurrence(of: occ, from: today, calendar: calendar), expected)
    }

    func testFeb29WhenTodayIsFeb28OfNonLeapYear() throws {
        let calendar = utcCalendar()
        let today = try date(2026, 2, 28, calendar: calendar)
        let occ = occasion(month: 2, day: 29)
        XCTAssertEqual(OccasionMath.nextOccurrence(of: occ, from: today, calendar: calendar), today)
        XCTAssertEqual(OccasionMath.daysUntil(occ, from: today, calendar: calendar), 0)
    }

    func testYearsOn() throws {
        let calendar = utcCalendar()
        let occurrence = try date(2026, 3, 14, calendar: calendar)
        XCTAssertEqual(OccasionMath.yearsOn(occurrence: occurrence, startYear: 1996, calendar: calendar), 30)
        XCTAssertNil(OccasionMath.yearsOn(occurrence: occurrence, startYear: 2026, calendar: calendar))
    }

    func testMilestoneTextByKind() {
        XCTAssertEqual(OccasionMath.milestoneText(kind: .birthday, years: 30), "turns 30")
        XCTAssertEqual(OccasionMath.milestoneText(kind: .anniversary, years: 5), "5th anniversary")
        XCTAssertEqual(OccasionMath.milestoneText(kind: .custom, years: 1), "1 year")
        XCTAssertEqual(OccasionMath.milestoneText(kind: .custom, years: 3), "3 years")
    }

    func testMilestoneTextForOccasionWithoutYearIsNil() throws {
        let calendar = utcCalendar()
        let today = try date(2026, 3, 1, calendar: calendar)
        let occ = occasion(month: 3, day: 14, year: nil)
        XCTAssertNil(OccasionMath.milestoneText(for: occ, today: today, calendar: calendar))
    }

    func testMilestoneTextForOccasionWithYear() throws {
        let calendar = utcCalendar()
        let today = try date(2026, 3, 1, calendar: calendar)
        let occ = occasion(month: 3, day: 14, year: 1996, kind: .birthday)
        XCTAssertEqual(OccasionMath.milestoneText(for: occ, today: today, calendar: calendar), "turns 30")
    }

    func testOrdinal() {
        XCTAssertEqual(OccasionMath.ordinal(1), "1st")
        XCTAssertEqual(OccasionMath.ordinal(2), "2nd")
        XCTAssertEqual(OccasionMath.ordinal(3), "3rd")
        XCTAssertEqual(OccasionMath.ordinal(4), "4th")
        XCTAssertEqual(OccasionMath.ordinal(11), "11th")
        XCTAssertEqual(OccasionMath.ordinal(12), "12th")
        XCTAssertEqual(OccasionMath.ordinal(13), "13th")
        XCTAssertEqual(OccasionMath.ordinal(21), "21st")
        XCTAssertEqual(OccasionMath.ordinal(22), "22nd")
        XCTAssertEqual(OccasionMath.ordinal(23), "23rd")
        XCTAssertEqual(OccasionMath.ordinal(101), "101st")
        XCTAssertEqual(OccasionMath.ordinal(111), "111th")
        XCTAssertEqual(OccasionMath.ordinal(112), "112th")
    }

    func testCountdownText() {
        XCTAssertEqual(OccasionMath.countdownText(days: 0), "It's today!!")
        XCTAssertEqual(OccasionMath.countdownText(days: 1), "Tomorrow!")
        XCTAssertEqual(OccasionMath.countdownText(days: 12), "12 days to go")
    }

    func testOffsetLabel() {
        XCTAssertEqual(OccasionMath.offsetLabel(0), "On the day")
        XCTAssertEqual(OccasionMath.offsetLabel(1), "1 day before")
        XCTAssertEqual(OccasionMath.offsetLabel(14), "14 days before")
    }

    func testIsValid() {
        XCTAssertTrue(OccasionMath.isValid(month: 2, day: 29))
        XCTAssertFalse(OccasionMath.isValid(month: 2, day: 30))
        XCTAssertFalse(OccasionMath.isValid(month: 4, day: 31))
        XCTAssertFalse(OccasionMath.isValid(month: 13, day: 1))
        XCTAssertTrue(OccasionMath.isValid(month: 12, day: 31))
        XCTAssertFalse(OccasionMath.isValid(month: 0, day: 1))
    }

    func testDaysInMonth() {
        XCTAssertEqual(OccasionMath.daysInMonth(2), 29)
        XCTAssertEqual(OccasionMath.daysInMonth(4), 30)
    }

    func testDateText() {
        let calendar = utcCalendar()
        XCTAssertEqual(OccasionMath.dateText(month: 3, day: 14, year: nil, calendar: calendar), "March 14")
        XCTAssertEqual(OccasionMath.dateText(month: 3, day: 14, year: 1994, calendar: calendar), "March 14, 1994")
    }
}
