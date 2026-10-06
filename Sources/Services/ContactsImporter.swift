import Foundation
import Contacts

struct ImportCandidate: Identifiable, Equatable, Hashable {
    let id: String
    let contactIdentifier: String
    let name: String
    let kind: OccasionKind
    let month: Int
    let day: Int
    let year: Int?

    init(contactIdentifier: String, name: String, kind: OccasionKind, month: Int, day: Int, year: Int?) {
        self.id = "\(contactIdentifier)|\(kind.rawValue)"
        self.contactIdentifier = contactIdentifier
        self.name = name
        self.kind = kind
        self.month = month
        self.day = day
        self.year = year
    }

    func makeOccasion(palette: OccasionPalette, reminderHour: Int, reminderMinute: Int) -> Occasion {
        return Occasion(
            name: name,
            kind: kind,
            emoji: kind.defaultEmoji,
            month: month,
            day: day,
            year: year,
            reminderOffsets: Occasion.defaultReminderOffsets,
            reminderHour: reminderHour,
            reminderMinute: reminderMinute,
            note: "",
            palette: palette,
            createdAt: Date(),
            contactIdentifier: id
        )
    }
}

final class ContactsImporter {
    enum AccessState: Equatable {
        case notDetermined
        case authorized
        case denied
    }

    private let store: CNContactStore

    init() {
        self.store = CNContactStore()
    }

    static func accessState() -> AccessState {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .notDetermined:
            return .notDetermined
        case .denied, .restricted:
            return .denied
        case .authorized:
            return .authorized
        default:
            return .authorized
        }
    }

    func requestAccess() async throws -> Bool {
        return try await store.requestAccess(for: .contacts)
    }

    func fetchCandidates() async throws -> [ImportCandidate] {
        let keys: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactBirthdayKey as CNKeyDescriptor,
            CNContactDatesKey as CNKeyDescriptor
        ]
        let request = CNContactFetchRequest(keysToFetch: keys)
        var results: [ImportCandidate] = []
        try store.enumerateContacts(with: request) { (contact: CNContact, stop: UnsafeMutablePointer<ObjCBool>) in
            var name = "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty {
                name = contact.organizationName.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if name.isEmpty { return }

            if let b = contact.birthday, let m = b.month, let d = b.day, OccasionMath.isValid(month: m, day: d) {
                var year: Int? = nil
                if let y = b.year, y >= 1900 { year = y }
                results.append(ImportCandidate(
                    contactIdentifier: contact.identifier,
                    name: name,
                    kind: .birthday,
                    month: m,
                    day: d,
                    year: year
                ))
            }

            var foundAnniversary = false
            for labeled in contact.dates {
                if foundAnniversary { break }
                if labeled.label != CNLabelDateAnniversary { continue }
                let comps = labeled.value as DateComponents
                guard let m = comps.month, let d = comps.day, OccasionMath.isValid(month: m, day: d) else { continue }
                var year: Int? = nil
                if let y = comps.year, y >= 1900 { year = y }
                results.append(ImportCandidate(
                    contactIdentifier: contact.identifier,
                    name: name,
                    kind: .anniversary,
                    month: m,
                    day: d,
                    year: year
                ))
                foundAnniversary = true
            }
        }
        results.sort { a, b in
            if a.name.lowercased() != b.name.lowercased() { return a.name.lowercased() < b.name.lowercased() }
            return a.kind.rawValue < b.kind.rawValue
        }
        return results
    }
}
