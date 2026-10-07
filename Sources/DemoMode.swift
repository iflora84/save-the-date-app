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
    }

    private static func samples(unlocked: Bool) -> [Sample] {
        let free: [Sample] = [
            Sample(name: "Mum", kind: .birthday, emoji: nil, inDays: 0, year: 1961,
                   offsets: [7, 1, 0], note: "Book the table at Trattoria.", palette: .sunset),
            Sample(name: "Alex & Sam", kind: .anniversary, emoji: nil, inDays: 1, year: 2019,
                   offsets: [14, 1], note: "", palette: .berry),
            Sample(name: "Kyoto trip", kind: .custom, emoji: "✈️", inDays: 12, year: nil,
                   offsets: [30, 7, 1], note: "Flights booked.", palette: .ocean, oneTime: true)
        ]
        if !unlocked {
            return free
        }
        return free + [
            Sample(name: "Dad", kind: .birthday, emoji: nil, inDays: 45, year: 1958,
                   offsets: [7, 0], note: "", palette: .grape),
            Sample(name: "Nina", kind: .birthday, emoji: "🌻", inDays: 83, year: 1994,
                   offsets: [3, 0], note: "", palette: .lime),
            Sample(name: "Lease renewal", kind: .custom, emoji: "🔑", inDays: 148, year: nil,
                   offsets: [30, 7], note: "Give notice 60 days ahead.", palette: .midnight)
        ]
    }
}
