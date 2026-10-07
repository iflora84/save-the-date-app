import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var store: OccasionStore
    @EnvironmentObject private var scheduler: NotificationScheduler
    @EnvironmentObject private var purchases: PurchaseManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage(AppDefaults.reminderHourKey) private var defaultReminderHour: Int = AppDefaults.defaultReminderHour
    @AppStorage(AppDefaults.reminderMinuteKey) private var defaultReminderMinute: Int = AppDefaults.defaultReminderMinute
    @AppStorage(AppAppearance.storageKey) private var appearance: String = AppAppearance.defaultChoice.rawValue
    @State private var showImport: Bool = false
    @State private var showPaywall: Bool = false
    @State private var restoreMessage: String? = nil
    @State private var showRestoreAlert: Bool = false

    init() {}

    var body: some View {
        NavigationStack {
            Form {
                appearanceSection
                remindersSection
                datesSection
                unlockSection
                aboutSection
            }
            .themedFormBackground()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await scheduler.refreshAuthorizationStatus() }
            .alert("Restore purchases", isPresented: $showRestoreAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(restoreMessage ?? "")
            }
            .sheet(isPresented: $showImport) {
                ContactsImportView(onImported: { count in
                    if count > 0 {
                        Task {
                            let ok = await scheduler.requestPermission()
                            if ok { await scheduler.reschedule(store.occasions) }
                        }
                    }
                })
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
        }
    }

    private var appearanceSection: some View {
        Section {
            Picker("Theme", selection: $appearance) {
                ForEach(AppAppearance.allCases) { option in
                    Text(option.label).tag(option.rawValue)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Appearance")
        } footer: {
            Text("Auto follows your iPhone's light or dark setting.")
        }
    }

    @ViewBuilder private var remindersSection: some View {
        Section {
            LabeledContent("Notifications", value: scheduler.statusText)
            if scheduler.isNotDetermined {
                Button("Turn on notifications") {
                    Task {
                        let ok = await scheduler.requestPermission()
                        if ok { await scheduler.reschedule(store.occasions) }
                    }
                }
            }
            if scheduler.isDenied {
                Button("Open iOS Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
            }
            DatePicker("Default reminder time", selection: defaultTimeBinding, displayedComponents: .hourAndMinute)
        } header: {
            Text("Reminders")
        } footer: {
            Text("Used for new dates. Each date can override it.")
        }
    }

    private var datesSection: some View {
        Section {
            Button("Import from Contacts") { showImport = true }
            LabeledContent("Saved dates", value: String(store.occasions.count))
        } header: {
            Text("Dates")
        }
    }

    @ViewBuilder private var unlockSection: some View {
        Section {
            if purchases.isUnlocked {
                Label("Unlocked — thank you!", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Unlock unlimited dates") { showPaywall = true }
            }
            Button("Restore purchases") { restore() }
                .disabled(purchases.isBusy)
        } header: {
            Text("Save the Date Unlimited")
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: versionText)
        } header: {
            Text("About")
        }
    }

    private var versionText: String {
        let value = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        return value ?? "1.0"
    }

    private var defaultTimeBinding: Binding<Date> {
        return Binding<Date>(
            get: {
                return Calendar.current.date(bySettingHour: defaultReminderHour, minute: defaultReminderMinute, second: 0, of: Date()) ?? Date()
            },
            set: { newValue in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                defaultReminderHour = comps.hour ?? AppDefaults.defaultReminderHour
                defaultReminderMinute = comps.minute ?? AppDefaults.defaultReminderMinute
            }
        )
    }

    private func restore() {
        Task {
            let ok = await purchases.restore()
            if ok {
                restoreMessage = "Your unlock has been restored."
            } else {
                restoreMessage = purchases.lastError ?? "No previous purchase found for this Apple ID."
            }
            showRestoreAlert = true
        }
    }
}
