import Foundation

enum OccasionKind: String, Codable, CaseIterable, Identifiable {
    case birthday
    case anniversary
    case custom
    /// A menstrual cycle. Named "Cycle" with a flower so a glance at the list
    /// gives nothing away; the date's page says what it is.
    case cycle

    var id: String { return rawValue }

    var label: String {
        switch self {
        case .birthday:
            return "Birthday"
        case .anniversary:
            return "Anniversary"
        case .custom:
            return "Other"
        case .cycle:
            return "Cycle"
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
        case .cycle:
            return "🌸"
        }
    }
}

/// A calendar day with no time of day, so a logged period start never shifts
/// when the phone changes time zone.
struct CalendarDay: Codable, Equatable, Hashable, Comparable {
    var year: Int
    var month: Int
    var day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    init(date: Date, calendar: Calendar) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.year = parts.year ?? 2000
        self.month = parts.month ?? 1
        self.day = parts.day ?? 1
    }

    func date(calendar: Calendar) -> Date? {
        var parts = DateComponents()
        parts.year = year
        parts.month = month
        parts.day = day
        return calendar.date(from: parts)
    }

    static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
        if lhs.year != rhs.year { return lhs.year < rhs.year }
        if lhs.month != rhs.month { return lhs.month < rhs.month }
        return lhs.day < rhs.day
    }
}

/// Period tracking for a `.cycle` date. Everything stays in occasions.json on the phone.
struct CycleData: Codable, Equatable, Hashable {
    static let defaultCycleLength: Int = 28
    static let defaultPeriodLength: Int = 5
    static let cycleLengthRange: ClosedRange<Int> = 18...45
    static let periodLengthRange: ClosedRange<Int> = 2...10

    /// Logged period start days, oldest first.
    var starts: [CalendarDay]
    /// Used for the prediction until two starts have been logged.
    var usualCycleLength: Int
    var periodLength: Int
    /// Lock-screen reminders say "Cycle" rather than "period" when true.
    var discreet: Bool

    init(starts: [CalendarDay], usualCycleLength: Int = CycleData.defaultCycleLength,
         periodLength: Int = CycleData.defaultPeriodLength, discreet: Bool = true) {
        self.starts = starts.sorted()
        self.usualCycleLength = usualCycleLength
        self.periodLength = periodLength
        self.discreet = discreet
    }

    /// Adds a start once; days are kept in order.
    mutating func log(_ day: CalendarDay) {
        if starts.contains(day) { return }
        starts.append(day)
        starts.sort()
    }

    mutating func remove(_ day: CalendarDay) {
        starts.removeAll { $0 == day }
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
    /// Only on `.cycle` dates.
    var cycle: CycleData?

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
        oneTime: Bool? = nil,
        cycle: CycleData? = nil
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
        self.cycle = cycle
    }

    /// A one-time date needs its year to mean anything; without one it repeats.
    var isOneTime: Bool {
        return oneTime == true && year != nil
    }

    /// A cycle needs at least one logged start to predict anything.
    var isCycle: Bool {
        return kind == .cycle && !(cycle?.starts.isEmpty ?? true)
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
