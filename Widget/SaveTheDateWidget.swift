import WidgetKit
import SwiftUI
import UIKit

@main
struct SaveTheDateWidgetBundle: WidgetBundle {
    var body: some Widget {
        CountdownWidget()
    }
}

struct CountdownWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CountdownWidget", provider: CountdownProvider()) { entry in
            CountdownWidgetView(entry: entry)
        }
        .configurationDisplayName("Countdown")
        .description("Your next dates and how many days are left.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct CountdownEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

/// One entry per midnight for a week, so the counts tick over even when the app
/// is never opened; the app asks for a reload whenever the dates change.
struct CountdownProvider: TimelineProvider {
    func placeholder(in context: Context) -> CountdownEntry {
        return CountdownEntry(date: Date(), snapshot: WidgetSnapshot.preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (CountdownEntry) -> Void) {
        let snapshot = loadSnapshot() ?? (context.isPreview ? WidgetSnapshot.preview : nil)
        completion(CountdownEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CountdownEntry>) -> Void) {
        let snapshot = loadSnapshot()
        let calendar = Calendar.current
        let midnight = calendar.startOfDay(for: Date())
        var entries: [CountdownEntry] = [CountdownEntry(date: Date(), snapshot: snapshot)]
        for offset in 1...7 {
            if let day = calendar.date(byAdding: .day, value: offset, to: midnight) {
                entries.append(CountdownEntry(date: day, snapshot: snapshot))
            }
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func loadSnapshot() -> WidgetSnapshot? {
        guard let directory = WidgetSnapshot.directory else { return nil }
        return WidgetSnapshot.load(from: directory)
    }
}

struct CountdownWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CountdownEntry

    private var items: [WidgetSnapshot.Item] {
        return entry.snapshot?.upcoming(on: entry.date, calendar: .current) ?? []
    }

    var body: some View {
        switch family {
        case .systemMedium:
            MediumCountdown(items: Array(items.prefix(4)), day: entry.date)
        case .accessoryCircular:
            CircularCountdown(item: items.first, day: entry.date)
        case .accessoryRectangular:
            RectangularCountdown(item: items.first, day: entry.date)
        case .accessoryInline:
            InlineCountdown(item: items.first, day: entry.date)
        default:
            SmallCountdown(item: items.first, day: entry.date)
        }
    }
}

// MARK: - Shared pieces

private enum Look {
    static func color(_ hex: UInt32) -> Color {
        return Color(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0
        )
    }

    static func gradient(_ item: WidgetSnapshot.Item?) -> LinearGradient {
        let hexes = item?.gradient ?? [0x5A2A47, 0x87455F]
        return LinearGradient(colors: hexes.map { color($0) }, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static func display(_ size: CGFloat) -> Font {
        return Font.system(size: size, weight: .regular, design: .serif)
    }

    static func days(_ item: WidgetSnapshot.Item, from day: Date) -> Int {
        return item.daysUntil(from: day, calendar: .current) ?? 0
    }

    /// "Today", "1 day", "12 days", or "2 days late" for a late cycle.
    static func phrase(_ days: Int) -> String {
        if days == 0 { return "Today" }
        if days < 0 { return "\(-days) \(days == -1 ? "day" : "days") late" }
        return "\(days) \(days == 1 ? "day" : "days")"
    }

    static func photo(_ item: WidgetSnapshot.Item) -> UIImage? {
        guard let name = item.photoFile, let directory = WidgetSnapshot.directory else { return nil }
        return UIImage(contentsOfFile: directory.appendingPathComponent(name).path)
    }
}

private struct Avatar: View {
    let item: WidgetSnapshot.Item
    let size: CGFloat

    var body: some View {
        ZStack {
            if let image = Look.photo(item) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(item.emoji)
                    .font(.system(size: size * 0.6))
            }
        }
        .frame(width: size, height: size)
        .background(Color.white.opacity(0.22), in: Circle())
        .clipShape(Circle())
    }
}

private struct EmptyCountdown: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("🎂")
                .font(.system(size: 30))
            Text("Add a date in Save the Date")
                .font(Look.display(16))
                .foregroundStyle(Color.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Home Screen

private struct SmallCountdown: View {
    let item: WidgetSnapshot.Item?
    let day: Date

    var body: some View {
        SmallContent(item: item, day: day)
            .containerBackground(for: .widget) {
                Look.gradient(item)
            }
    }
}

/// The small widget's face without its background, so Medium can reuse it.
private struct SmallContent: View {
    let item: WidgetSnapshot.Item?
    let day: Date

    var body: some View {
        if let item {
            let days = Look.days(item, from: day)
            VStack(alignment: .leading, spacing: 2) {
                Avatar(item: item, size: 40)
                Spacer(minLength: 4)
                Text(item.name)
                    .font(Look.display(16))
                    .lineLimit(1)
                if days == 0 {
                    Text("Today")
                        .font(Look.display(34))
                } else {
                    Text(String(abs(days)))
                        .font(Look.display(44))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text(days < 0 ? "days late" : (days == 1 ? "day" : "days"))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .opacity(0.85)
                }
            }
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            EmptyCountdown()
        }
    }
}

private struct MediumCountdown: View {
    let items: [WidgetSnapshot.Item]
    let day: Date

    var body: some View {
        HStack(spacing: 14) {
            if let first = items.first {
                SmallContent(item: first, day: day)
                    .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(items.dropFirst()) { item in
                        HStack(spacing: 8) {
                            Avatar(item: item, size: 26)
                            Text(item.name)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text(Look.phrase(Look.days(item, from: day)))
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .opacity(0.9)
                        }
                    }
                }
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                EmptyCountdown()
            }
        }
        .containerBackground(for: .widget) {
            Look.gradient(items.first)
        }
    }
}

// MARK: - Lock Screen

private struct CircularCountdown: View {
    let item: WidgetSnapshot.Item?
    let day: Date

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let item {
                let days = Look.days(item, from: day)
                VStack(spacing: 0) {
                    Text(item.emoji)
                        .font(.system(size: 12))
                    Text(days == 0 ? "🎉" : String(abs(days)))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.6)
                }
            } else {
                Text("🎂")
            }
        }
        .containerBackground(for: .widget) {
            Color.clear
        }
    }
}

private struct RectangularCountdown: View {
    let item: WidgetSnapshot.Item?
    let day: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let item {
                Text("\(item.emoji) \(item.name)")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Text(Look.phrase(Look.days(item, from: day)))
                    .font(.system(size: 22, weight: .bold, design: .serif))
                    .widgetAccentable()
            } else {
                Text("Save the Date")
                    .font(.headline)
                Text("Add a date")
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(for: .widget) {
            Color.clear
        }
    }
}

private struct InlineCountdown: View {
    let item: WidgetSnapshot.Item?
    let day: Date

    var body: some View {
        Group {
            if let item {
                let days = Look.days(item, from: day)
                Text(days == 0 ? "\(item.emoji) \(item.name) today" : "\(item.emoji) \(item.name) · \(Look.phrase(days))")
            } else {
                Text("Save the Date")
            }
        }
        .containerBackground(for: .widget) {
            Color.clear
        }
    }
}

extension WidgetSnapshot {
    /// Shown in the widget gallery before the app has written anything.
    static var preview: WidgetSnapshot {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        func inDays(_ n: Int) -> Date {
            return calendar.date(byAdding: .day, value: n, to: today) ?? today
        }
        return WidgetSnapshot(items: [
            Item(id: UUID(), name: "Mum", emoji: "🎂", occurrences: [inDays(10)], gradient: [0x8A3F30, 0x9E5C3C], photoFile: nil, isCycle: false),
            Item(id: UUID(), name: "Alex & Sam", emoji: "💍", occurrences: [inDays(12)], gradient: [0x5A2A47, 0x87455F], photoFile: nil, isCycle: false),
            Item(id: UUID(), name: "Kyoto trip", emoji: "✈️", occurrences: [inDays(24)], gradient: [0x1C4A58, 0x2F7480], photoFile: nil, isCycle: false),
            Item(id: UUID(), name: "Dad", emoji: "🎂", occurrences: [inDays(45)], gradient: [0x42325A, 0x6B5486], photoFile: nil, isCycle: false)
        ])
    }
}
