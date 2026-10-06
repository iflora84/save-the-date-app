import SwiftUI

@main
struct SaveTheDateApp: App {
    @StateObject private var store: OccasionStore = OccasionStore(
        seed: DemoMode.seed(),
        seedSamplesIfNew: !DemoMode.isActive
    )
    @StateObject private var scheduler: NotificationScheduler = NotificationScheduler()
    @StateObject private var purchases: PurchaseManager = PurchaseManager(
        defaults: DemoMode.purchaseDefaults(),
        fallbackPrice: DemoMode.demoPrice()
    )

    init() {
        NotificationTapRouter.shared.install()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(scheduler)
                .environmentObject(purchases)
        }
    }
}
