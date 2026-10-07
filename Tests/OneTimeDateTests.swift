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

private func kyoto(offsets: [Int] = [7, 1]) -> Occasion {
    return Occasion(name: "Kyoto", kind: .custom, emoji: "✈️", month: 2, day: 4, year: 2027,
                    reminderOffsets: offsets, oneTime: true)
}

@MainActor
final class OneTimeDateTests: XCTestCase {

    func testOneTimeNeedsAYear() {
        var trip = kyoto()
        XCTAssertTrue(trip.isOneTime)
        trip.year = nil
        XCTAssertFalse(trip.isOneTime, "without a year it falls back to repeating yearly")
    }

    func testDaysUntilGoesNegativeAfterTheDate() throws {
        let calendar = utcCalendar()
        let trip = kyoto()
        XCTAssertEqual(OccasionMath.daysUntil(trip, from: try date(2027, 2, 1, calendar: calendar), calendar: calendar), 3)
        XCTAssertEqual(OccasionMath.daysUntil(trip, from: try date(2027, 2, 4, calendar: calendar), calendar: calendar), 0)
        XCTAssertEqual(OccasionMath.daysUntil(trip, from: try date(2027, 2, 14, calendar: calendar), calendar: calendar), -10)

        var yearly = trip
        yearly.oneTime = nil
        XCTAssertEqual(OccasionMath.daysUntil(yearly, from: try date(2027, 2, 5, calendar: calendar), calendar: calendar), 364)
    }

    func testCountdownTextForPastDates() {
        XCTAssertEqual(OccasionMath.countdownText(days: -1), "Yesterday")
        XCTAssertEqual(OccasionMath.countdownText(days: -10), "10 days ago")
    }

    func testOneTimeGetsOneReminderPerOffsetAndNoneOnceItHasPassed() throws {
        let calendar = utcCalendar()
        let trip = kyoto()
        let before = ReminderPlan.notifications(for: trip, now: try date(2027, 1, 1, calendar: calendar), calendar: calendar, cycles: 2)
        XCTAssertEqual(before.map { $0.offset }, [7, 1], "no second year is planned")
        XCTAssertTrue(before.allSatisfy { calendar.component(.year, from: $0.fireDate) == 2027 })
        XCTAssertTrue(before.allSatisfy { !$0.body.contains("year") }, "no milestone text for a trip")

        let between = ReminderPlan.notifications(for: trip, now: try date(2027, 1, 30, calendar: calendar), calendar: calendar, cycles: 2)
        XCTAssertEqual(between.map { $0.offset }, [1], "the 7-day reminder has passed and does not roll to next year")

        let after = ReminderPlan.notifications(for: trip, now: try date(2027, 3, 1, calendar: calendar), calendar: calendar, cycles: 2)
        XCTAssertTrue(after.isEmpty)
    }

    func testPastOneTimeDatesSortAfterUpcomingOnes() throws {
        let calendar = utcCalendar()
        let today = try date(2027, 3, 1, calendar: calendar)
        let store = OccasionStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true))
        store.add(Occasion(name: "Old trip", kind: .custom, month: 1, day: 10, year: 2027, oneTime: true))
        store.add(Occasion(name: "Christmas", kind: .custom, month: 12, day: 25))
        store.add(Occasion(name: "Recent trip", kind: .custom, month: 2, day: 20, year: 2027, oneTime: true))
        store.add(Occasion(name: "Soon", kind: .birthday, month: 3, day: 5))

        let names = store.sorted(today: today, calendar: calendar).map { $0.name }
        XCTAssertEqual(names, ["Soon", "Christmas", "Recent trip", "Old trip"])
    }
}
