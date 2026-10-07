import Foundation

/// The three examples a brand new install starts with, so the app has something
/// to show and the reviewer has data on screen. They are ordinary dates: the user
/// can edit or delete them. They do not use a free slot (see `OccasionStore`).
enum SampleDates {
    static func make(now: Date = Date(), calendar: Calendar = .current) -> [Occasion] {
        var made: [Occasion] = []
        for sample in samples {
            guard let date = calendar.date(byAdding: .day, value: sample.inDays, to: now) else { continue }
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            guard let month = parts.month, let day = parts.day else { continue }
            made.append(Occasion(
                name: sample.name,
                kind: sample.kind,
                emoji: sample.emoji,
                month: month,
                day: day,
                year: sample.oneTime ? parts.year : sample.year,
                reminderOffsets: sample.offsets,
                note: "An example to get you started. Edit it, or swipe left to delete it.",
                palette: sample.palette,
                isSample: true,
                oneTime: sample.oneTime ? true : nil
            ))
        }
        return made
    }

    private struct Sample {
        let name: String
        let kind: OccasionKind
        let emoji: String?
        let inDays: Int
        let year: Int?
        let offsets: [Int]
        let palette: OccasionPalette
        let oneTime: Bool
    }

    private static let samples: [Sample] = [
        Sample(name: "Mum's birthday", kind: .birthday, emoji: nil, inDays: 16, year: 1962,
               offsets: [7, 1, 0], palette: .sunset, oneTime: false),
        Sample(name: "Our anniversary", kind: .anniversary, emoji: nil, inDays: 54, year: 2019,
               offsets: [14, 1], palette: .berry, oneTime: false),
        Sample(name: "Trip to Kyoto", kind: .custom, emoji: "✈️", inDays: 121, year: nil,
               offsets: [30, 7, 1], palette: .ocean, oneTime: true)
    ]
}
