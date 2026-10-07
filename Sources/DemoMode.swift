import Foundation

/// Screenshot support. The app behaves normally unless it is launched with
/// `-demo <screen>`, which only happens from the Screenshots CI workflow.
enum DemoMode {
    static let price: String = "$2.99"

    static var screen: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-demo"), index + 1 < arguments.count else {
            return nil
        }
        return arguments[index + 1]
    }

    static var isActive: Bool {
        return screen != nil
    }

    static var isUnlocked: Bool {
        return ProcessInfo.processInfo.arguments.contains("-unlocked")
    }

    static func purchaseDefaults() -> UserDefaults {
        let defaults = UserDefaults.standard
        if isActive {
            defaults.set(isUnlocked, forKey: AppDefaults.isUnlockedKey)
        }
        return defaults
    }

    static func demoPrice() -> String? {
        return isActive ? price : nil
    }

    /// Sample data for the screenshots, or nil in a normal launch.
    /// Locked runs stay inside the free tier so the list and the paywall agree.
    static func seed(now: Date = Date(), calendar: Calendar = .current) -> [Occasion]? {
        guard isActive else { return nil }
        var seeded: [Occasion] = []
        for sample in samples(unlocked: isUnlocked) {
            guard let date = calendar.date(byAdding: .day, value: sample.inDays, to: now) else { continue }
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            guard let month = parts.month, let day = parts.day else { continue }
            seeded.append(Occasion(
                name: sample.name,
                kind: sample.kind,
                emoji: sample.emoji,
                month: month,
                day: day,
                year: sample.oneTime ? parts.year : sample.year,
                reminderOffsets: sample.offsets,
                note: sample.note,
                palette: sample.palette,
                // The Screenshots workflow copies these into the store's photos folder.
                photoFileName: sample.photo.map { $0 + ".jpg" },
                photoFullFileName: sample.photo.map { $0 + "-full.jpg" },
                oneTime: sample.oneTime ? true : nil
            ))
        }
        return seeded
    }

    private struct Sample {
        let name: String
        let kind: OccasionKind
        let emoji: String?
        let inDays: Int
        let year: Int?
        let offsets: [Int]
        let note: String
        let palette: OccasionPalette
        var oneTime: Bool = false
        var photo: String? = nil
    }

    private static func samples(unlocked: Bool) -> [Sample] {
        let free: [Sample] = [
            Sample(name: "Mum", kind: .birthday, emoji: nil, inDays: 10, year: 1961,
                   offsets: [7, 1, 0], note: "Book the table at Trattoria.", palette: .sunset, photo: "mum"),
            Sample(name: "Alex & Sam", kind: .anniversary, emoji: nil, inDays: 12, year: 2019,
                   offsets: [14, 1], note: "", palette: .berry, photo: "couple"),
            Sample(name: "Kyoto trip", kind: .custom, emoji: "✈️", inDays: 24, year: nil,
                   offsets: [30, 7, 1], note: "Flights booked.", palette: .ocean, oneTime: true)
        ]
        if !unlocked {
            return free
        }
        return free + [
            Sample(name: "Dad", kind: .birthday, emoji: nil, inDays: 45, year: 1958,
                   offsets: [7, 0], note: "", palette: .grape, photo: "dad"),
            Sample(name: "Nina", kind: .birthday, emoji: "🌻", inDays: 83, year: 1994,
                   offsets: [3, 0], note: "", palette: .lime, photo: "nina"),
            Sample(name: "Lease renewal", kind: .custom, emoji: "🔑", inDays: 148, year: nil,
                   offsets: [30, 7], note: "Give notice 60 days ahead.", palette: .midnight)
        ]
    }

    static let pastedEmail: String = """
    Your trip is confirmed
    Flight UA 837 · San Francisco (SFO) to Osaka Kansai (KIX)
    Thursday 4 February 2027, departs 11:05
    Booking reference K7Q2PX · 1 adult
    """

    /// What "Found 1 date" shows in the screenshots.
    static func foundResult(now: Date = Date(), calendar: Calendar = .current) -> TextDateFinder.Result {
        let year = calendar.component(.year, from: now) + 1
        return TextDateFinder.Result(
            dates: [FoundDate(name: "Flight to Osaka", kind: .custom, emoji: "✈️", month: 2, day: 4, year: year, oneTime: true)],
            usedAI: true
        )
    }

    /// What "Find in Calendar" shows in the screenshots.
    static func calendarResult(now: Date = Date(), calendar: Calendar = .current) -> CalendarScanner.Result {
        let next = calendar.component(.year, from: now) + 1
        let rows: [(String, OccasionKind, String, Int, Int, Int?, Bool)] = [
            ("Grandma", .birthday, "🎂", 3, 3, nil, false),
            ("Jo & Lee's wedding", .custom, "💒", 5, 1, next, true),
            ("Flight to Lisbon", .custom, "✈️", 6, 12, next, true),
            ("Sam's graduation", .custom, "🎓", 7, 2, next, true),
            ("Our anniversary", .anniversary, "💍", 8, 20, nil, false),
            ("Lease renewal", .custom, "🎉", 9, 1, nil, false)
        ]
        let candidates = rows.map { row in
            return CalendarCandidate(id: "calendar|demo-" + row.0, name: row.0, kind: row.1, emoji: row.2,
                                     month: row.3, day: row.4, year: row.5, oneTime: row.6)
        }
        return CalendarScanner.Result(candidates: candidates, usedAI: true)
    }
}
