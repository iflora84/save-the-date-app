import SwiftUI
import UIKit

struct OccasionDetailView: View {
    let occasionID: UUID
    @EnvironmentObject private var store: OccasionStore
    @EnvironmentObject private var scheduler: NotificationScheduler
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var showEditor: Bool = false
    @State private var showDeleteConfirm: Bool = false
    @State private var confettiTrigger: Int = 0
    @State private var viewedPhoto: ViewedPhoto? = nil

    init(occasionID: UUID) {
        self.occasionID = occasionID
    }

    var body: some View {
        if let occasion = store.occasion(withID: occasionID) {
            content(occasion)
        } else {
            ContentUnavailableView("This date is gone", systemImage: "calendar.badge.minus")
        }
    }

    private func content(_ occasion: Occasion) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                OccasionCardView(occasion: occasion, today: Date(), style: .hero, onPhotoTap: { openPhoto(occasion) })
                remindersCard(occasion)
                if !occasion.note.isEmpty {
                    noteCard(occasion)
                }
                if !scheduler.isAuthorized && !DemoMode.isActive {
                    notificationsHint
                }
                deleteButton
            }
            .padding(16)
        }
        .background(Theme.screenBackground)
        .navigationTitle(occasion.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showEditor = true }
            }
        }
        .sheet(isPresented: $showEditor) {
            OccasionEditorView(
                editing: occasion,
                defaultReminderHour: occasion.reminderHour,
                defaultReminderMinute: occasion.reminderMinute,
                onSave: { updated in store.update(updated) }
            )
        }
        .confirmationDialog("Delete \(occasion.name)?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                store.delete(id: occasion.id)
                dismiss()
            }
        }
        .confetti(trigger: confettiTrigger)
        .fullScreenCover(item: $viewedPhoto) { photo in
            PhotoViewer(image: photo.image)
        }
        .onAppear {
            if OccasionMath.daysUntil(occasion, from: Date(), calendar: .current) == 0 {
                Task {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    confettiTrigger += 1
                }
            }
        }
    }

    /// The same plan the scheduler hands to iOS, so the dates shown here are the
    /// dates the reminders actually arrive.
    private func remindersCard(_ occasion: Occasion) -> some View {
        let upcoming = ReminderPlan.notifications(for: occasion, now: Date(), calendar: .current)
        let willArrive = scheduler.isAuthorized || DemoMode.isActive
        return VStack(alignment: .leading, spacing: 12) {
            Text("Next reminders")
                .font(Theme.display(20, weight: .semibold))
            if upcoming.isEmpty {
                Text(emptyRemindersText(occasion))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(upcoming, id: \.identifier) { item in
                    HStack(spacing: 12) {
                        Image(systemName: willArrive ? "bell.fill" : "bell.slash")
                            .foregroundStyle(willArrive ? Theme.accent : Color.secondary)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(fireText(item.fireDate))
                            Text(OccasionMath.offsetLabel(item.offset))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    private func openPhoto(_ occasion: Occasion) {
        guard let url = store.fullPhotoURL(for: occasion), let image = UIImage(contentsOfFile: url.path) else {
            return
        }
        viewedPhoto = ViewedPhoto(image: image)
    }

    private func emptyRemindersText(_ occasion: Occasion) -> String {
        if OccasionMath.daysUntil(occasion, from: Date(), calendar: .current) < 0 {
            return "This date has passed."
        }
        return "No reminders — tap Edit to add some"
    }

    private func fireText(_ date: Date) -> String {
        var style = Date.FormatStyle.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()
        if !Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year) {
            style = style.year()
        }
        return date.formatted(style)
    }

    private func noteCard(_ occasion: Occasion) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Note")
                .font(Theme.display(20, weight: .semibold))
            Text(occasion.note)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    @ViewBuilder private var notificationsHint: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Notifications are off, so reminders will not arrive.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if scheduler.isDenied {
                Button("Open iOS Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
                .buttonStyle(PillButtonStyle(.secondary))
            } else {
                Button("Turn on") {
                    Task {
                        let ok = await scheduler.requestPermission()
                        if ok { await scheduler.reschedule(store.occasions) }
                    }
                }
                .buttonStyle(PillButtonStyle(.primary))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    private var deleteButton: some View {
        Button("Delete this date", role: .destructive) {
            showDeleteConfirm = true
        }
        .buttonStyle(PillButtonStyle(.destructive))
    }
}

private struct ViewedPhoto: Identifiable {
    let id: UUID = UUID()
    let image: UIImage
}
