import Foundation
import Combine
import StoreKit

@MainActor
final class PurchaseManager: ObservableObject {
    static let productID: String = "com.iflora.savethedate.unlock"

    @Published private(set) var isUnlocked: Bool
    @Published private(set) var product: Product? = nil
    @Published private(set) var isBusy: Bool = false
    @Published private(set) var productUnavailable: Bool = false
    @Published var lastError: String? = nil

    private let defaults: UserDefaults
    private let fallbackPrice: String?
    private var updatesTask: Task<Void, Never>? = nil

    init(defaults: UserDefaults = UserDefaults.standard, fallbackPrice: String? = nil) {
        self.defaults = defaults
        self.fallbackPrice = fallbackPrice
        self.isUnlocked = defaults.bool(forKey: AppDefaults.isUnlockedKey)
        self.updatesTask = Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await self?.refreshEntitlements()
                }
            }
        }
    }

    var hasProduct: Bool {
        return product != nil || fallbackPrice != nil
    }

    var priceText: String {
        if let displayPrice = product?.displayPrice {
            return displayPrice
        }
        return fallbackPrice ?? "…"
    }

    func start() async {
        await loadProducts()
        await refreshEntitlements()
    }

    func loadProducts() async {
        lastError = nil
        productUnavailable = false
        do {
            let products: [Product] = try await Product.products(for: [PurchaseManager.productID])
            product = products.first
            productUnavailable = (product == nil && fallbackPrice == nil)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func refreshEntitlements() async {
        var unlocked = false
        var sawRevocation = false
        for await result in StoreKit.Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == PurchaseManager.productID {
                if transaction.revocationDate == nil {
                    unlocked = true
                } else {
                    sawRevocation = true
                }
            }
        }
        if unlocked {
            setUnlocked(true)
        } else if sawRevocation {
            setUnlocked(false)
        }
        // An empty scan (signed out, cold cache, restored backup) is not proof that
        // nothing was bought, so the persisted unlock is left exactly as it was.
    }

    func purchase() async -> Bool {
        if isBusy { return false }
        lastError = nil
        if product == nil { await loadProducts() }
        guard let product = product else {
            lastError = "The unlock is not available right now. Please try again later."
            return false
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let result: Product.PurchaseResult = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    setUnlocked(true)
                    return true
                case .unverified:
                    lastError = "The purchase could not be verified."
                    return false
                @unknown default:
                    lastError = "The purchase could not be verified."
                    return false
                }
            case .userCancelled:
                return false
            case .pending:
                lastError = "The purchase is pending approval."
                return false
            @unknown default:
                return false
            }
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func restore() async -> Bool {
        if isBusy { return isUnlocked }
        lastError = nil
        isBusy = true
        defer { isBusy = false }
        do {
            try await AppStore.sync()
        } catch {
            lastError = error.localizedDescription
        }
        await refreshEntitlements()
        return isUnlocked
    }

    private func setUnlocked(_ value: Bool) {
        isUnlocked = value
        defaults.set(value, forKey: AppDefaults.isUnlockedKey)
    }
}
