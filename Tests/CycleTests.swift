import XCTest
@testable import SaveTheDate

private func utcCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone.current
    calendar.locale = Locale(identifier: "en_US_POSIX")
    return calendar
}

private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, calendar: Calendar) throws -> Date {
    var c = DateComponents()
    c.year = year; c.month = month; c.day = day; c.hour = hour
    return try XCTUnwrap(calendar.date(from: c))
}

private func day(_ year: Int, _ month: Int, _ day: Int) -> CalendarDay {
    return CalendarDay(year: year, month: month, day: day)
}

private func cycleOccasion(_ data: CycleData) -> Occasion {
    let last = data.starts.last ?? day(2026, 1, 1)
    return Occasion(name: "Cycle", kind: .cycle, month: last.month, day: last.day,
                    reminderOffsets: [2, 0], cycle: data)
}

@MainActor
final class CycleTests: XCTestCase {

    func testUsualLengthUntilTwoStartsAreLogged() {
        let calendar = utcCalendar()
        let data = CycleData(starts: [day(2026, 9, 20)], usualCycleLength: 30)
        XCTAssertEqual(OccasionMath.predictedCycleLength(data, calendar: calendar), 30)
        let next = OccasionMath.nextPeriodStart(data, calendar: calendar)
        XCTAssertEqual(next.map { CalendarDay(date: $0, calendar: calendar) }, day(2026, 10, 20))
    }

    func testMedianOfTheLastSixCyclesIgnoringImplausibleGaps() {
        let calendar = utcCalendar()
        // Lengths: 27, 29, 60 (a missed log, ignored), 28, 31, 26, 30 -> last six plausible: 29, 28, 31, 26, 30 + 27
        let data = CycleData(starts: [
            day(2026, 1, 1), day(2026, 1, 28), day(2026, 2, 26), day(2026, 4, 27),
            day(2026, 5, 25), day(2026, 6, 25), day(2026, 7, 21), day(2026, 8, 20)
        ])
        XCTAssertEqual(OccasionMath.cycleLengths(data, calendar: calendar), [27, 29, 28, 31, 26, 30])
        XCTAssertEqual(OccasionMath.predictedCycleLength(data, calendar: calendar), 29, "median of 26 27 28 29 30 31 rounds 28.5 up")
    }

    func testStatusInPeriodUpcomingAndLate() throws {
        let calendar = utcCalendar()
        let data = CycleData(starts: [day(2026, 9, 1), day(2026, 9, 29)], periodLength: 5)
        XCTAssertEqual(OccasionMath.cycleStatus(data, today: try date(2026, 10, 1, calendar: calendar), calendar: calendar), .inPeriod(day: 3))
        XCTAssertEqual(OccasionMath.cycleStatus(data, today: try date(2026, 10, 20, calendar: calendar), calendar: calendar), .upcoming(days: 7))
        XCTAssertEqual(OccasionMath.cycleStatus(data, today: try date(2026, 10, 29, calendar: calendar), calendar: calendar), .late(days: 2))
    }

    func testLoggingKeepsDaysInOrderAndOnce() {
        var data = CycleData(starts: [day(2026, 9, 29)])
        data.log(day(2026, 9, 1))
        data.log(day(2026, 9, 29))
        XCTAssertEqual(data.starts, [day(2026, 9, 1), day(2026, 9, 29)])
        data.remove(day(2026, 9, 1))
        XCTAssertEqual(data.starts, [day(2026, 9, 29)])
    }

    func testAKindWithNoStartsIsNotTreatedAsACycle() {
        let empty = Occasion(name: "Cycle", kind: .cycle, month: 1, day: 1, cycle: CycleData(starts: []))
        XCTAssertFalse(empty.isCycle)
    }

    func testRemindersAreDiscreetByDefaultAndOnlyForTheNextStart() throws {
        let calendar = utcCalendar()
        let occasion = cycleOccasion(CycleData(starts: [day(2026, 9, 1), day(2026, 9, 29)]))
        let items = ReminderPlan.notifications(for: occasion, now: try date(2026, 10, 10, calendar: calendar), calendar: calendar, cycles: 2)
        XCTAssertEqual(items.map { $0.offset }, [2, 0], "one reminder per offset, no second cycle")
        XCTAssertEqual(items.first?.title, "🌸 Cycle reminder")
        XCTAssertEqual(items.first?.body, "Expected in 2 days")
        XCTAssertFalse(items.contains { $0.body.lowercased().contains("period") })
        XCTAssertEqual(items.last.map { CalendarDay(date: $0.fireDate, calendar: calendar) }, day(2026, 10, 27))

        var explicit = occasion
        explicit.cycle?.discreet = false
        let open = ReminderPlan.notifications(for: explicit, now: try date(2026, 10, 10, calendar: calendar), calendar: calendar)
        XCTAssertEqual(open.last?.body, "Your period is expected today")
    }

    func testALateCycleSortsAsDueNotPast() throws {
        let calendar = utcCalendar()
        let today = try date(2026, 10, 29, calendar: calendar)
        let store = OccasionStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true))
        store.add(Occasion(name: "Old trip", kind: .custom, month: 1, day: 10, year: 2026, oneTime: true))
        store.add(Occasion(name: "Mum", kind: .birthday, month: 11, day: 3))
        store.add(cycleOccasion(CycleData(starts: [day(2026, 9, 1), day(2026, 9, 29)])))

        let late = try XCTUnwrap(store.occasions.first { $0.kind == .cycle })
        XCTAssertFalse(OccasionMath.isPast(late, from: today, calendar: calendar))
        XCTAssertEqual(store.sorted(today: today, calendar: calendar).map { $0.name }, ["Cycle", "Mum", "Old trip"])
    }

    func testOlderFilesWithoutCycleStillLoad() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let json = """
        {"version":1,"occasions":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Mom","kind":"birthday","emoji":"🎂","month":3,"day":14,"reminderOffsets":[7],"reminderHour":9,"reminderMinute":0,"note":"","palette":"sunset","createdAt":"2026-01-01T00:00:00Z"}]}
        """
        try XCTUnwrap(json.data(using: .utf8)).write(to: directory.appendingPathComponent("occasions.json"))
        let store = OccasionStore(directory: directory)
        XCTAssertNil(store.occasions.first?.cycle)
    }
}
