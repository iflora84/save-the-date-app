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

@MainActor
final class OccasionStoreTests: XCTestCase {

    private func makeDirectory() -> URL {
        return FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private func makeOccasion(name: String, month: Int, day: Int, contactIdentifier: String? = nil) -> Occasion {
        return Occasion(
            name: name,
            kind: .birthday,
            month: month,
            day: day,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            contactIdentifier: contactIdentifier
        )
    }

    func testStartsEmpty() {
        let store = OccasionStore(directory: makeDirectory())
        XCTAssertTrue(store.occasions.isEmpty)
    }

    func testAddPersistsAndReloads() {
        let directory = makeDirectory()
        let store = OccasionStore(directory: directory)
        let mom = makeOccasion(name: "Mom", month: 3, day: 14)
        let dad = makeOccasion(name: "Dad", month: 7, day: 4)
        store.add(mom)
        store.add(dad)
        XCTAssertEqual(store.occasions.count, 2)

        let reloaded = OccasionStore(directory: directory)
        XCTAssertEqual(reloaded.occasions, store.occasions)
        XCTAssertEqual(reloaded.occasions, [mom, dad])
    }

    func testAddWithSameIDReplaces() {
        let store = OccasionStore(directory: makeDirectory())
        var mom = makeOccasion(name: "Mom", month: 3, day: 14)
        store.add(mom)
        mom.name = "Mother"
        store.add(mom)
        XCTAssertEqual(store.occasions.count, 1)
        XCTAssertEqual(store.occasions.first?.name, "Mother")
    }

    func testUpdateReplacesByID() {
        let store = OccasionStore(directory: makeDirectory())
        var mom = makeOccasion(name: "Mom", month: 3, day: 14)
        store.add(mom)
        mom.name = "Mum"
        store.update(mom)
        XCTAssertEqual(store.occasions.count, 1)
        XCTAssertEqual(store.occasion(withID: mom.id)?.name, "Mum")
    }

    func testUpdateMissingIsNoOp() {
        let store = OccasionStore(directory: makeDirectory())
        store.add(makeOccasion(name: "Mom", month: 3, day: 14))
        store.update(makeOccasion(name: "Stranger", month: 1, day: 1))
        XCTAssertEqual(store.occasions.count, 1)
        XCTAssertEqual(store.occasions.first?.name, "Mom")
    }

    func testDeleteRemoves() {
        let store = OccasionStore(directory: makeDirectory())
        let mom = makeOccasion(name: "Mom", month: 3, day: 14)
        store.add(mom)
        store.delete(id: mom.id)
        XCTAssertTrue(store.occasions.isEmpty)
        XCTAssertNil(store.occasion(withID: mom.id))
    }

    func testFreeLimit() {
        let store = OccasionStore(directory: makeDirectory())
        for index in 1..<OccasionStore.freeLimit {
            store.add(makeOccasion(name: "Date \(index)", month: 1, day: index))
        }
        XCTAssertEqual(store.remainingFreeSlots(), 1)
        XCTAssertTrue(store.canAddMore(isUnlocked: false))

        store.add(makeOccasion(name: "Last", month: 2, day: 1))
        XCTAssertFalse(store.canAddMore(isUnlocked: false))
        XCTAssertTrue(store.canAddMore(isUnlocked: true))
        XCTAssertEqual(store.remainingFreeSlots(), 0)
    }

    func testContainsContactIdentifier() {
        let store = OccasionStore(directory: makeDirectory())
        store.add(makeOccasion(name: "Mom", month: 3, day: 14, contactIdentifier: "abc|birthday"))
        XCTAssertTrue(store.contains(contactIdentifier: "abc|birthday"))
        XCTAssertFalse(store.contains(contactIdentifier: "abc|anniversary"))
    }

    func testSortedByDaysUntil() throws {
        let calendar = utcCalendar()
        let today = try date(2026, 3, 1, calendar: calendar)
        let store = OccasionStore(directory: makeDirectory())
        store.add(makeOccasion(name: "March", month: 3, day: 14))
        store.add(makeOccasion(name: "Soon", month: 3, day: 2))
        store.add(makeOccasion(name: "Christmas", month: 12, day: 25))

        let names = store.sorted(today: today, calendar: calendar).map { $0.name }
        XCTAssertEqual(names, ["Soon", "March", "Christmas"])
    }

    func testCorruptFileLoadsEmpty() throws {
        let directory = makeDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("occasions.json", isDirectory: false)
        let garbage = try XCTUnwrap("garbage".data(using: .utf8))
        try garbage.write(to: fileURL)

        let store = OccasionStore(directory: directory)
        XCTAssertTrue(store.occasions.isEmpty)
        XCTAssertEqual(store.fileURL.path, fileURL.path)
    }

    func testSamplesAreSeededOnceAndDoNotUseFreeSlots() throws {
        let directory = makeDirectory()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "samples-\(UUID().uuidString)"))

        let first = OccasionStore(directory: directory, seedSamplesIfNew: true, defaults: defaults)
        XCTAssertEqual(first.occasions.count, 3)
        XCTAssertTrue(first.occasions.allSatisfy { $0.isSeededSample })
        XCTAssertEqual(first.userDateCount, 0)
        XCTAssertEqual(first.remainingFreeSlots(), OccasionStore.freeLimit)
        XCTAssertTrue(first.canAddMore(isUnlocked: false))

        first.delete(id: try XCTUnwrap(first.occasions.first).id)
        let second = OccasionStore(directory: directory, seedSamplesIfNew: true, defaults: defaults)
        XCTAssertEqual(second.occasions.count, 2, "deleting an example must not re-seed")
    }

    func testEmptyStoreIsNotSeededWithoutOptIn() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "nosamples-\(UUID().uuidString)"))
        let store = OccasionStore(directory: makeDirectory(), defaults: defaults)
        XCTAssertTrue(store.occasions.isEmpty)
    }

    func testEditedSampleCountsTowardTheFreeLimit() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "edited-\(UUID().uuidString)"))
        let store = OccasionStore(directory: makeDirectory(), seedSamplesIfNew: true, defaults: defaults)
        var sample = try XCTUnwrap(store.occasions.first)
        XCTAssertEqual(store.userDateCount, 0)
        sample.isSample = nil
        store.update(sample)
        XCTAssertEqual(store.userDateCount, 1)
        XCTAssertEqual(store.remainingFreeSlots(), OccasionStore.freeLimit - 1)
    }

    func testRemoveSamplesKeepsTheUsersOwnDates() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "remove-\(UUID().uuidString)"))
        let store = OccasionStore(directory: makeDirectory(), seedSamplesIfNew: true, defaults: defaults)
        let mom = makeOccasion(name: "Mom", month: 3, day: 14)
        store.add(mom)
        XCTAssertTrue(store.hasSamples)

        store.removeSamples()
        XCTAssertFalse(store.hasSamples)
        XCTAssertEqual(store.occasions, [mom])
    }
}
