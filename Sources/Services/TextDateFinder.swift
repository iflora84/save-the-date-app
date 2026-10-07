import Foundation
import UIKit
import Vision

/// A date pulled out of pasted text or a screenshot, waiting for the user to check
/// it in the editor.
struct FoundDate: Identifiable, Equatable, Hashable {
    let id: UUID = UUID()
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

    /// Starting point for the editor; the palette is the caller's choice.
    func draft(palette: OccasionPalette, reminderHour: Int, reminderMinute: Int) -> Occasion {
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
            palette: palette,
            oneTime: oneTime ? true : nil
        )
    }
}

enum TextDateFinder {
    struct Result {
        let dates: [FoundDate]
        let usedAI: Bool
    }

    /// A date written in the text, as the system's date detector read it.
    struct DetectedDate: Equatable {
        let month: Int
        let day: Int
        let year: Int
        /// The words the date was read from, e.g. "Thursday 4 February 2027".
        let snippet: String
    }

    /// The on-device model's window is small (about 4K tokens, and CJK text costs
    /// roughly a token per character), so long emails are cut.
    static let maxCharacters: Int = 2000
    private static let maxResults: Int = 5
    private static let tripWords: [String] = [
        "flight", "boarding", "depart", "airline", "hotel", "check-in", "check in",
        "booking", "reservation", "itinerary", "trip", "航班", "酒店", "フライト", "ホテル"
    ]

    /// The dates always come from NSDataDetector, so only dates actually written in
    /// the text are offered. Apple Intelligence, where the phone has it, only names
    /// and sorts those dates and may drop ones not worth a countdown; a small model
    /// asked to find dates itself invents some (build 24: three made-up dates next
    /// to the one real flight).
    static func find(in text: String, now: Date = Date(), calendar: Calendar = .current) async -> Result {
        let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxCharacters))
        let detected = detectDates(in: trimmed, now: now, calendar: calendar)
        if detected.isEmpty {
            return Result(dates: [], usedAI: false)
        }
        if OnDeviceAI.isAvailable,
           let reply = await OnDeviceAI.respond(instructions: labelInstructions, prompt: labelPrompt(text: trimmed, dates: detected), temperature: 0.1) {
            let labelled = parseLabels(reply, dates: detected)
            if !labelled.isEmpty {
                return Result(dates: labelled, usedAI: true)
            }
        }
        return Result(dates: detected.map { fallbackDate($0, text: trimmed) }, usedAI: false)
    }

    static let labelInstructions: String = """
    You label dates that were found in a message a person pasted. For each numbered date answer \
    one line: number|kind|name|emoji. kind is trip, event, birthday or anniversary. \
    If a date is not worth a countdown, such as a booking date, a payment or cancellation deadline \
    or a check-out day, answer number|skip instead. name is at most four words taken from the \
    message saying what happens and where or for whom, such as Flight to Osaka or Mia's wedding, \
    in the language of the message. Only use the numbers given. Write nothing else.
    """

    static func labelPrompt(text: String, dates: [DetectedDate]) -> String {
        var lines: [String] = ["Message:", text, "", "Dates:"]
        for (index, date) in dates.enumerated() {
            lines.append(String(format: "%d. %04d-%02d-%02d (\"%@\")", index, date.year, date.month, date.day, date.snippet))
        }
        return lines.joined(separator: "\n")
    }

    /// Reads the model's labels for the detected dates. The model never supplies a
    /// date: an unknown number, an unknown kind or an empty name is skipped.
    static func parseLabels(_ reply: String, dates: [DetectedDate]) -> [FoundDate] {
        var found: [FoundDate] = []
        var seen: Set<Int> = []
        for rawLine in reply.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: CharacterSet(charactersIn: " -*•\t"))
            let fields = line.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            guard fields.count >= 2,
                  let index = Int(fields[0].trimmingCharacters(in: CharacterSet(charactersIn: ". "))),
                  index >= 0, index < dates.count, !seen.contains(index) else {
                continue
            }
            seen.insert(index)
            let kind = fields[1].lowercased()
            if kind == "skip" || fields.count < 3 { continue }
            let name = String(fields[2].prefix(40))
            if name.isEmpty { continue }
            let emoji = fields.count >= 4 ? firstEmoji(fields[3]) : nil
            let date = dates[index]
            switch kind {
            case "trip":
                found.append(FoundDate(name: name, kind: .custom, emoji: emoji ?? "✈️", month: date.month, day: date.day, year: date.year, oneTime: true))
            case "event":
                found.append(FoundDate(name: name, kind: .custom, emoji: emoji ?? "🎉", month: date.month, day: date.day, year: date.year, oneTime: true))
            case "birthday":
                found.append(FoundDate(name: name, kind: .birthday, emoji: emoji ?? "🎂", month: date.month, day: date.day, year: nil, oneTime: false))
            case "anniversary":
                found.append(FoundDate(name: name, kind: .anniversary, emoji: emoji ?? "💍", month: date.month, day: date.day, year: nil, oneTime: false))
            default:
                continue
            }
        }
        return found
    }

    /// Future dates written in the text, earliest mention first, each day once.
    static func detectDates(in text: String, now: Date, calendar: Calendar) -> [DetectedDate] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else {
            return []
        }
        let todayStart = calendar.startOfDay(for: now)
        var found: [DetectedDate] = []
        var seenDays: Set<String> = []
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        for match in detector.matches(in: text, options: [], range: range) {
            guard let date = match.date, date >= todayStart else { continue }
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            guard let year = parts.year, let month = parts.month, let day = parts.day else { continue }
            let key = "\(year)-\(month)-\(day)"
            if seenDays.contains(key) { continue }
            seenDays.insert(key)
            let snippet = Range(match.range, in: text).map { String(text[$0]) } ?? ""
            found.append(DetectedDate(month: month, day: day, year: year, snippet: snippet))
            if found.count >= maxResults { break }
        }
        return found
    }

    /// Without the model: a trip when the text reads like a booking, named after
    /// its destination when one follows "to"; otherwise an event named after the
    /// text's first short line.
    static func fallbackDate(_ date: DetectedDate, text: String) -> FoundDate {
        let lower = text.lowercased()
        let isTrip = tripWords.contains { lower.contains($0) }
        let name = isTrip ? tripName(text) : fallbackName(text)
        return FoundDate(name: name, kind: .custom, emoji: isTrip ? "✈️" : "🎉",
                         month: date.month, day: date.day, year: date.year, oneTime: true)
    }

    private static func tripName(_ text: String) -> String {
        let pattern = "\\bto\\s+([A-Z][\\p{L}-]+(?:\\s[A-Z][\\p{L}-]+)?)"
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
           let range = Range(match.range(at: 1), in: text) {
            return "Trip to " + text[range]
        }
        return "Trip"
    }

    /// The first short line of the text, which is usually a subject or a title.
    private static func fallbackName(_ text: String) -> String {
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty && trimmed.count <= 40 {
                return trimmed
            }
        }
        return "New date"
    }

    private static func firstEmoji(_ text: String) -> String? {
        guard let first = text.first,
              let scalar = first.unicodeScalars.first,
              scalar.properties.isEmoji, scalar.value > 0x238C else {
            return nil
        }
        return String(first)
    }

    /// On-device text recognition for screenshots, in any language Vision detects.
    static func recognizeText(in image: UIImage) async -> String {
        let upright = PhotoSizing.downscaled(image, maxSide: 2400)
        guard let cgImage = upright.cgImage else { return "" }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.automaticallyDetectsLanguage = true
                let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(returning: "")
                    return
                }
                let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines.joined(separator: "\n"))
            }
        }
    }
}
