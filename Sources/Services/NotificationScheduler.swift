import Foundation
import Combine
import UserNotifications

@MainActor
final class NotificationScheduler: ObservableObject {
    static let maxPending: Int = 60

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private let center: UNUserNotificationCenter

    init() {
        self.center = UNUserNotificationCenter.current()
    }

    var isAuthorized: Bool {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined, .denied:
            return false
        @unknown default:
            return false
        }
    }

    var isDenied: Bool {
        return authorizationStatus == .denied
    }

    var isNotDetermined: Bool {
        return authorizationStatus == .notDetermined
    }

    var statusText: String {
        switch authorizationStatus {
        case .notDetermined:
            return "Not asked yet"
        case .denied:
            return "Off"
        case .authorized, .provisional, .ephemeral:
            return "On"
        @unknown default:
            return "Unknown"
        }
    }

    func refreshAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    @discardableResult
    func requestPermission() async -> Bool {
        if authorizationStatus == .notDetermined {
            do {
                _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            } catch {
                // Treated like a denial; the refresh below reads the real status.
            }
        }
        await refreshAuthorizationStatus()
        return isAuthorized
    }

    func reschedule(_ occasions: [Occasion], now: Date = Date(), calendar: Calendar = .current) async {
        await refreshAuthorizationStatus()
        await removePending(withPrefix: ReminderPlan.identifierPrefix)
        if !isAuthorized { return }

        var plan: [PlannedNotification] = []
        for occasion in occasions {
            plan.append(contentsOf: ReminderPlan.notifications(for: occasion, now: now, calendar: calendar, cycles: 2))
        }
        plan.sort { $0.fireDate < $1.fireDate }
        if plan.count > NotificationScheduler.maxPending {
            plan = trimmed(plan)
        }

        for item in plan {
            await add(item)
        }
    }

    func cancel(occasionID: UUID) async {
        let prefix = ReminderPlan.identifierPrefix + occasionID.uuidString + "-"
        await removePending(withPrefix: prefix)
    }

    func cancelAll() async {
        await removePending(withPrefix: ReminderPlan.identifierPrefix)
    }

    private func removePending(withPrefix prefix: String) async {
        let pending = await center.pendingNotificationRequests()
        let ids: [String] = pending.map { $0.identifier }.filter { $0.hasPrefix(prefix) }
        if ids.isEmpty { return }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    private func add(_ item: PlannedNotification) async {
        let content = UNMutableNotificationContent()
        content.title = item.title
        content.body = item.body
        content.sound = UNNotificationSound.default
        content.userInfo = ["occasionID": item.occasionID.uuidString]
        let trigger = UNCalendarNotificationTrigger(dateMatching: item.dateComponents, repeats: false)
        let request = UNNotificationRequest(identifier: item.identifier, content: content, trigger: trigger)
        do {
            try await center.add(request)
        } catch {
            // A single failed request should not stop the rest of the plan.
        }
    }

    private func trimmed(_ plan: [PlannedNotification]) -> [PlannedNotification] {
        if plan.count <= NotificationScheduler.maxPending { return plan }
        var chosen: [PlannedNotification] = []
        var seenOccasions: Set<UUID> = []
        for item in plan {
            if chosen.count >= NotificationScheduler.maxPending { break }
            if seenOccasions.contains(item.occasionID) { continue }
            seenOccasions.insert(item.occasionID)
            chosen.append(item)
        }
        let chosenIDs: Set<String> = Set(chosen.map { $0.identifier })
        for item in plan {
            if chosen.count >= NotificationScheduler.maxPending { break }
            if chosenIDs.contains(item.identifier) { continue }
            chosen.append(item)
        }
        return chosen.sorted { $0.fireDate < $1.fireDate }
    }
}

/// Receives taps on reminders. The App installs it from its init, before launch
/// finishes, so a tap that cold-launches the app still opens the right date.
@MainActor
final class NotificationTapRouter: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared: NotificationTapRouter = NotificationTapRouter()

    /// Set when a reminder is tapped. The list opens that date and clears it.
    @Published var openedOccasionID: UUID? = nil

    func install() {
        UNUserNotificationCenter.current().delegate = self
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let raw = response.notification.request.content.userInfo["occasionID"] as? String
        if let raw = raw, let id = UUID(uuidString: raw) {
            Task { @MainActor in
                self.openedOccasionID = id
            }
        }
        completionHandler()
    }

    // Once a delegate is set, iOS asks it what to do with a reminder that fires while
    // the app is open. Show it like any other.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}
