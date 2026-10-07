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

    /// For a one-time date this is its only occurrence, which may be in the past.
    /// For a cycle it is the predicted next start, which is in the past when late.
    static func nextOccurrence(of occasion: Occasion, from today: Date, calendar: Calendar) -> Date {
        if occasion.isCycle, let cycle = occasion.cycle, let next = nextPeriodStart(cycle, calendar: calendar) {
            return next
        }
        if occasion.isOneTime, let year = occasion.year,
           let only = occurrence(month: occasion.month, day: occasion.day, year: year, calendar: calendar) {
            return only
        }
        return nextOccurrence(month: occasion.month, day: occasion.day, from: today, calendar: calendar)
    }

    /// Negative once a one-time date has passed. Yearly dates never go below 0.
    static func daysUntil(_ occasion: Occasion, from today: Date, calendar: Calendar) -> Int {
        let todayStart = calendar.startOfDay(for: today)
        let next = nextOccurrence(of: occasion, from: today, calendar: calendar)
        return calendar.dateComponents([.day], from: todayStart, to: next).day ?? 0
    }

    /// One-time dates that have gone by. A late cycle is never "past": it is due.
    static func isPast(_ occasion: Occasion, from today: Date, calendar: Calendar) -> Bool {
        if occasion.isCycle { return false }
        return daysUntil(occasion, from: today, calendar: calendar) < 0
    }

    /// Where a date sorts on the list; a late cycle sorts as due today.
    static func listDays(_ occasion: Occasion, from today: Date, calendar: Calendar) -> Int {
        let days = daysUntil(occasion, from: today, calendar: calendar)
        return occasion.isCycle ? max(0, days) : days
    }

    enum CycleStatus: Equatable {
        case inPeriod(day: Int)
        case upcoming(days: Int)
        case late(days: Int)
    }

    /// Lengths between consecutive logged starts. Gaps outside a plausible range
    /// (a missed log, a typo) are left out of the prediction.
    static func cycleLengths(_ cycle: CycleData, calendar: Calendar) -> [Int] {
        let dates = cycle.starts.compactMap { $0.date(calendar: calendar) }
        var lengths: [Int] = []
        var index = 1
        while index < dates.count {
            if let days = calendar.dateComponents([.day], from: dates[index - 1], to: dates[index]).day,
               CycleData.cycleLengthRange.contains(days) {
                lengths.append(days)
            }
            index += 1
        }
        return lengths
    }

    /// The median of the last six cycles, or the usual length until there is one.
    static func predictedCycleLength(_ cycle: CycleData, calendar: Calendar) -> Int {
        let recent = Array(cycleLengths(cycle, calendar: calendar).suffix(6)).sorted()
        if recent.isEmpty {
            return cycle.usualCycleLength
        }
        let middle = recent.count / 2
        if recent.count % 2 == 1 {
            return recent[middle]
        }
        return Int((Double(recent[middle - 1] + recent[middle]) / 2.0).rounded())
    }

    static func nextPeriodStart(_ cycle: CycleData, calendar: Calendar) -> Date? {
        guard let last = cycle.starts.last?.date(calendar: calendar) else { return nil }
        return calendar.date(byAdding: .day, value: predictedCycleLength(cycle, calendar: calendar), to: last)
    }

    static func cycleStatus(_ cycle: CycleData, today: Date, calendar: Calendar) -> CycleStatus? {
        guard let last = cycle.starts.last?.date(calendar: calendar),
              let next = nextPeriodStart(cycle, calendar: calendar) else {
            return nil
        }
        let todayStart = calendar.startOfDay(for: today)
        let sinceStart = calendar.dateComponents([.day], from: last, to: todayStart).day ?? 0
        if sinceStart >= 0 && sinceStart < cycle.periodLength {
            return .inPeriod(day: sinceStart + 1)
        }
        let until = calendar.dateComponents([.day], from: todayStart, to: next).day ?? 0
        return until >= 0 ? .upcoming(days: until) : .late(days: -until)
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
        case .custom, .cycle:
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
        if days == -1 {
            return "Yesterday"
        }
        if days < 0 {
            return "\(-days) days ago"
        }
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
