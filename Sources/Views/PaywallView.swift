import SwiftUI

struct PaywallView: View {
    @EnvironmentObject private var purchases: PurchaseManager
    @Environment(\.dismiss) private var dismiss
    @State private var showError: Bool = false
    @State private var isLoadingProduct: Bool = false
    @State private var restoreMessage: String? = nil
    @State private var showRestoreAlert: Bool = false
    @State private var confettiTrigger: Int = 0

    init() {}

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    hero
                    features
                    actions
                }
                .padding(16)
            }
        }
        .background(Theme.screenBackground)
        .task {
            if !purchases.hasProduct {
                isLoadingProduct = true
                await purchases.loadProducts()
                isLoadingProduct = false
            }
        }
        .alert("Something went wrong", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(purchases.lastError ?? "Unknown error")
        }
        .alert("Restore purchases", isPresented: $showRestoreAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(restoreMessage ?? "")
        }
        .confetti(trigger: confettiTrigger)
    }

    private var hero: some View {
        GradientCard(palette: .berry) {
            VStack(alignment: .leading, spacing: 10) {
                Text("🎉")
                    .font(.system(size: 64))
                Text("Unlimited dates")
                    .font(Theme.font(32, weight: .heavy))
                Text(heroBody)
                    .font(Theme.font(15, weight: .semibold))
                    .opacity(0.9)
            }
        }
    }

    private var heroBody: String {
        return "The free plan holds \(OccasionStore.freeLimit) dates. Unlock once, keep every birthday, anniversary and big day forever."
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Unlimited occasions", systemImage: "infinity")
            Label("Reminders for every one", systemImage: "bell.badge.fill")
            Label("One-time purchase, no subscription", systemImage: "checkmark.seal.fill")
        }
        .font(Theme.font(17, weight: .semibold))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    @ViewBuilder private var actions: some View {
        if purchases.isUnlocked {
            VStack(spacing: 12) {
                Text("You're unlocked — thank you!")
                    .font(Theme.font(20, weight: .heavy))
                Button("Done") { dismiss() }
                    .buttonStyle(PillButtonStyle(.primary))
            }
        } else {
            VStack(spacing: 12) {
                primaryAction
                Button("Restore purchases") { restore() }
                    .buttonStyle(PillButtonStyle(.secondary))
                    .disabled(purchases.isBusy)
                Button("Maybe later") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
    }

    @ViewBuilder private var primaryAction: some View {
        if purchases.hasProduct {
            Button(unlockTitle) { buy() }
                .buttonStyle(PillButtonStyle(.primary))
                .disabled(purchases.isBusy)
        } else if isLoadingProduct {
            Button("Loading price…") { }
                .buttonStyle(PillButtonStyle(.primary))
                .disabled(true)
        } else if purchases.productUnavailable {
            Text("The unlock isn't available right now. Please try again later.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        } else {
            Text("Couldn't reach the App Store.")
                .foregroundStyle(.secondary)
            Button("Try again") { reloadProduct() }
                .buttonStyle(PillButtonStyle(.primary))
        }
    }

    private var unlockTitle: String {
        return "Unlock for \(purchases.priceText)"
    }

    private func reloadProduct() {
        Task {
            isLoadingProduct = true
            await purchases.loadProducts()
            isLoadingProduct = false
        }
    }

    private func buy() {
        Task {
            let ok = await purchases.purchase()
            if ok {
                confettiTrigger += 1
            } else if purchases.lastError != nil {
                showError = true
            }
        }
    }

    private func restore() {
        Task {
            let ok = await purchases.restore()
            if ok {
                restoreMessage = "Your unlock has been restored."
                confettiTrigger += 1
            } else {
                restoreMessage = purchases.lastError ?? "No previous purchase found for this Apple ID."
            }
            showRestoreAlert = true
        }
    }
}
