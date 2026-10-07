import XCTest
@testable import SaveTheDate

final class SharedInboxTests: XCTestCase {

    private func makeDirectory() -> URL {
        return FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    func testItemsComeOutOldestFirstAndOnlyOnce() {
        let inbox = makeDirectory()
        XCTAssertTrue(SharedInbox.save(.text("second"), in: inbox, now: Date(timeIntervalSince1970: 2_000)))
        XCTAssertTrue(SharedInbox.save(.image(Data([0xFF, 0xD8])), in: inbox, now: Date(timeIntervalSince1970: 3_000)))
        XCTAssertTrue(SharedInbox.save(.text("first"), in: inbox, now: Date(timeIntervalSince1970: 1_000)))

        XCTAssertEqual(SharedInbox.takeOldest(from: inbox), .text("first"))
        XCTAssertEqual(SharedInbox.takeOldest(from: inbox), .text("second"))
        XCTAssertEqual(SharedInbox.takeOldest(from: inbox), .image(Data([0xFF, 0xD8])))
        XCTAssertNil(SharedInbox.takeOldest(from: inbox))
    }

    func testEmptyOrMissingFilesAreSkipped() throws {
        let inbox = makeDirectory()
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        try Data().write(to: inbox.appendingPathComponent("000000000000001-a.txt"))
        try Data("ignored".utf8).write(to: inbox.appendingPathComponent("notes.md"))
        SharedInbox.save(.text("Flight to Kyoto, 4 Feb 2027"), in: inbox, now: Date(timeIntervalSince1970: 5))

        XCTAssertEqual(SharedInbox.takeOldest(from: inbox), .text("Flight to Kyoto, 4 Feb 2027"))
        XCTAssertNil(SharedInbox.takeOldest(from: inbox))
        XCTAssertNil(SharedInbox.takeOldest(from: makeDirectory()), "a folder that was never created is just empty")
    }
}
