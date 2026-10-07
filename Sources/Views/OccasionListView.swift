import SwiftUI
import UIKit

enum ListSheet: String, Identifiable {
    case editor, settings, importContacts, importCalendar, paywall
    var id: String { return rawValue }
}

struct OccasionListView: View {
    @EnvironmentObject private var store: OccasionStore
    @EnvironmentObject private var scheduler: NotificationScheduler
    @EnvironmentObject private var purchases: PurchaseManager
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @AppStorage(AppDefaults.reminderHourKey) private var defaultReminderHour: Int = AppDefaults.defaultReminderHour
    @AppStorage(AppDefaults.reminderMinuteKey) private var defaultReminderMinute: Int = AppDefaults.defaultReminderMinute
    @AppStorage(AppDefaults.keepsSamplesKey) private var keepsSamples: Bool = false
    @ObservedObject private var tapRouter: NotificationTapRouter = NotificationTapRouter.shared

    @State private var path: [UUID] = []
    @State private var activeSheet: ListSheet? = nil
    @State private var pendingAdd: Bool = false
    @State private var pendingDelete: Occasion? = nil
    @State private var today: Date = Date()
    @State private var confettiTrigger: Int = 0
    @State private var didCelebrateToday: Bool = false

    init() {}

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if store.occasions.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .background(Theme.screenBackground)
            .navigationTitle("Save the Date")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                // The list draws its own serif header, so the bar shows no title.
                ToolbarItem(placement: .principal) {
                    Text("")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        activeSheet = .settings
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        addTapped()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Theme.onAccent)
                            .frame(width: 32, height: 32)
                            .background(Theme.accentFill, in: Circle())
                    }
                    .accessibilityLabel("Add a date")
                }
            }
            .navigationDestination(for: UUID.self) { id in
                OccasionDetailView(occasionID: id)
            }
            .sheet(item: $activeSheet, onDismiss: { sheetDismissed() }) { sheet in
                sheetContent(sheet)
            }
            .confirmationDialog(deleteTitle, isPresented: deleteDialogBinding, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { confirmDelete() }
            }
            .confetti(trigger: confettiTrigger)
            .onAppear {
                today = Date()
                celebrateIfToday()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { today = Date() }
            }
            .onChange(of: tapRouter.openedOccasionID, initial: true) { _, id in
                openTappedReminder(id)
            }
        }
    }

    private var items: [Occasion] {
        return store.sorted(today: today, calendar: .current)
    }

    private var emptyState: some View {
        EmptyOccasionsView(
            onAdd: { addTapped() },
            onImport: { activeSheet = .importContacts }
        )
    }

    private var list: some View {
        let sortedItems = items
        let upcoming = sortedItems.filter { !isPast($0) }
        let past = sortedItems.filter { isPast($0) }
        let heroID = upcoming.first?.id
        return List {
            header
            ForEach(upcoming) { occasion in
                row(occasion, isHero: occasion.id == heroID)
            }
            if store.hasSamples && store.userDateCount > 0 && !keepsSamples {
                examplesRow
            }
            if !store.occasions.isEmpty && !scheduler.isAuthorized && !DemoMode.isActive {
                notificationsRow
            }
            if !purchases.isUnlocked {
                freeSlotsRow
            }
            calendarRow
            importRow
            if !past.isEmpty {
                pastHeader
                ForEach(past) { occasion in
                    row(occasion, isHero: false)
                        .opacity(0.6)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("YOUR MOMENTS")
                .font(Theme.eyebrowFont)
                .tracking(2.4)
                .foregroundStyle(Theme.accent)
            Text("Save the Date")
                .font(Theme.display(40))
        }
        .padding(.bottom, 8)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 6, trailing: 16))
    }

    private func isPast(_ occasion: Occasion) -> Bool {
        return OccasionMath.daysUntil(occasion, from: today, calendar: .current) < 0
    }

    private var pastHeader: some View {
        Text("Past")
            .font(Theme.display(22, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 12)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 0, trailing: 16))
    }

    private func row(_ occasion: Occasion, isHero: Bool) -> some View {
        Button {
            path.append(occasion.id)
        } label: {
            OccasionCardView(occasion: occasion, today: today, style: isHero ? .hero : .compact, isNext: isHero)
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                pendingDelete = occasion
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    @ViewBuilder private var notificationsRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reminders are off")
                .font(Theme.display(20, weight: .semibold))
            Text("Turn on notifications so you never miss a day.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if scheduler.isDenied {
                Button("Open iOS Settings") { openSettings() }
                    .buttonStyle(PillButtonStyle(.secondary))
            } else {
                Button("Turn on") { requestNotificationsAndReschedule() }
                    .buttonStyle(PillButtonStyle(.primary))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
    }

    // Offered once the user has a date of their own, so the examples have done their job.
    private var examplesRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your own dates are in")
                .font(Theme.display(20, weight: .semibold))
            Text("Remove the examples so only your dates are left?")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Remove examples") {
                withAnimation(Theme.spring) { store.removeSamples() }
            }
            .buttonStyle(PillButtonStyle(.primary))
            Button("Keep them") { keepsSamples = true }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
    }

    private var freeSlotsRow: some View {
        HStack {
            Text("\(store.userDateCount) of \(OccasionStore.freeLimit) free dates used")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                activeSheet = .paywall
            } label: {
                Text("Unlock unlimited")
                    .font(Theme.font(14, weight: .semibold))
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Theme.accentFill, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
    }

    private var calendarRow: some View {
        Button {
            activeSheet = .importCalendar
        } label: {
            Label("Find dates in Calendar", systemImage: OnDeviceAI.isAvailable ? "sparkles" : "calendar.badge.plus")
        }
        .buttonStyle(PillButtonStyle(.secondary))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
    }

    private var importRow: some View {
        Button {
            activeSheet = .importContacts
        } label: {
            Label("Import from Contacts", systemImage: "person.crop.circle.badge.plus")
        }
        .buttonStyle(PillButtonStyle(.secondary))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
    }

    private var deleteTitle: String {
        return "Delete \(pendingDelete?.name ?? "this date")?"
    }

    private var deleteDialogBinding: Binding<Bool> {
        return Binding(
            get: { pendingDelete != nil },
            set: { shown in
                if !shown { pendingDelete = nil }
            }
        )
    }

    private func confirmDelete() {
        if let target = pendingDelete {
            store.delete(id: target.id)
        }
        pendingDelete = nil
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }

    private func requestNotificationsAndReschedule() {
        Task {
            let ok = await scheduler.requestPermission()
            if ok { await scheduler.reschedule(store.occasions) }
        }
    }

    // Any open sheet stays put, so a half-typed date is not thrown away. The date
    // is waiting underneath when the sheet closes.
    private func openTappedReminder(_ id: UUID?) {
        guard let id = id else { return }
        tapRouter.openedOccasionID = nil
        if store.occasion(withID: id) != nil {
            path = [id]
        }
    }

    private func addTapped() {
        if store.canAddMore(isUnlocked: purchases.isUnlocked) {
            activeSheet = .editor
        } else {
            pendingAdd = true
            activeSheet = .paywall
        }
    }

    private func sheetDismissed() {
        if pendingAdd {
            pendingAdd = false
            if purchases.isUnlocked {
                activeSheet = .editor
            }
        }
    }

    @ViewBuilder private func sheetContent(_ sheet: ListSheet) -> some View {
        switch sheet {
        case .editor:
            OccasionEditorView(
                editing: nil,
                defaultReminderHour: defaultReminderHour,
                defaultReminderMinute: defaultReminderMinute,
                onSave: { occasion in handleCreate(occasion) }
            )
        case .settings:
            SettingsView()
        case .importContacts:
            ContactsImportView(onImported: { count in
                if count > 0 {
                    fireConfetti()
                    requestNotificationsAndReschedule()
                }
            })
        case .importCalendar:
            CalendarImportView(onImported: { count in
                if count > 0 {
                    fireConfetti()
                    requestNotificationsAndReschedule()
                }
            })
        case .paywall:
            PaywallView()
        }
    }

    private func handleCreate(_ occasion: Occasion) {
        guard store.canAddMore(isUnlocked: purchases.isUnlocked) else { return }
        store.add(occasion)
        fireConfetti()
        Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            let granted = await scheduler.requestPermission()
            if granted { await scheduler.reschedule(store.occasions) }
        }
    }

    private func fireConfetti() {
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            confettiTrigger += 1
        }
    }

    private func celebrateIfToday() {
        if didCelebrateToday { return }
        let hasToday = items.contains { occasion in
            OccasionMath.daysUntil(occasion, from: today, calendar: .current) == 0
        }
        if hasToday {
            didCelebrateToday = true
            fireConfetti()
        }
    }
}

private struct EmptyOccasionsView: View {
    let onAdd: () -> Void
    let onImport: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("🎂 💍 🎉")
                .font(Theme.font(44))
            Text("Nothing saved yet")
                .font(Theme.display(32))
            Text("Birthdays, anniversaries, any day worth a countdown.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Add your first date") { onAdd() }
                .buttonStyle(PillButtonStyle(.primary))
                .padding(.top, 8)
            Button("Import from Contacts") { onImport() }
                .buttonStyle(PillButtonStyle(.secondary))
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct OccasionCardView: View {
    enum Style { case hero, compact }

    let occasion: Occasion
    let today: Date
    let calendar: Calendar
    let style: Style

    /// Only the first upcoming date on the list is "next"; Detail shows any date as a hero.
    let isNext: Bool

    init(occasion: Occasion, today: Date, calendar: Calendar = .current, style: Style, isNext: Bool = false) {
        self.occasion = occasion
        self.today = today
        self.calendar = calendar
        self.style = style
        self.isNext = isNext
    }

    private var days: Int {
        return OccasionMath.daysUntil(occasion, from: today, calendar: calendar)
    }

    private var dateLine: String {
        let milestone = OccasionMath.milestoneText(for: occasion, today: today, calendar: calendar)
        let base = OccasionMath.dateText(of: occasion, calendar: calendar)
        return base + (milestone.map { " · " + $0 } ?? "")
    }

    var body: some View {
        GradientCard(palette: occasion.palette) {
            switch style {
            case .hero:
                heroContent
            case .compact:
                compactContent
            }
        }
        .overlay {
            if style == .hero {
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(Theme.goldLine.opacity(0.55), lineWidth: 1)
            }
        }
    }

    private var heroContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                heroArt
                VStack(alignment: .leading, spacing: 3) {
                    Text(heroEyebrow)
                        .font(Theme.eyebrowFont)
                        .tracking(2)
                        .opacity(0.85)
                    Text(occasion.name)
                        .font(Theme.display(24))
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                if occasion.isSeededSample {
                    ExampleBadge()
                }
            }
            heroCount
            Rectangle()
                .fill(Color.white.opacity(0.25))
                .frame(height: 1)
            Text(dateLine)
                .font(Theme.font(15, weight: .semibold))
                .opacity(0.9)
        }
        .shadow(color: Color.black.opacity(0.15), radius: 2, x: 0, y: 1)
    }

    private var heroEyebrow: String {
        if days == 0 { return "TODAY" }
        if days == 1 { return "TOMORROW" }
        if days < 0 { return "PAST" }
        if isNext { return "NEXT UP" }
        if occasion.isOneTime { return "ONE TIME" }
        return occasion.kind.label.uppercased()
    }

    @ViewBuilder private var heroCount: some View {
        if days == 0 {
            Text("Today")
                .font(Theme.display(60))
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Text(String(abs(days)))
                    .font(Theme.display(76))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(dayUnit)
                    .font(Theme.font(16, weight: .semibold))
                    .opacity(0.85)
            }
        }
    }

    // A thin gold ring around the portrait (or emoji), set slightly apart from it.
    private var heroArt: some View {
        OccasionAvatar(occasion: occasion, size: 60, emojiSize: 34)
            .padding(4)
            .overlay {
                Circle().stroke(Theme.goldLine, lineWidth: 1.5)
            }
    }

    private var compactContent: some View {
        HStack(spacing: 14) {
            OccasionAvatar(occasion: occasion, size: 54, emojiSize: 32)
            VStack(alignment: .leading, spacing: 3) {
                if occasion.isSeededSample {
                    ExampleBadge()
                        .padding(.bottom, 2)
                }
                Text(occasion.name)
                    .font(Theme.display(21))
                    .lineLimit(2)
                Text(dateLine)
                    .font(Theme.font(13, weight: .medium))
                    .opacity(0.85)
            }
            Spacer()
            compactTrailing
        }
        .shadow(color: Color.black.opacity(0.15), radius: 2, x: 0, y: 1)
    }

    private var dayUnit: String {
        let unit = abs(days) == 1 ? "day" : "days"
        return days < 0 ? unit + " ago" : unit
    }

    @ViewBuilder private var compactTrailing: some View {
        VStack(spacing: 0) {
            if days == 0 {
                Text("Today")
                    .font(Theme.display(22))
            } else {
                Text(String(abs(days)))
                    .font(Theme.display(30))
                Text(dayUnit.uppercased())
                    .font(Theme.font(10, weight: .semibold))
                    .tracking(1.5)
                    .opacity(0.85)
            }
        }
    }
}

/// The date's photo in a circle, or its emoji when it has none or the file is missing.
struct OccasionAvatar: View {
    let occasion: Occasion
    let size: CGFloat
    let emojiSize: CGFloat
    @EnvironmentObject private var store: OccasionStore
    @State private var image: UIImage? = nil

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(occasion.displayEmoji)
                    .font(.system(size: emojiSize))
            }
        }
        .frame(width: size, height: size)
        .background(Color.white.opacity(0.22), in: Circle())
        .clipShape(Circle())
        .task(id: occasion.photoFileName) {
            image = loadImage()
        }
    }

    private func loadImage() -> UIImage? {
        guard let url = store.photoURL(for: occasion) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
}

private struct ExampleBadge: View {
    var body: some View {
        Text("EXAMPLE")
            .font(Theme.font(10, weight: .heavy))
            .tracking(0.6)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.28), in: Capsule())
            .fixedSize()
            .accessibilityLabel("Example")
    }
}
