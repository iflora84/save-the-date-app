import Foundation

struct PlannedNotification: Equatable {
    let identifier: String
    let occasionID: UUID
    let offset: Int
    let fireDate: Date
    let dateComponents: DateComponents
    let title: String
    let body: String
}

enum ReminderPlan {
    static let identifierPrefix: String = "occasion-"
    static let maxOffsetDays: Int = 365

    static func identifier(occasionID: UUID, offset: Int, cycle: Int = 0) -> String {
        if cycle == 0 {
            return "\(identifierPrefix)\(occasionID.uuidString)-\(offset)"
        }
        return "\(identifierPrefix)\(occasionID.uuidString)-\(offset)-y\(cycle)"
    }

    /// `cycles` is how many future occurrences to plan per offset. iOS triggers are
    /// one-shot, so planning only the next one means reminders stop for anyone who
    /// never reopens the app.
    static func notifications(for occasion: Occasion, now: Date, calendar: Calendar, cycles: Int = 1) -> [PlannedNotification] {
        let validOffsets = occasion.reminderOffsets.filter { $0 >= 0 && $0 <= maxOffsetDays }
        let offsets = Array(Set(validOffsets)).sorted(by: >)
        if offsets.isEmpty {
            return []
        }

        let first = OccasionMath.nextOccurrence(of: occasion, from: now, calendar: calendar)
        guard let dayAfterFirst = calendar.date(byAdding: .day, value: 1, to: first) else {
            return []
        }
        let second = OccasionMath.nextOccurrence(of: occasion, from: dayAfterFirst, calendar: calendar)

        var planned: [PlannedNotification] = []
        for offset in offsets {
            guard let firstFire = fireDate(for: first, offset: offset, occasion: occasion, calendar: calendar) else {
                continue
            }
            var occurrence = first
            var fire: Date? = firstFire
            if firstFire <= now {
                occurrence = second
                fire = fireDate(for: second, offset: offset, occasion: occasion, calendar: calendar)
            }
            var cycle = 0
            // A one-time date has no next year to plan for.
            let cycleCount = (occasion.isOneTime || occasion.isCycle) ? 1 : max(1, cycles)
            while cycle < cycleCount {
                guard let fireInstant = fire, fireInstant > now else {
                    break
                }
                var years: Int? = nil
                if let startYear = occasion.year {
                    years = OccasionMath.yearsOn(occurrence: occurrence, startYear: startYear, calendar: calendar)
                }
                let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireInstant)
                planned.append(PlannedNotification(
                    identifier: identifier(occasionID: occasion.id, offset: offset, cycle: cycle),
                    occasionID: occasion.id,
                    offset: offset,
                    fireDate: fireInstant,
                    dateComponents: components,
                    title: occasion.isCycle ? cycleTitle(occasion) : title(offset: offset, emoji: occasion.displayEmoji),
                    body: occasion.isCycle ? cycleBody(occasion, offset: offset) : body(occasion: occasion, offset: offset, years: years)
                ))
                cycle += 1
                guard let dayAfter = calendar.date(byAdding: .day, value: 1, to: occurrence) else {
                    break
                }
                occurrence = OccasionMath.nextOccurrence(of: occasion, from: dayAfter, calendar: calendar)
                fire = fireDate(for: occurrence, offset: offset, occasion: occasion, calendar: calendar)
            }
        }
        return planned.sorted { $0.fireDate < $1.fireDate }
    }

    /// A cycle is re-predicted every time a start is logged, so only the next one is
    /// planned. Discreet text keeps the lock screen neutral.
    static func cycleTitle(_ occasion: Occasion) -> String {
        let discreet = occasion.cycle?.discreet ?? true
        return "\(occasion.displayEmoji) " + (discreet ? "Cycle reminder" : "Period reminder")
    }

    static func cycleBody(_ occasion: Occasion, offset: Int) -> String {
        let discreet = occasion.cycle?.discreet ?? true
        let when: String
        if offset == 0 {
            when = "today"
        } else if offset == 1 {
            when = "tomorrow"
        } else {
            when = "in \(offset) days"
        }
        return discreet ? "Expected \(when)" : "Your period is expected \(when)"
    }

    static func title(offset: Int, emoji: String) -> String {
        return "\(emoji) \(OccasionMath.countdownText(days: offset))"
    }

    static func body(occasion: Occasion, offset: Int, years: Int?) -> String {
        let when = whenText(offset: offset)
        let name = occasion.name
        switch occasion.kind {
        case .birthday:
            if let years = years {
                return "\(name)'s birthday \(when) — \(OccasionMath.milestoneText(kind: .birthday, years: years))"
            }
            return "\(name)'s birthday \(when)"
        case .anniversary:
            if let years = years {
                return "\(name)'s \(OccasionMath.ordinal(years)) anniversary \(when)"
            }
            return "\(name)'s anniversary \(when)"
        case .custom, .cycle:
            if let years = years {
                return "\(name) \(when) — \(OccasionMath.milestoneText(kind: .custom, years: years))"
            }
            return "\(name) \(when)"
        }
    }

    private static func whenText(offset: Int) -> String {
        if offset == 0 {
            return "is today"
        }
        if offset == 1 {
            return "is tomorrow"
        }
        return "is in \(offset) days"
    }

    private static func fireDate(for occurrence: Date, offset: Int, occasion: Occasion, calendar: Calendar) -> Date? {
        guard let day = calendar.date(byAdding: .day, value: -offset, to: occurrence) else {
            return nil
        }
        return calendar.date(bySettingHour: occasion.reminderHour, minute: occasion.reminderMinute, second: 0, of: day)
    }
}
