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

@MainActor
final class WidgetSnapshotTests: XCTestCase {

    func testSnapshotIsSoonestFirstWithoutPastDates() throws {
        let calendar = utcCalendar()
        let today = try date(2026, 10, 7, calendar: calendar)
        let occasions = [
            Occasion(name: "Christmas", kind: .custom, month: 12, day: 25),
            Occasion(name: "Old trip", kind: .custom, month: 1, day: 10, year: 2026, oneTime: true),
            Occasion(name: "Mum", kind: .birthday, month: 10, day: 17, palette: .sunset)
        ]
        let snapshot = WidgetBridge.makeSnapshot(from: occasions, today: today, calendar: calendar)
        XCTAssertEqual(snapshot.items.map { $0.name }, ["Mum", "Christmas"])
        XCTAssertEqual(snapshot.items.first?.gradient, [0x8A3F30, 0x9E5C3C])
    }

    func testYearlyDatesCarryTwoOccurrencesSoTheWidgetRollsOver() throws {
        let calendar = utcCalendar()
        let today = try date(2026, 10, 7, calendar: calendar)
        let mum = Occasion(name: "Mum", kind: .birthday, month: 10, day: 17)
        let snapshot = WidgetBridge.makeSnapshot(from: [mum], today: today, calendar: calendar)
        let item = try XCTUnwrap(snapshot.items.first)
        XCTAssertEqual(item.occurrences.count, 2)

        XCTAssertEqual(item.daysUntil(from: today, calendar: calendar), 10)
        // The widget is never refreshed by the app for a few weeks: it still counts.
        let later = try date(2026, 10, 20, calendar: calendar)
        XCTAssertEqual(item.daysUntil(from: later, calendar: calendar), 362)
    }

    func testOneTimeDateDropsOutAfterItPasses() throws {
        let calendar = utcCalendar()
        let today = try date(2026, 10, 7, calendar: calendar)
        let trip = Occasion(name: "Trip", kind: .custom, month: 10, day: 9, year: 2026, oneTime: true)
        let snapshot = WidgetBridge.makeSnapshot(from: [trip], today: today, calendar: calendar)
        XCTAssertEqual(snapshot.upcoming(on: today, calendar: calendar).count, 1)
        XCTAssertEqual(snapshot.upcoming(on: try date(2026, 10, 10, calendar: calendar), calendar: calendar).count, 0)
    }

    func testALateCycleStaysOnTheWidgetAsDue() throws {
        let calendar = utcCalendar()
        let today = try date(2026, 10, 7, calendar: calendar)
        let cycle = Occasion(name: "Cycle", kind: .cycle, month: 9, day: 29,
                             cycle: CycleData(starts: [CalendarDay(year: 2026, month: 9, day: 1), CalendarDay(year: 2026, month: 9, day: 29)]))
        let snapshot = WidgetBridge.makeSnapshot(from: [cycle], today: today, calendar: calendar)
        let item = try XCTUnwrap(snapshot.items.first)
        XCTAssertTrue(item.isCycle)
        let late = try date(2026, 10, 29, calendar: calendar)
        XCTAssertEqual(item.daysUntil(from: late, calendar: calendar), -2)
        XCTAssertEqual(snapshot.upcoming(on: late, calendar: calendar).map { $0.name }, ["Cycle"])
    }

    func testSnapshotRoundTripsThroughDisk() throws {
        let calendar = utcCalendar()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let snapshot = WidgetBridge.makeSnapshot(
            from: [Occasion(name: "Mum", kind: .birthday, month: 10, day: 17)],
            today: try date(2026, 10, 7, calendar: calendar), calendar: calendar,
            photoFiles: [:]
        )
        XCTAssertTrue(snapshot.save(to: directory))
        XCTAssertEqual(WidgetSnapshot.load(from: directory), snapshot)
    }

    func testAtMostEightItems() throws {
        let calendar = utcCalendar()
        let occasions = (1...12).map { Occasion(name: "D\($0)", kind: .birthday, month: 11, day: $0) }
        let snapshot = WidgetBridge.makeSnapshot(from: occasions, today: try date(2026, 10, 7, calendar: calendar), calendar: calendar)
        XCTAssertEqual(snapshot.items.count, WidgetBridge.maxItems)
        XCTAssertEqual(snapshot.items.first?.name, "D1")
    }
}
