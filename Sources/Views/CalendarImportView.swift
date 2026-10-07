import SwiftUI
import UIKit

struct CalendarImportView: View {
    let onImported: (Int) -> Void
    @EnvironmentObject private var store: OccasionStore
    @EnvironmentObject private var purchases: PurchaseManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage(AppDefaults.reminderHourKey) private var defaultReminderHour: Int = AppDefaults.defaultReminderHour
    @AppStorage(AppDefaults.reminderMinuteKey) private var defaultReminderMinute: Int = AppDefaults.defaultReminderMinute

    private let scanner: CalendarScanner = CalendarScanner()
    @State private var phase: Phase = .idle
    @State private var candidates: [CalendarCandidate] = []
    @State private var usedAI: Bool = false
    @State private var selected: Set<String> = []
    @State private var chosen: [CalendarCandidate] = []
    @State private var showPaywall: Bool = false
    @State private var skippedMessage: String? = nil

    enum Phase: Equatable {
        case idle
        case scanning
        case denied
        case loaded
    }

    /// `preset` shows a finished scan without touching EventKit (screenshot demo).
    init(onImported: @escaping (Int) -> Void, preset: CalendarScanner.Result? = nil) {
        self.onImported = onImported
        if let preset = preset {
            _candidates = State(initialValue: preset.candidates)
            _usedAI = State(initialValue: preset.usedAI)
            _selected = State(initialValue: Set(preset.candidates.map { $0.id }))
            _phase = State(initialValue: .loaded)
        }
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Find in Calendar")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
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
        case .idle, .scanning:
            ProgressView(OnDeviceAI.isAvailable ? "Reading your calendar with Apple Intelligence…" : "Reading your calendar…")
        case .denied:
            deniedView
        case .loaded:
            if candidates.isEmpty {
                ContentUnavailableView(
                    "Nothing found",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text("No birthdays, anniversaries or trips in the next 12 months of your calendar.")
                )
            } else {
                candidateList
            }
        }
    }

    private var deniedView: some View {
        VStack(spacing: 12) {
            Text("Calendar access is off")
                .font(Theme.display(24, weight: .semibold))
            Text("Allow full access in Settings to find birthdays, anniversaries and trips.")
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

    private var candidateList: some View {
        List {
            Section {
                ForEach(candidates) { candidate in
                    row(candidate)
                }
            } header: {
                Text(sourceText)
            } footer: {
                freeFooter
            }
        }
        .themedFormBackground()
    }

    // Only claims AI when the model actually answered during this scan.
    private var sourceText: String {
        if usedAI {
            return "Found with Apple Intelligence, on this iPhone"
        }
        return "Found by matching event titles"
    }

    @ViewBuilder private var freeFooter: some View {
        if !purchases.isUnlocked {
            VStack(alignment: .leading, spacing: 8) {
                Text(freeText)
                if let message = skippedMessage {
                    Text(message)
                }
                Button("Unlock unlimited") {
                    chosen = []
                    showPaywall = true
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private var freeText: String {
        let remaining = store.remainingFreeSlots()
        let noun = remaining == 1 ? "date" : "dates"
        return "Free plan: \(remaining) more \(noun) — unlock for all"
    }

    private var importTitle: String {
        if selected.isEmpty { return "Import" }
        return "Import \(selected.count)"
    }

    private func row(_ candidate: CalendarCandidate) -> some View {
        let alreadySaved = isAlreadySaved(candidate)
        let isSelected = selected.contains(candidate.id)
        let dateLine = OccasionMath.dateText(month: candidate.month, day: candidate.day, year: candidate.year, calendar: .current)
        return Button {
            toggle(candidate.id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                Text(candidate.emoji)
                    .font(.system(size: 26))
                VStack(alignment: .leading) {
                    Text(candidate.name)
                    Text("\(candidate.kindLabel) · \(dateLine)")
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

    /// Also catches a birthday already imported from Contacts under the same name.
    private func isAlreadySaved(_ candidate: CalendarCandidate) -> Bool {
        if store.contains(contactIdentifier: candidate.id) { return true }
        let name = candidate.name.lowercased()
        return store.occasions.contains { occasion in
            return occasion.name.lowercased() == name
                && occasion.month == candidate.month
                && occasion.day == candidate.day
                && (!candidate.oneTime || occasion.year == candidate.year)
        }
    }

    private func toggle(_ id: String) {
        if selected.contains(id) {
            selected.remove(id)
        } else {
            selected.insert(id)
        }
    }

    private func load() async {
        if phase != .idle { return }
        switch CalendarScanner.accessState() {
        case .notDetermined:
            phase = .scanning
            let granted = (try? await scanner.requestAccess()) ?? false
            if granted {
                await scan()
            } else {
                phase = .denied
            }
        case .denied:
            phase = .denied
        case .authorized:
            phase = .scanning
            await scan()
        }
    }

    private func scan() async {
        let result = await scanner.scan()
        candidates = result.candidates
        usedAI = result.usedAI
        selected = Set(candidates.filter { !isAlreadySaved($0) }.map { $0.id })
        phase = .loaded
    }

    private func importBatch(_ items: [CalendarCandidate]) -> Int {
        var added = 0
        for candidate in items {
            if isAlreadySaved(candidate) { continue }
            if !store.canAddMore(isUnlocked: purchases.isUnlocked) { break }
            store.add(candidate.makeOccasion(
                palette: OccasionPalette.forIndex(store.occasions.count),
                reminderHour: defaultReminderHour,
                reminderMinute: defaultReminderMinute
            ))
            added += 1
        }
        return added
    }

    private func importSelected() {
        chosen = candidates.filter { selected.contains($0.id) }
        let added = importBatch(chosen)
        if added > 0 { onImported(added) }
        // Anything chosen but still unsaved was stopped by the free limit.
        if chosen.contains(where: { !isAlreadySaved($0) }) {
            showPaywall = true
        } else {
            dismiss()
        }
    }

    private func paywallDismissed() {
        if chosen.isEmpty { return }
        if purchases.isUnlocked {
            let added = importBatch(chosen)
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
