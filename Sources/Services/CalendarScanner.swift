import Foundation
import EventKit

/// One calendar event reduced to what the classifier needs, so the rules can be
/// tested without EventKit.
struct CalendarEventInfo: Equatable {
    let id: String
    let title: String
    let start: Date
    let isBirthdayCalendar: Bool
    let repeatsYearly: Bool
}

struct CalendarCandidate: Identifiable, Equatable, Hashable {
    /// "calendar|<event id>", stored in `contactIdentifier` so a re-scan shows it as saved.
    let id: String
    let name: String
    let kind: OccasionKind
    let emoji: String
    let month: Int
    let day: Int
    let year: Int?
    let oneTime: Bool

    var kindLabel: String {
        if oneTime && kind == .custom {
            return emoji == "✈️" ? "Trip" : "Once"
        }
        return kind.label
    }

    func makeOccasion(palette: OccasionPalette, reminderHour: Int, reminderMinute: Int) -> Occasion {
        return Occasion(
            name: name,
            kind: kind,
            emoji: emoji,
            month: month,
            day: day,
            year: year,
            reminderOffsets: oneTime ? [7, 1] : Occasion.defaultReminderOffsets,
            reminderHour: reminderHour,
            reminderMinute: reminderMinute,
            note: "",
            palette: palette,
            createdAt: Date(),
            contactIdentifier: id,
            oneTime: oneTime ? true : nil
        )
    }
}

enum CalendarClassifier {
    static let idPrefix: String = "calendar|"

    private static let birthdayWords: [String] = ["birthday", "bday", "b-day"]
    private static let tripWords: [String] = [
        "flight", "✈", "trip", "vacation", "holiday", "travel", "hotel",
        "check-in", "check in", "boarding", "airport", "honeymoon"
    ]
    private static let milestoneWords: [String: String] = [
        "wedding": "💒", "graduation": "🎓", "due date": "👶", "moving day": "🏡", "concert": "🎤"
    ]

    /// Rules that need no model. Birthday-calendar events carry this year's date, not
    /// the birth year, so birthdays never get a year from here.
    static func classify(_ event: CalendarEventInfo, calendar: Calendar) -> CalendarCandidate? {
        let title = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty { return nil }
        let lower = title.lowercased()

        if event.isBirthdayCalendar || containsAny(lower, birthdayWords) {
            return candidate(event, name: cleanedName(title), kind: .birthday, emoji: "🎂", oneTime: false, calendar: calendar)
        }
        if lower.contains("anniversary") {
            return candidate(event, name: cleanedName(title), kind: .anniversary, emoji: "💍", oneTime: false, calendar: calendar)
        }
        if containsAny(lower, tripWords) {
            return candidate(event, name: title, kind: .custom, emoji: "✈️", oneTime: !event.repeatsYearly, calendar: calendar)
        }
        for (word, emoji) in milestoneWords where lower.contains(word) {
            return candidate(event, name: title, kind: .custom, emoji: emoji, oneTime: !event.repeatsYearly, calendar: calendar)
        }
        // Someone set this to repeat every year by hand, so it matters to them.
        if event.repeatsYearly {
            return candidate(event, name: title, kind: .custom, emoji: "🎉", oneTime: false, calendar: calendar)
        }
        return nil
    }

    /// "Alex’s 30th Birthday" -> "Alex". Falls back to the full title when nothing
    /// sensible is left ("Our anniversary" stays as it is).
    static func cleanedName(_ title: String) -> String {
        var name = title
        let patterns = [
            "(?i)['’]s\\b",
            "(?i)\\b\\d+(st|nd|rd|th)\\b",
            "(?i)\\b(happy|birthday|bday|b-day|anniversary|party)\\b",
            "[:!🎂🎉💍🥳🎈]"
        ]
        for pattern in patterns {
            name = name.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        name = name.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: " -–—,.&"))
        let tooVague: Set<String> = ["", "our", "my", "wedding", "mum and dad", "mom and dad"]
        if name.count < 2 || tooVague.contains(name.lowercased()) {
            return title
        }
        return name
    }

    static let instructions: String = """
    You pick personal milestones out of calendar event titles: birthdays, anniversaries, \
    trips, and once-in-a-while life events such as a wedding, graduation, concert, move or due date. \
    Ignore work meetings, routine appointments, classes, chores and reminders. \
    Answer only with lines in the form index|kind|name|emoji where kind is one of \
    birthday, anniversary, trip, event and name is a short title of at most four words. \
    Write nothing for events to ignore.
    """

    static func prompt(for events: [CalendarEventInfo]) -> String {
        var lines: [String] = ["Events:"]
        for (index, event) in events.enumerated() {
            lines.append("\(index). \(event.title)")
        }
        return lines.joined(separator: "\n")
    }

    /// Reads the model's lines. Anything malformed (prose, a bad index, an unknown
    /// kind, an empty name) is skipped rather than trusted.
    static func parse(_ reply: String, events: [CalendarEventInfo], calendar: Calendar) -> [CalendarCandidate] {
        var found: [CalendarCandidate] = []
        var seen: Set<Int> = []
        for rawLine in reply.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: CharacterSet(charactersIn: " -*•\t"))
            let fields = line.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            guard fields.count >= 3,
                  let index = Int(fields[0].trimmingCharacters(in: CharacterSet(charactersIn: ". "))),
                  index >= 0, index < events.count, !seen.contains(index) else {
                continue
            }
            let event = events[index]
            let name = String(fields[2].prefix(40))
            if name.isEmpty { continue }
            let suggestedEmoji = fields.count >= 4 ? firstEmoji(fields[3]) : nil
            let made: CalendarCandidate?
            switch fields[1].lowercased() {
            case "birthday":
                made = candidate(event, name: cleanedName(name), kind: .birthday, emoji: suggestedEmoji ?? "🎂", oneTime: false, calendar: calendar)
            case "anniversary":
                made = candidate(event, name: cleanedName(name), kind: .anniversary, emoji: suggestedEmoji ?? "💍", oneTime: false, calendar: calendar)
            case "trip":
                made = candidate(event, name: name, kind: .custom, emoji: suggestedEmoji ?? "✈️", oneTime: !event.repeatsYearly, calendar: calendar)
            case "event":
                made = candidate(event, name: name, kind: .custom, emoji: suggestedEmoji ?? "🎉", oneTime: !event.repeatsYearly, calendar: calendar)
            default:
                made = nil
            }
            if let made = made {
                found.append(made)
                seen.insert(index)
            }
        }
        return found
    }

    private static func containsAny(_ text: String, _ words: [String]) -> Bool {
        return words.contains { text.contains($0) }
    }

    private static func firstEmoji(_ text: String) -> String? {
        guard let first = text.first,
              let scalar = first.unicodeScalars.first,
              scalar.properties.isEmoji, scalar.value > 0x238C else {
            return nil
        }
        return String(first)
    }

    private static func candidate(_ event: CalendarEventInfo, name: String, kind: OccasionKind, emoji: String, oneTime: Bool, calendar: Calendar) -> CalendarCandidate? {
        let parts = calendar.dateComponents([.year, .month, .day], from: event.start)
        guard let month = parts.month, let day = parts.day, OccasionMath.isValid(month: month, day: day) else {
            return nil
        }
        return CalendarCandidate(
            id: idPrefix + event.id,
            name: name,
            kind: kind,
            emoji: emoji,
            month: month,
            day: day,
            year: oneTime ? parts.year : nil,
            oneTime: oneTime
        )
    }
}

final class CalendarScanner {
    enum AccessState: Equatable {
        case notDetermined
        case authorized
        case denied
    }

    struct Result {
        let candidates: [CalendarCandidate]
        let usedAI: Bool
    }

    private static let aiBatchSize: Int = 25
    private static let aiMaxEvents: Int = 75

    private let store: EKEventStore

    init() {
        self.store = EKEventStore()
    }

    /// Write-only access cannot read events, so it counts as denied.
    static func accessState() -> AccessState {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined:
            return .notDetermined
        case .fullAccess:
            return .authorized
        case .denied, .restricted, .writeOnly:
            return .denied
        case .authorized:
            return .authorized
        @unknown default:
            return .denied
        }
    }

    func requestAccess() async throws -> Bool {
        return try await store.requestFullAccessToEvents()
    }

    /// Rules first; on phones with Apple Intelligence the model then reads the titles
    /// the rules skipped. `usedAI` is true only when the model actually answered.
    func scan(now: Date = Date(), calendar: Calendar = .current) async -> Result {
        let events = fetchEvents(now: now, calendar: calendar)
        var candidates: [CalendarCandidate] = []
        var unmatched: [CalendarEventInfo] = []
        for event in events {
            if let match = CalendarClassifier.classify(event, calendar: calendar) {
                candidates.append(match)
            } else {
                unmatched.append(event)
            }
        }

        var usedAI = false
        if OnDeviceAI.isAvailable && !unmatched.isEmpty {
            let pool = Array(unmatched.prefix(CalendarScanner.aiMaxEvents))
            var start = 0
            while start < pool.count {
                let batch = Array(pool[start..<min(start + CalendarScanner.aiBatchSize, pool.count)])
                let prompt = CalendarClassifier.prompt(for: batch)
                if let reply = await OnDeviceAI.respond(instructions: CalendarClassifier.instructions, prompt: prompt) {
                    usedAI = true
                    candidates.append(contentsOf: CalendarClassifier.parse(reply, events: batch, calendar: calendar))
                }
                start += CalendarScanner.aiBatchSize
            }
        }

        let byDate = Dictionary(events.map { (CalendarClassifier.idPrefix + $0.id, $0.start) }, uniquingKeysWith: { first, _ in first })
        candidates.sort { a, b in
            return (byDate[a.id] ?? .distantFuture) < (byDate[b.id] ?? .distantFuture)
        }
        return Result(candidates: candidates, usedAI: usedAI)
    }

    /// The next 365 days, so a yearly event shows up once. Subscribed calendars
    /// (public holidays, sports fixtures) and events repeating more than yearly
    /// are left out.
    private func fetchEvents(now: Date, calendar: Calendar) -> [CalendarEventInfo] {
        let start = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: 365, to: start) else { return [] }
        let calendars = store.calendars(for: .event).filter { $0.type != .subscription }
        if calendars.isEmpty { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        let events = store.events(matching: predicate).sorted { $0.startDate < $1.startDate }

        var seenIDs: Set<String> = []
        var infos: [CalendarEventInfo] = []
        for event in events {
            let id = event.calendarItemIdentifier
            if seenIDs.contains(id) { continue }
            seenIDs.insert(id)
            var repeatsYearly = false
            if let rules = event.recurrenceRules, let rule = rules.first {
                if rule.frequency != .yearly { continue }
                repeatsYearly = true
            }
            infos.append(CalendarEventInfo(
                id: id,
                title: event.title ?? "",
                start: event.startDate,
                isBirthdayCalendar: event.calendar.type == .birthday,
                repeatsYearly: repeatsYearly
            ))
        }
        return infos
    }
}
