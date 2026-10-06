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

final class ReminderPlanTests: XCTestCase {

    private func assertComponents(
        _ components: DateComponents,
        year: Int, month: Int, day: Int, hour: Int, minute: Int,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(components.year, year, "year", file: file, line: line)
        XCTAssertEqual(components.month, month, "month", file: file, line: line)
        XCTAssertEqual(components.day, day, "day", file: file, line: line)
        XCTAssertEqual(components.hour, hour, "hour", file: file, line: line)
        XCTAssertEqual(components.minute, minute, "minute", file: file, line: line)
    }

    func testThreeOffsetsSortedByFireDate() throws {
        let calendar = utcCalendar()
        let now = try date(2026, 3, 1, 8, 0, calendar: calendar)
        let occasion = Occasion(name: "Test", kind: .birthday, month: 3, day: 14, reminderOffsets: [14, 3, 0], reminderHour: 9, reminderMinute: 0)

        let items = ReminderPlan.notifications(for: occasion, now: now, calendar: calendar)
        XCTAssertEqual(items.count, 3)

        let first = try XCTUnwrap(items.first)
        let second = try XCTUnwrap(items.dropFirst(1).first)
        let third = try XCTUnwrap(items.dropFirst(2).first)

        XCTAssertEqual(first.offset, 3)
        assertComponents(first.dateComponents, year: 2026, month: 3, day: 11, hour: 9, minute: 0)
        XCTAssertEqual(first.identifier, "occasion-\(occasion.id.uuidString)-3")

        XCTAssertEqual(second.offset, 0)
        assertComponents(second.dateComponents, year: 2026, month: 3, day: 14, hour: 9, minute: 0)
        XCTAssertEqual(second.identifier, "occasion-\(occasion.id.uuidString)-0")

        XCTAssertEqual(third.offset, 14)
        assertComponents(third.dateComponents, year: 2027, month: 2, day: 28, hour: 9, minute: 0)
        XCTAssertEqual(third.identifier, "occasion-\(occasion.id.uuidString)-14")

        XCTAssertTrue(first.fireDate < second.fireDate)
        XCTAssertTrue(second.fireDate < third.fireDate)
        XCTAssertEqual(first.occasionID, occasion.id)
    }

    func testTwoCyclesPlanNextTwoYears() throws {
        let calendar = utcCalendar()
        let now = try date(2026, 3, 1, 8, 0, calendar: calendar)
        let occasion = Occasion(name: "Test", kind: .birthday, month: 3, day: 14, reminderOffsets: [0], reminderHour: 9, reminderMinute: 0)

        let items = ReminderPlan.notifications(for: occasion, now: now, calendar: calendar, cycles: 2)
        XCTAssertEqual(items.count, 2)

        let thisYear = try XCTUnwrap(items.first)
        let nextYear = try XCTUnwrap(items.dropFirst(1).first)

        assertComponents(thisYear.dateComponents, year: 2026, month: 3, day: 14, hour: 9, minute: 0)
        assertComponents(nextYear.dateComponents, year: 2027, month: 3, day: 14, hour: 9, minute: 0)

        XCTAssertEqual(thisYear.identifier, "occasion-\(occasion.id.uuidString)-0")
        XCTAssertEqual(nextYear.identifier, "occasion-\(occasion.id.uuidString)-0-y1")
        XCTAssertNotEqual(thisYear.identifier, nextYear.identifier)
    }

    func testTwoCyclesDefaultStaysOneForASingleCycleCaller() throws {
        let calendar = utcCalendar()
        let now = try date(2026, 3, 1, 8, 0, calendar: calendar)
        let occasion = Occasion(name: "Test", kind: .birthday, month: 3, day: 14, reminderOffsets: [0], reminderHour: 9, reminderMinute: 0)

        XCTAssertEqual(ReminderPlan.notifications(for: occasion, now: now, calendar: calendar).count, 1)
    }

    func testDayOfAlreadyPassedUsesNextYear() throws {
        let calendar = utcCalendar()
        let now = try date(2026, 3, 14, 10, 0, calendar: calendar)
        let occasion = Occasion(name: "Test", kind: .birthday, month: 3, day: 14, reminderOffsets: [0], reminderHour: 9, reminderMinute: 0)

        let items = ReminderPlan.notifications(for: occasion, now: now, calendar: calendar)
        XCTAssertEqual(items.count, 1)
        let item = try XCTUnwrap(items.first)
        XCTAssertEqual(item.offset, 0)
        assertComponents(item.dateComponents, year: 2027, month: 3, day: 14, hour: 9, minute: 0)
    }

    func testDayOfStillAheadUsesThisYear() throws {
        let calendar = utcCalendar()
        let now = try date(2026, 3, 14, 8, 0, calendar: calendar)
        let occasion = Occasion(name: "Test", kind: .birthday, month: 3, day: 14, reminderOffsets: [0], reminderHour: 9, reminderMinute: 0)

        let items = ReminderPlan.notifications(for: occasion, now: now, calendar: calendar)
        XCTAssertEqual(items.count, 1)
        let item = try XCTUnwrap(items.first)
        assertComponents(item.dateComponents, year: 2026, month: 3, day: 14, hour: 9, minute: 0)
    }

    func testDedupeAndFilterOffsets() throws {
        let calendar = utcCalendar()
        let now = try date(2026, 3, 1, 8, 0, calendar: calendar)
        let occasion = Occasion(name: "Test", kind: .birthday, month: 3, day: 14, reminderOffsets: [3, 3, -1, 400], reminderHour: 9, reminderMinute: 0)

        let items = ReminderPlan.notifications(for: occasion, now: now, calendar: calendar)
        XCTAssertEqual(items.count, 1)
        let item = try XCTUnwrap(items.first)
        XCTAssertEqual(item.offset, 3)
    }

    func testBirthdayWording() throws {
        let calendar = utcCalendar()
        let now = try date(2026, 3, 1, 8, 0, calendar: calendar)
        let occasion = Occasion(name: "Mom", kind: .birthday, month: 3, day: 14, year: 1966, reminderOffsets: [3], reminderHour: 9, reminderMinute: 0)

        let items = ReminderPlan.notifications(for: occasion, now: now, calendar: calendar)
        let item = try XCTUnwrap(items.first)
        XCTAssertEqual(item.body, "Mom's birthday is in 3 days — turns 60")
        XCTAssertEqual(item.title, "🎂 3 days to go")
    }

    func testAnniversaryWording() throws {
        let calendar = utcCalendar()
        let now = try date(2026, 3, 1, 8, 0, calendar: calendar)
        let occasion = Occasion(name: "Alex & Sam", kind: .anniversary, month: 3, day: 14, year: 2021, reminderOffsets: [0], reminderHour: 9, reminderMinute: 0)

        let items = ReminderPlan.notifications(for: occasion, now: now, calendar: calendar)
        let item = try XCTUnwrap(items.first)
        XCTAssertEqual(item.body, "Alex & Sam's 5th anniversary is today")
        XCTAssertEqual(item.title, "💍 It's today!!")
    }

    func testCustomWording() throws {
        let calendar = utcCalendar()
        let now = try date(2026, 3, 1, 8, 0, calendar: calendar)
        let occasion = Occasion(name: "Trip to Japan", kind: .custom, month: 3, day: 14, year: nil, reminderOffsets: [1], reminderHour: 9, reminderMinute: 0)

        let items = ReminderPlan.notifications(for: occasion, now: now, calendar: calendar)
        let item = try XCTUnwrap(items.first)
        XCTAssertEqual(item.body, "Trip to Japan is tomorrow")
        XCTAssertEqual(item.title, "🎉 Tomorrow!")
    }

    func testEmptyOffsetsProduceNothing() throws {
        let calendar = utcCalendar()
        let now = try date(2026, 3, 1, 8, 0, calendar: calendar)
        let occasion = Occasion(name: "Test", kind: .birthday, month: 3, day: 14, reminderOffsets: [], reminderHour: 9, reminderMinute: 0)

        let items = ReminderPlan.notifications(for: occasion, now: now, calendar: calendar)
        XCTAssertTrue(items.isEmpty)
    }

    func testIdentifierFormat() {
        let id = UUID()
        XCTAssertEqual(ReminderPlan.identifier(occasionID: id, offset: 7), "occasion-\(id.uuidString)-7")
        XCTAssertTrue(ReminderPlan.identifier(occasionID: id, offset: 7).hasPrefix(ReminderPlan.identifierPrefix))
    }
}
