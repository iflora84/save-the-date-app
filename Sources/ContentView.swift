import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: OccasionStore
    @EnvironmentObject private var scheduler: NotificationScheduler
    @EnvironmentObject private var purchases: PurchaseManager
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        root
            .fontDesign(.rounded)
            .tint(Theme.accent)
            .task {
                if !DemoMode.isActive {
                    await purchases.start()
                }
            }
            .onChange(of: store.occasions, initial: true) { _, occasions in
                if !DemoMode.isActive {
                    Task { await scheduler.reschedule(occasions) }
                }
            }
            .onChange(of: scenePhase, initial: true) { _, phase in
                if phase == .active && !DemoMode.isActive {
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
