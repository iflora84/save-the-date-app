import Foundation

/// Hands things shared with "Share > Save the Date" from the extension to the app.
/// The extension writes one file per share into the App Group container; the app
/// takes the oldest next time it opens. File names start with a millisecond
/// timestamp, so plain name order is arrival order.
enum SharedInbox {
    static let groupID: String = "group.com.iflora.savethedate"

    enum Item: Equatable {
        case text(String)
        case image(Data)
    }

    /// Nil when the App Group is missing from the build's entitlements, which
    /// happens if the group is not ticked on the App ID in the developer portal.
    static var directory: URL? {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) else {
            return nil
        }
        return container.appendingPathComponent("Inbox", isDirectory: true)
    }

    @discardableResult
    static func save(_ item: Item, in directory: URL, now: Date = Date()) -> Bool {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let stamp = String(format: "%015.0f", now.timeIntervalSince1970 * 1000)
            let base = "\(stamp)-\(UUID().uuidString)"
            switch item {
            case .text(let text):
                let data = Data(text.utf8)
                try data.write(to: directory.appendingPathComponent(base + ".txt"), options: .atomic)
            case .image(let data):
                try data.write(to: directory.appendingPathComponent(base + ".img"), options: .atomic)
            }
            return true
        } catch {
            return false
        }
    }

    /// Removes and returns the oldest item. Unreadable files are dropped so one bad
    /// share can't block the rest.
    static func takeOldest(from directory: URL) -> Item? {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names.sorted() where name.hasSuffix(".txt") || name.hasSuffix(".img") {
            let url = directory.appendingPathComponent(name)
            let data = try? Data(contentsOf: url)
            try? FileManager.default.removeItem(at: url)
            guard let data = data, !data.isEmpty else { continue }
            if name.hasSuffix(".txt") {
                if let text = String(data: data, encoding: .utf8) {
                    return .text(text)
                }
                continue
            }
            return .image(data)
        }
        return nil
    }
}
