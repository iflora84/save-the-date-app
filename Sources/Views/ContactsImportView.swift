import SwiftUI
import UIKit

struct ContactsImportView: View {
    let onImported: (Int) -> Void
    @EnvironmentObject private var store: OccasionStore
    @EnvironmentObject private var purchases: PurchaseManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage(AppDefaults.reminderHourKey) private var defaultReminderHour: Int = AppDefaults.defaultReminderHour
    @AppStorage(AppDefaults.reminderMinuteKey) private var defaultReminderMinute: Int = AppDefaults.defaultReminderMinute

    private let importer: ContactsImporter = ContactsImporter()
    @State private var phase: Phase = .idle
    @State private var candidates: [ImportCandidate] = []
    @State private var selected: Set<String> = []
    @State private var chosen: [ImportCandidate] = []
    @State private var showPaywall: Bool = false
    @State private var skippedMessage: String? = nil

    enum Phase: Equatable {
        case idle
        case requesting
        case loading
        case denied
        case loaded
        case failed(String)
    }

    init(onImported: @escaping (Int) -> Void) {
        self.onImported = onImported
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Import from Contacts")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Menu {
                            Button("Select all") { selectAll() }
                            Button("Clear") { selected = [] }
                        } label: {
                            Image(systemName: "checklist")
                        }
                        .disabled(phase != .loaded || candidates.isEmpty)
                        Button(importTitle) { importSelected() }
                            .disabled(selected.isEmpty)
                    }
                }
                .task { await load() }
                .sheet(isPresented: $showPaywall, onDismiss: { paywallDismissed() }) {
                    PaywallView()
                }
        }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .idle, .requesting, .loading:
            ProgressView("Looking for birthdays and anniversaries…")
        case .denied:
            deniedView
        case .failed(let message):
            Text(message)
                .padding(24)
        case .loaded:
            if candidates.isEmpty {
                ContentUnavailableView(
                    "No dates found",
                    systemImage: "person.crop.circle.badge.questionmark",
                    description: Text("None of your contacts have a birthday or anniversary set.")
                )
            } else {
                candidateList
            }
        }
    }

    private var deniedView: some View {
        VStack(spacing: 12) {
            Text("Contacts access is off")
                .font(Theme.font(22, weight: .heavy))
            Text("Allow it in Settings to import birthdays and anniversaries.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            .buttonStyle(PillButtonStyle(.primary))
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var candidateList: some View {
        List {
            if !purchases.isUnlocked {
                freeHeaderRow
            }
            ForEach(candidates) { candidate in
                row(candidate)
            }
        }
    }

    @ViewBuilder private var freeHeaderRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(freeHeaderText)
                .font(.footnote)
                .foregroundStyle(.secondary)
            skippedBanner
            Button("Unlock unlimited") {
                chosen = []
                showPaywall = true
            }
            .font(.footnote)
            .buttonStyle(.borderless)
        }
    }

    private var freeHeaderText: String {
        let remaining = store.remainingFreeSlots()
        let noun = remaining == 1 ? "date" : "dates"
        return "Free plan: \(remaining) more \(noun) — unlock for all"
    }

    @ViewBuilder private var skippedBanner: some View {
        if let message = skippedMessage {
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var importTitle: String {
        if selected.isEmpty { return "Import" }
        return "Import \(selected.count)"
    }

    private func row(_ candidate: ImportCandidate) -> some View {
        let alreadySaved = isAlreadySaved(candidate)
        let isSelected = selected.contains(candidate.id)
        let dateLine = OccasionMath.dateText(month: candidate.month, day: candidate.day, year: candidate.year, calendar: .current)
        let subtitle = "\(candidate.kind.defaultEmoji) \(candidate.kind.label) · \(dateLine)"
        return Button {
            toggle(candidate.id)
        } label: {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                VStack(alignment: .leading) {
                    Text(candidate.name)
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if alreadySaved {
                    Text("Already saved")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(alreadySaved)
    }

    private func isAlreadySaved(_ candidate: ImportCandidate) -> Bool {
        if store.contains(contactIdentifier: candidate.id) { return true }
        let candidateName = candidate.name.lowercased()
        return store.occasions.contains { occasion in
            return occasion.name.lowercased() == candidateName
                && occasion.month == candidate.month
                && occasion.day == candidate.day
        }
    }

    private func toggle(_ id: String) {
        if selected.contains(id) {
            selected.remove(id)
        } else {
            selected.insert(id)
        }
    }

    private func selectAll() {
        let available = candidates.filter { !isAlreadySaved($0) }
        selected = Set(available.map { $0.id })
    }

    private func load() async {
        switch ContactsImporter.accessState() {
        case .notDetermined:
            phase = .requesting
            let granted = (try? await importer.requestAccess()) ?? false
            if granted {
                await fetch()
            } else {
                phase = .denied
            }
        case .denied:
            phase = .denied
        case .authorized:
            await fetch()
        }
    }

    private func fetch() async {
        phase = .loading
        do {
            candidates = try await importer.fetchCandidates()
            phase = .loaded
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func importBatch(_ items: [ImportCandidate]) -> Int {
        var added = 0
        for candidate in items {
            if store.contains(contactIdentifier: candidate.id) { continue }
            if !store.canAddMore(isUnlocked: purchases.isUnlocked) { break }
            let occasion = candidate.makeOccasion(
                palette: OccasionPalette.forIndex(store.occasions.count),
                reminderHour: defaultReminderHour,
                reminderMinute: defaultReminderMinute
            )
            store.add(occasion)
            added += 1
        }
        return added
    }

    private func importSelected() {
        chosen = candidates.filter { selected.contains($0.id) }
        let added = importBatch(chosen)
        if added > 0 { onImported(added) }
        if added < chosen.count {
            showPaywall = true
        } else {
            dismiss()
        }
    }

    private func paywallDismissed() {
        if chosen.isEmpty { return }
        if purchases.isUnlocked {
            let remaining = chosen.filter { !store.contains(contactIdentifier: $0.id) }
            let added = importBatch(remaining)
            if added > 0 { onImported(added) }
            chosen = []
            dismiss()
        } else {
            let saved = chosen.filter { store.contains(contactIdentifier: $0.id) }.count
            skippedMessage = "Saved \(saved) of \(chosen.count). Unlock to import the rest."
            selected = []
            chosen = []
        }
    }
}
