import Foundation
import Combine

private struct StoreFile: Codable {
    var version: Int
    var occasions: [Occasion]
}

@MainActor
final class OccasionStore: ObservableObject {
    static let freeLimit: Int = 10

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

    var hasSamples: Bool {
        return occasions.contains { $0.isSeededSample }
    }

    func canAddMore(isUnlocked: Bool) -> Bool {
        return isUnlocked || userDateCount < OccasionStore.freeLimit
    }

    func remainingFreeSlots() -> Int {
        return max(0, OccasionStore.freeLimit - userDateCount)
    }

    var photosDirectory: URL {
        return fileURL.deletingLastPathComponent().appendingPathComponent("photos", isDirectory: true)
    }

    func photoURL(for occasion: Occasion) -> URL? {
        guard let name = occasion.photoFileName else { return nil }
        return photosDirectory.appendingPathComponent(name, isDirectory: false)
    }

    /// The whole photo when there is one, otherwise the card square.
    func fullPhotoURL(for occasion: Occasion) -> URL? {
        guard let name = occasion.photoFullFileName ?? occasion.photoFileName else { return nil }
        return photosDirectory.appendingPathComponent(name, isDirectory: false)
    }

    /// Writes the image and returns the file name to put on the occasion. Each save
    /// gets a new name, so a cancelled edit never touches the photo in use.
    func savePhoto(_ jpegData: Data) -> String? {
        try? FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
        let name = UUID().uuidString + ".jpg"
        do {
            try jpegData.write(to: photosDirectory.appendingPathComponent(name, isDirectory: false), options: .atomic)
        } catch {
            return nil
        }
        return name
    }

    func add(_ occasion: Occasion) {
        if let index = occasions.firstIndex(where: { $0.id == occasion.id }) {
            removePhotoIfReplaced(occasions[index], by: occasion)
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
        removePhotoIfReplaced(occasions[index], by: occasion)
        occasions[index] = occasion
        save()
    }

    func delete(id: UUID) {
        if let gone = occasion(withID: id) {
            removePhotoFile(named: gone.photoFileName)
            removePhotoFile(named: gone.photoFullFileName)
        }
        occasions.removeAll { $0.id == id }
        save()
    }

    func removeSamples() {
        occasions.removeAll { $0.isSeededSample }
        save()
    }

    func occasion(withID id: UUID) -> Occasion? {
        return occasions.first { $0.id == id }
    }

    func contains(contactIdentifier: String) -> Bool {
        return occasions.contains { $0.contactIdentifier == contactIdentifier }
    }

    /// Upcoming dates soonest first, then one-time dates that have passed, most recent
    /// first. A late cycle counts as due today, not as past.
    func sorted(today: Date = Date(), calendar: Calendar = .current) -> [Occasion] {
        return occasions.sorted { a, b in
            let pastA = OccasionMath.isPast(a, from: today, calendar: calendar)
            let pastB = OccasionMath.isPast(b, from: today, calendar: calendar)
            if pastA != pastB {
                return !pastA
            }
            let daysA = OccasionMath.listDays(a, from: today, calendar: calendar)
            let daysB = OccasionMath.listDays(b, from: today, calendar: calendar)
            if daysA != daysB {
                return pastA ? daysA > daysB : daysA < daysB
            }
            return a.name.lowercased() < b.name.lowercased()
        }
    }

    private func removePhotoIfReplaced(_ old: Occasion, by new: Occasion) {
        if old.photoFileName != new.photoFileName {
            removePhotoFile(named: old.photoFileName)
        }
        if old.photoFullFileName != new.photoFullFileName {
            removePhotoFile(named: old.photoFullFileName)
        }
    }

    private func removePhotoFile(named name: String?) {
        guard let name = name else { return }
        try? FileManager.default.removeItem(at: photosDirectory.appendingPathComponent(name, isDirectory: false))
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
