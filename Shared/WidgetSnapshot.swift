import Foundation

/// What the widgets show, written by the app into the App Group container each
/// time the dates change. The widget never reads occasions.json, so the app's own
/// storage did not have to move.
struct WidgetSnapshot: Codable, Equatable {
    struct Item: Codable, Equatable, Identifiable {
        let id: UUID
        let name: String
        let emoji: String
        /// Start-of-day dates of the next occurrences, earliest first. Two are kept
        /// for yearly dates so the widget stays right after one passes.
        let occurrences: [Date]
        /// The card's two gradient colours as 0xRRGGBB.
        let gradient: [UInt32]
        /// A small square photo in the App Group container, if the date has one.
        let photoFile: String?
        let isCycle: Bool

        /// The first occurrence on or after `day`; a late cycle keeps its last
        /// prediction so it can say "late".
        func nextOccurrence(onOrAfter day: Date, calendar: Calendar) -> Date? {
            let start = calendar.startOfDay(for: day)
            if let upcoming = occurrences.first(where: { $0 >= start }) {
                return upcoming
            }
            return isCycle ? occurrences.last : nil
        }

        /// Days from `day` to the next occurrence; negative only for a late cycle.
        func daysUntil(from day: Date, calendar: Calendar) -> Int? {
            guard let next = nextOccurrence(onOrAfter: day, calendar: calendar) else { return nil }
            return calendar.dateComponents([.day], from: calendar.startOfDay(for: day), to: next).day
        }
    }

    let items: [Item]

    static let fileName: String = "widget.json"

    /// Items still ahead on `day`, soonest first; a late cycle counts as due today.
    func upcoming(on day: Date, calendar: Calendar) -> [Item] {
        let ranked = items.compactMap { item -> (Item, Int)? in
            guard let days = item.daysUntil(from: day, calendar: calendar) else { return nil }
            return (item, max(0, days))
        }
        return ranked.sorted { $0.1 < $1.1 }.map { $0.0 }
    }

    static func load(from directory: URL) -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(fileName)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    @discardableResult
    func save(to directory: URL) -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try encoder.encode(self).write(to: directory.appendingPathComponent(WidgetSnapshot.fileName), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// The App Group folder both the app and the widget can read.
    static var directory: URL? {
        return FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SharedInbox.groupID)?
            .appendingPathComponent("Widget", isDirectory: true)
    }
}
