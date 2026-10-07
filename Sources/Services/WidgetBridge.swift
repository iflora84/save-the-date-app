import Foundation
import UIKit
import WidgetKit

/// Keeps the widgets' snapshot (Shared/WidgetSnapshot.swift) in step with the dates.
enum WidgetBridge {
    static let maxItems: Int = 8
    private static let thumbnailSide: CGFloat = 240

    /// The next dates, soonest first, with the occurrence days the widget needs to
    /// count down on its own. Past one-time dates are left out, and so is a cycle
    /// set to discreet: a Home or Lock Screen saying "2 days late" gives it away.
    static func makeSnapshot(from occasions: [Occasion], today: Date, calendar: Calendar,
                             photoFiles: [UUID: String] = [:]) -> WidgetSnapshot {
        let upcoming = occasions
            .filter { !OccasionMath.isPast($0, from: today, calendar: calendar) }
            .filter { !($0.kind == .cycle && ($0.cycle?.discreet ?? true)) }
            .sorted { OccasionMath.listDays($0, from: today, calendar: calendar) < OccasionMath.listDays($1, from: today, calendar: calendar) }
            .prefix(maxItems)
        let items = upcoming.map { occasion -> WidgetSnapshot.Item in
            return WidgetSnapshot.Item(
                id: occasion.id,
                name: occasion.name,
                emoji: occasion.displayEmoji,
                occurrences: occurrences(of: occasion, today: today, calendar: calendar),
                gradient: Theme.hexes(occasion.palette).map { UInt32($0) },
                photoFile: photoFiles[occasion.id],
                isCycle: occasion.isCycle
            )
        }
        return WidgetSnapshot(items: Array(items))
    }

    static func occurrences(of occasion: Occasion, today: Date, calendar: Calendar) -> [Date] {
        let first = calendar.startOfDay(for: OccasionMath.nextOccurrence(of: occasion, from: today, calendar: calendar))
        if occasion.isOneTime || occasion.isCycle {
            return [first]
        }
        guard let dayAfter = calendar.date(byAdding: .day, value: 1, to: first) else { return [first] }
        let second = calendar.startOfDay(for: OccasionMath.nextOccurrence(of: occasion, from: dayAfter, calendar: calendar))
        return [first, second]
    }

    /// Writes the snapshot and thumbnails, then asks WidgetKit to redraw.
    @MainActor
    static func publish(_ occasions: [Occasion], store: OccasionStore, now: Date = Date()) {
        guard let directory = WidgetSnapshot.directory else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let calendar = Calendar.current
        let first = makeSnapshot(from: occasions, today: now, calendar: calendar)

        var photoFiles: [UUID: String] = [:]
        for item in first.items {
            guard let occasion = occasions.first(where: { $0.id == item.id }),
                  let source = occasion.photoFileName,
                  let url = store.photoURL(for: occasion) else { continue }
            // Named after the photo file, which changes on every save, so an
            // existing thumbnail is never stale.
            let name = "thumb-" + source
            let target = directory.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: target.path) {
                guard let image = UIImage(contentsOfFile: url.path),
                      let data = PhotoSizing.downscaled(image, maxSide: thumbnailSide).jpegData(compressionQuality: 0.8) else { continue }
                try? data.write(to: target, options: .atomic)
            }
            photoFiles[occasion.id] = name
        }
        removeUnusedThumbnails(in: directory, keeping: Set(photoFiles.values))

        let snapshot = makeSnapshot(from: occasions, today: now, calendar: calendar, photoFiles: photoFiles)
        if snapshot.save(to: directory) {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private static func removeUnusedThumbnails(in directory: URL, keeping: Set<String>) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names where name.hasPrefix("thumb-") && !keeping.contains(name) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }
}
