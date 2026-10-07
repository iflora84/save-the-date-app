import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject private var store: OccasionStore
    @EnvironmentObject private var scheduler: NotificationScheduler
    @EnvironmentObject private var purchases: PurchaseManager
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppAppearance.storageKey) private var appearance: String = AppAppearance.defaultChoice.rawValue

    init() {
        Theme.applyNavigationBarFonts()
    }

    var body: some View {
        root
            .fontDesign(.rounded)
            .tint(Theme.accent)
            .preferredColorScheme((AppAppearance(rawValue: appearance) ?? .defaultChoice).colorScheme)
            .task {
                if !DemoMode.isActive {
                    await purchases.start()
                }
            }
            .onChange(of: store.occasions, initial: true) { _, occasions in
                if !DemoMode.isActive {
                    Task { await scheduler.reschedule(occasions) }
                    WidgetBridge.publish(occasions, store: store)
                }
            }
            .onChange(of: scenePhase, initial: true) { _, phase in
                if phase == .active && !DemoMode.isActive {
                    // Yearly dates roll over and cycles get re-predicted; keep the widget current.
                    WidgetBridge.publish(store.occasions, store: store)
                    Task {
                        await scheduler.refreshAuthorizationStatus()
                        await scheduler.reschedule(store.occasions)
                    }
                }
            }
    }

    @ViewBuilder private var root: some View {
        switch DemoMode.screen {
        case "paywall":
            PaywallView()
        case "settings":
            SettingsView()
        case "detail":
            demoDetail
        case "editor":
            demoEditor
        case "paste":
            TextImportView(source: .paste, prefilledText: DemoMode.pastedEmail, onPick: { _ in })
        case "found":
            TextImportView(source: .paste, preset: DemoMode.foundResult(), onPick: { _ in })
        case "calendar":
            CalendarImportView(onImported: { _ in }, preset: DemoMode.calendarResult())
        case "crop":
            demoCrop
        default:
            OccasionListView()
        }
    }

    @ViewBuilder private var demoEditor: some View {
        OccasionEditorView(
            editing: nil,
            defaultReminderHour: AppDefaults.defaultReminderHour,
            defaultReminderMinute: AppDefaults.defaultReminderMinute,
            onSave: { _ in }
        )
    }

    @ViewBuilder private var demoCrop: some View {
        let url = store.photosDirectory.appendingPathComponent("couple-full.jpg", isDirectory: false)
        if let image = UIImage(contentsOfFile: url.path) {
            PhotoCropView(image: image, onDone: { _ in })
        } else {
            OccasionListView()
        }
    }

    @ViewBuilder private var demoDetail: some View {
        if let first = store.sorted().first {
            NavigationStack {
                OccasionDetailView(occasionID: first.id)
            }
        } else {
            OccasionListView()
        }
    }
}
