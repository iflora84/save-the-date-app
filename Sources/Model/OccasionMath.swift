import Foundation

enum OccasionMath {
    private static let monthLengths: [Int] = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]

    static func daysInMonth(_ month: Int) -> Int {
        if month < 1 || month > 12 {
            return 31
        }
        return monthLengths[month - 1]
    }

    static func isValid(month: Int, day: Int) -> Bool {
        return (1...12).contains(month) && (1...daysInMonth(month)).contains(day)
    }

    static func occurrence(month: Int, day: Int, year: Int, calendar: Calendar) -> Date? {
        var firstComponents = DateComponents()
        firstComponents.year = year
        firstComponents.month = month
        firstComponents.day = 1
        guard let firstOfMonth = calendar.date(from: firstComponents),
              let range = calendar.range(of: .day, in: .month, for: firstOfMonth) else {
            return nil
        }
        let clampedDay = min(max(1, day), range.count)
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = clampedDay
        return calendar.date(from: components)
    }

    static func nextOccurrence(month: Int, day: Int, from today: Date, calendar: Calendar) -> Date {
        let todayStart = calendar.startOfDay(for: today)
        let currentYear = calendar.component(.year, from: todayStart)
        if let thisYear = occurrence(month: month, day: day, year: currentYear, calendar: calendar),
           thisYear >= todayStart {
            return thisYear
        }
        return occurrence(month: month, day: day, year: currentYear + 1, calendar: calendar) ?? todayStart
    }

    static func nextOccurrence(of occasion: Occasion, from today: Date, calendar: Calendar) -> Date {
        return nextOccurrence(month: occasion.month, day: occasion.day, from: today, calendar: calendar)
    }

    static func daysUntil(_ occasion: Occasion, from today: Date, calendar: Calendar) -> Int {
        let todayStart = calendar.startOfDay(for: today)
        let next = nextOccurrence(of: occasion, from: today, calendar: calendar)
        return calendar.dateComponents([.day], from: todayStart, to: next).day ?? 0
    }

    static func yearsOn(occurrence: Date, startYear: Int, calendar: Calendar) -> Int? {
        let years = calendar.component(.year, from: occurrence) - startYear
        if years <= 0 {
            return nil
        }
        return years
    }

    static func ordinal(_ n: Int) -> String {
        let mod100 = n % 100
        if mod100 >= 11 && mod100 <= 13 { return "\(n)th" }
        switch n % 10 {
        case 1: return "\(n)st"
        case 2: return "\(n)nd"
        case 3: return "\(n)rd"
        default: return "\(n)th"
        }
    }

    static func milestoneText(kind: OccasionKind, years: Int) -> String {
        switch kind {
        case .birthday:
            return "turns \(years)"
        case .anniversary:
            return "\(ordinal(years)) anniversary"
        case .custom:
            return years == 1 ? "1 year" : "\(years) years"
        }
    }

    static func milestoneText(for occasion: Occasion, today: Date, calendar: Calendar) -> String? {
        guard let startYear = occasion.year else {
            return nil
        }
        let next = nextOccurrence(of: occasion, from: today, calendar: calendar)
        guard let years = yearsOn(occurrence: next, startYear: startYear, calendar: calendar) else {
            return nil
        }
        return milestoneText(kind: occasion.kind, years: years)
    }

    static func countdownText(days: Int) -> String {
        if days == 0 {
            return "It's today!!"
        }
        if days == 1 {
            return "Tomorrow!"
        }
        return "\(days) days to go"
    }

    static func offsetLabel(_ offset: Int) -> String {
        if offset == 0 {
            return "On the day"
        }
        if offset == 1 {
            return "1 day before"
        }
        return "\(offset) days before"
    }

    static func monthName(_ month: Int, calendar: Calendar) -> String {
        let symbols = calendar.monthSymbols
        if symbols.isEmpty {
            return ""
        }
        let clamped = min(max(1, month), symbols.count)
        return symbols[clamped - 1]
    }

    static func dateText(month: Int, day: Int, year: Int?, calendar: Calendar) -> String {
        let base = "\(monthName(month, calendar: calendar)) \(day)"
        if let year = year {
            return base + ", " + String(year)
        }
        return base
    }

    static func dateText(of occasion: Occasion, calendar: Calendar) -> String {
        return dateText(month: occasion.month, day: occasion.day, year: occasion.year, calendar: calendar)
    }
}
