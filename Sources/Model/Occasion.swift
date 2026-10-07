import Foundation

enum OccasionKind: String, Codable, CaseIterable, Identifiable {
    case birthday
    case anniversary
    case custom

    var id: String { return rawValue }

    var label: String {
        switch self {
        case .birthday:
            return "Birthday"
        case .anniversary:
            return "Anniversary"
        case .custom:
            return "Other"
        }
    }

    var defaultEmoji: String {
        switch self {
        case .birthday:
            return "🎂"
        case .anniversary:
            return "💍"
        case .custom:
            return "🎉"
        }
    }
}

enum OccasionPalette: String, Codable, CaseIterable {
    case sunset, ocean, berry, lime, candy, midnight, peach, grape

    static func forIndex(_ index: Int) -> OccasionPalette {
        let all = OccasionPalette.allCases
        return all[abs(index) % all.count]
    }

    static func random() -> OccasionPalette {
        return OccasionPalette.allCases.randomElement() ?? .sunset
    }
}

struct Occasion: Identifiable, Codable, Equatable, Hashable {
    static let defaultReminderOffsets: [Int] = [7, 1, 0]
    static let presetReminderOffsets: [Int] = [0, 1, 3, 7, 14, 30]

    var id: UUID
    var name: String
    var kind: OccasionKind
    var emoji: String
    var month: Int
    var day: Int
    var year: Int?
    var reminderOffsets: [Int]
    var reminderHour: Int
    var reminderMinute: Int
    var note: String
    var palette: OccasionPalette
    var createdAt: Date
    var contactIdentifier: String?
    /// Set on the examples seeded at first launch. They do not use a free slot,
    /// and the flag is cleared the moment the user edits one. Optional so files
    /// written before this existed still decode.
    var isSample: Bool?
    /// A JPEG in the store's photos folder, shown on the card instead of the emoji.
    /// It is the square the user framed in the cropper.
    var photoFileName: String?
    /// The whole photo, for viewing full screen and for re-framing later. Older
    /// dates have only the square.
    var photoFullFileName: String?
    /// True for a date that happens once, such as a flight. Optional so older
    /// files still decode; they repeat yearly.
    var oneTime: Bool?

    init(
        id: UUID = UUID(),
        name: String,
        kind: OccasionKind,
        emoji: String? = nil,
        month: Int,
        day: Int,
        year: Int? = nil,
        reminderOffsets: [Int] = Occasion.defaultReminderOffsets,
        reminderHour: Int = 9,
        reminderMinute: Int = 0,
        note: String = "",
        palette: OccasionPalette = .sunset,
        createdAt: Date = Date(),
        contactIdentifier: String? = nil,
        isSample: Bool? = nil,
        photoFileName: String? = nil,
        photoFullFileName: String? = nil,
        oneTime: Bool? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.emoji = emoji ?? kind.defaultEmoji
        self.month = month
        self.day = day
        self.year = year
        self.reminderOffsets = reminderOffsets
        self.reminderHour = reminderHour
        self.reminderMinute = reminderMinute
        self.note = note
        self.palette = palette
        self.createdAt = createdAt
        self.contactIdentifier = contactIdentifier
        self.isSample = isSample
        self.photoFileName = photoFileName
        self.photoFullFileName = photoFullFileName
        self.oneTime = oneTime
    }

    /// A one-time date needs its year to mean anything; without one it repeats.
    var isOneTime: Bool {
        return oneTime == true && year != nil
    }

    var isSeededSample: Bool {
        return isSample == true
    }

    var displayEmoji: String {
        return emoji.isEmpty ? kind.defaultEmoji : emoji
    }
}

/// UserDefaults keys and defaults shared by views and services.
enum AppDefaults {
    static let reminderHourKey: String = "defaultReminderHour"
    static let reminderMinuteKey: String = "defaultReminderMinute"
    static let isUnlockedKey: String = "isUnlocked"
    static let hasSeededSamplesKey: String = "hasSeededSamples"
    static let keepsSamplesKey: String = "keepsSamples"
    static let defaultReminderHour: Int = 9
    static let defaultReminderMinute: Int = 0
}
