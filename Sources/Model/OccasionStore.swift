import Foundation
import Combine

private struct StoreFile: Codable {
    var version: Int
    var occasions: [Occasion]
}

@MainActor
final class OccasionStore: ObservableObject {
    static let freeLimit: Int = 3

    @Published private(set) var occasions: [Occasion] = []
    let fileURL: URL
    private let defaults: UserDefaults

    init(
        directory: URL? = nil,
        seed: [Occasion]? = nil,
        seedSamplesIfNew: Bool = false,
        defaults: UserDefaults = UserDefaults.standard
    ) {
        let baseDirectory = directory ?? OccasionStore.defaultDirectory()
        try? FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        self.fileURL = baseDirectory.appendingPathComponent("occasions.json", isDirectory: false)
        self.defaults = defaults
        if let seed = seed {
            self.occasions = seed
            save()
            return
        }
        self.occasions = OccasionStore.load(from: fileURL)
        // Seed the examples once, on a genuinely new install. The flag means deleting
        // them all does not bring them back on the next launch.
        if seedSamplesIfNew && occasions.isEmpty && !defaults.bool(forKey: AppDefaults.hasSeededSamplesKey) {
            occasions = SampleDates.make()
            defaults.set(true, forKey: AppDefaults.hasSeededSamplesKey)
            save()
        }
    }

    static func defaultDirectory() -> URL {
        let fileManager = FileManager.default
        if let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            return support.appendingPathComponent("SaveTheDate", isDirectory: true)
        }
        return fileManager.temporaryDirectory.appendingPathComponent("SaveTheDate", isDirectory: true)
    }

    /// Seeded examples are not the user's own dates, so they do not use a free slot.
    var userDateCount: Int {
        return occasions.filter { !$0.isSeededSample }.count
    }

    func canAddMore(isUnlocked: Bool) -> Bool {
        return isUnlocked || userDateCount < OccasionStore.freeLimit
    }

    func remainingFreeSlots() -> Int {
        return max(0, OccasionStore.freeLimit - userDateCount)
    }

    func add(_ occasion: Occasion) {
        if let index = occasions.firstIndex(where: { $0.id == occasion.id }) {
            occasions[index] = occasion
        } else {
            occasions.append(occasion)
        }
        save()
    }

    func update(_ occasion: Occasion) {
        guard let index = occasions.firstIndex(where: { $0.id == occasion.id }) else {
            return
        }
        occasions[index] = occasion
        save()
    }

    func delete(id: UUID) {
        occasions.removeAll { $0.id == id }
        save()
    }

    func occasion(withID id: UUID) -> Occasion? {
        return occasions.first { $0.id == id }
    }

    func contains(contactIdentifier: String) -> Bool {
        return occasions.contains { $0.contactIdentifier == contactIdentifier }
    }

    func sorted(today: Date = Date(), calendar: Calendar = .current) -> [Occasion] {
        return occasions.sorted { a, b in
            let daysA = OccasionMath.daysUntil(a, from: today, calendar: calendar)
            let daysB = OccasionMath.daysUntil(b, from: today, calendar: calendar)
            if daysA != daysB {
                return daysA < daysB
            }
            return a.name.lowercased() < b.name.lowercased()
        }
    }

    private static func load(from url: URL) -> [Occasion] {
        guard let data = try? Data(contentsOf: url) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let file = try? decoder.decode(StoreFile.self, from: data) else {
            return []
        }
        return file.occasions
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let file = StoreFile(version: 1, occasions: occasions)
        guard let data = try? encoder.encode(file) else {
            return
        }
        try? data.write(to: fileURL, options: .atomic)
    }
}
