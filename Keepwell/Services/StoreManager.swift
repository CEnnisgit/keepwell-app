import Foundation
import StoreKit
import Observation

@MainActor
@Observable
final class StoreManager {
    enum ProductID {
        static let monthly = "com.nimbuswebdesign.keepwell.pro.monthly"
        static let yearly = "com.nimbuswebdesign.keepwell.pro.yearly"
        static let lifetime = "com.nimbuswebdesign.keepwell.pro.lifetime"
        static let all = [monthly, yearly, lifetime]
    }

    private(set) var products: [String: Product] = [:]
    private(set) var purchasedProductIDs: Set<String> = []
    private(set) var isLoadingProducts = false
    private(set) var isPurchasing = false
    var errorMessage: String?

    var isPro: Bool { !purchasedProductIDs.isEmpty }
    var activePlanName: String? {
        if purchasedProductIDs.contains(ProductID.lifetime) { return "Lifetime" }
        if purchasedProductIDs.contains(ProductID.yearly) { return "Yearly" }
        if purchasedProductIDs.contains(ProductID.monthly) { return "Monthly" }
        return nil
    }

    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private var started = false

    func start() async {
        guard !started else { return }
        started = true
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                await self?.handle(result)
            }
        }
        await refreshEntitlements()
        await loadProducts()
    }

    func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let loaded = try await Product.products(for: ProductID.all)
            products = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
        } catch {
            errorMessage = "Couldn't load prices. \(error.localizedDescription)"
        }
    }

    func refreshEntitlements() async {
        var ids = Set<String>()
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, transaction.revocationDate == nil {
                ids.insert(transaction.productID)
            }
        }
        purchasedProductIDs = ids
    }

    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    errorMessage = "The purchase couldn't be verified."
                    return false
                }
                await transaction.finish()
                await refreshEntitlements()
                return true
            case .pending, .userCancelled:
                return false
            @unknown default:
                return false
            }
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func restore() async {
        do {
            try await AppStore.sync()
        } catch {
            errorMessage = error.localizedDescription
        }
        await refreshEntitlements()
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result else { return }
        await transaction.finish()
        await refreshEntitlements()
    }
}
