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

    /// The on-device model's window is small (about 4K tokens, and CJK text costs
    /// roughly a token per character), so long emails are cut.
    static let maxCharacters: Int = 2000
    private static let maxResults: Int = 5
    private static let tripWords: [String] = [
        "flight", "boarding", "depart", "airline", "hotel", "check-in", "check in",
        "booking", "reservation", "itinerary", "trip", "航班", "酒店", "フライト", "ホテル"
    ]

    /// Apple Intelligence first where the phone has it; otherwise, or when it finds
    /// nothing, the system's own date detection.
    static func find(in text: String, now: Date = Date(), calendar: Calendar = .current) async -> Result {
        let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxCharacters))
        if trimmed.isEmpty {
            return Result(dates: [], usedAI: false)
        }
        if OnDeviceAI.isAvailable,
           let reply = await OnDeviceAI.respond(instructions: instructions(today: now, calendar: calendar), prompt: trimmed) {
            let parsed = parse(reply)
            if !parsed.isEmpty {
                return Result(dates: Array(parsed.prefix(maxResults)), usedAI: true)
            }
        }
        return Result(dates: detectDates(in: trimmed, now: now, calendar: calendar), usedAI: false)
    }

    static func instructions(today: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: today)
        let todayText = String(format: "%04d-%02d-%02d", parts.year ?? 2026, parts.month ?? 1, parts.day ?? 1)
        return """
        You find dates worth a countdown in text a person pasted: trips, flights and hotel stays, \
        events such as weddings, concerts and graduations, and birthdays or anniversaries. \
        Today is \(todayText); resolve dates without a year to the next one after today. \
        For a trip use the start date. Ignore payment deadlines, order numbers and times of day. \
        Answer only with lines in the form kind|name|YYYY-MM-DD|emoji where kind is one of \
        trip, event, birthday, anniversary and name is a short title of at most four words \
        in the language of the text. Write nothing else.
        """
    }

    /// Reads the model's lines; anything malformed is skipped.
    static func parse(_ reply: String) -> [FoundDate] {
        var found: [FoundDate] = []
        var seen: Set<String> = []
        for rawLine in reply.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: CharacterSet(charactersIn: " -*•\t"))
            let fields = line.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            guard fields.count >= 3 else { continue }
            let dateParts = fields[2].components(separatedBy: "-").compactMap { Int($0) }
            guard dateParts.count == 3,
                  dateParts[0] >= 1900, dateParts[0] <= 2200,
                  OccasionMath.isValid(month: dateParts[1], day: dateParts[2]) else {
                continue
            }
            let name = String(fields[1].prefix(40))
            if name.isEmpty { continue }
            let emoji = fields.count >= 4 ? firstEmoji(fields[3]) : nil
            let made: FoundDate
            switch fields[0].lowercased() {
            case "trip":
                made = FoundDate(name: name, kind: .custom, emoji: emoji ?? "✈️", month: dateParts[1], day: dateParts[2], year: dateParts[0], oneTime: true)
            case "event":
                made = FoundDate(name: name, kind: .custom, emoji: emoji ?? "🎉", month: dateParts[1], day: dateParts[2], year: dateParts[0], oneTime: true)
            case "birthday":
                made = FoundDate(name: name, kind: .birthday, emoji: emoji ?? "🎂", month: dateParts[1], day: dateParts[2], year: nil, oneTime: false)
            case "anniversary":
                made = FoundDate(name: name, kind: .anniversary, emoji: emoji ?? "💍", month: dateParts[1], day: dateParts[2], year: nil, oneTime: false)
            default:
                continue
            }
            let key = "\(made.name.lowercased())|\(made.month)|\(made.day)"
            if seen.contains(key) { continue }
            seen.insert(key)
            found.append(made)
        }
        return found
    }

    /// No model: NSDataDetector finds the dates, and the text's own words decide
    /// between a trip and a plain event.
    static func detectDates(in text: String, now: Date, calendar: Calendar) -> [FoundDate] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else {
            return []
        }
        let lower = text.lowercased()
        let isTrip = tripWords.contains { lower.contains($0) }
        let name = isTrip ? "Trip" : fallbackName(text)
        let todayStart = calendar.startOfDay(for: now)
        var found: [FoundDate] = []
        var seenDays: Set<String> = []
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        for match in detector.matches(in: text, options: [], range: range) {
            guard let date = match.date, date >= todayStart else { continue }
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            guard let year = parts.year, let month = parts.month, let day = parts.day else { continue }
            let key = "\(year)-\(month)-\(day)"
            if seenDays.contains(key) { continue }
            seenDays.insert(key)
            found.append(FoundDate(name: name, kind: .custom, emoji: isTrip ? "✈️" : "🎉",
                                   month: month, day: day, year: year, oneTime: true))
            if found.count >= maxResults { break }
        }
        return found
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
