import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(StoreManager.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var selected: Plan = .yearly

    enum Plan: CaseIterable, Identifiable {
        case yearly, lifetime, monthly   // display order; lifetime always visible without scrolling
        var id: Self { self }
        var productID: String {
            switch self {
            case .yearly: StoreManager.ProductID.yearly
            case .lifetime: StoreManager.ProductID.lifetime
            case .monthly: StoreManager.ProductID.monthly
            }
        }
        var title: String {
            switch self { case .yearly: "Yearly"; case .lifetime: "Lifetime"; case .monthly: "Monthly" }
        }
        var subtitle: String {
            switch self {
            case .yearly: "Billed once a year"
            case .lifetime: "Pay once, share with family"
            case .monthly: "Billed every month"
            }
        }
        /// Shown only in DEBUG Simulator runs launched outside Xcode, where the scheme's
        /// StoreKit configuration isn't loaded. Mirrors Keepwell.storekit.
        var debugFallbackPrice: String {
            switch self { case .yearly: "$14.99"; case .lifetime: "$24.99"; case .monthly: "$3.99" }
        }
    }

    private func price(_ plan: Plan) -> String? {
        if let p = store.products[plan.productID] { return p.displayPrice }
        #if DEBUG
        return plan.debugFallbackPrice
        #else
        return nil
        #endif
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                benefits
                plans
                Button {
                    Task {
                        guard let product = store.products[selected.productID] else {
                            store.errorMessage = "Prices aren't available right now. Please try again later."
                            return
                        }
                        if await store.purchase(product) { dismiss() }
                    }
                } label: {
                    if store.isPurchasing { ProgressView().tint(Color.kwOnBrand) } else { Text("Continue") }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(store.isPurchasing)

                Text("Not now? Free keeps unlimited swiping and \(CleanupStore.freeDailyDeleteLimit) deletes a day.")
                    .font(.subheadline.weight(.medium))
                    .multilineTextAlignment(.center)
                disclosure
                links
            }
            .padding(.horizontal, KWLayout.screenPadding)
            .padding(.bottom, 16)
        }
        .background(Color.kwBackground.ignoresSafeArea())
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.kwTextSecondary)
                    .frame(width: 30, height: 30)
                    .background(Color.kwSeparator, in: Circle())
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Close")
            .padding(.trailing, 12)
            .padding(.top, 8)
        }
        .alert("Purchase", isPresented: Binding(get: { store.errorMessage != nil },
                                                set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(store.errorMessage ?? "") }
        .onChange(of: store.isPro) { _, isPro in if isPro { dismiss() } }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image("BrandIcon")
                .resizable()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityHidden(true)
            Text("Keepwell Pro")
                .font(.largeTitle.weight(.bold))
            Text("Clear your camera roll at your own pace. Everything stays on your iPhone.")
                .font(.body)
                .foregroundStyle(Color.kwTextSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 40)
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: 14) {
            benefit("rectangle.portrait.and.arrow.right", "Unlimited deletes",
                    "No daily cap. Deleted photos stay in Recently Deleted for 30 days.")
            benefit("square.on.square", "Duplicate & similar groups",
                    "Found on-device, best shot suggested.")
            benefit("calendar", "On this day & by month",
                    "Short review sessions instead of one huge pile.")
            benefit("gauge.with.needle", "Space freed total",
                    "A running count of what you've cleared.")
        }
        .kwCard()
    }

    private func benefit(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            IconChip(systemName: icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold))
                Text(detail).font(.footnote).foregroundStyle(Color.kwTextSecondary)
            }
        }
    }

    private var plans: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CHOOSE A PLAN")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.kwTextSecondary)
            ForEach(Plan.allCases) { plan in
                Button { selected = plan } label: { planRow(plan) }
                    .accessibilityAddTraits(selected == plan ? .isSelected : [])
            }
        }
    }

    private func planRow(_ plan: Plan) -> some View {
        let isSelected = selected == plan
        let p = price(plan)
        return HStack(spacing: 12) {
            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .font(.title2)
                .foregroundStyle(isSelected ? Color.kwBrandTeal : Color.kwSeparator)
            VStack(alignment: .leading, spacing: 2) {
                Text(plan.title).font(.body.weight(.semibold)).foregroundStyle(Color.kwTextPrimary)
                Text(plan.subtitle).font(.footnote).foregroundStyle(Color.kwTextSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                switch plan {
                case .yearly: Text(p.map { "\($0)/year" } ?? "—")
                case .monthly: Text(p.map { "\($0)/month" } ?? "—")
                case .lifetime:
                    Text(p ?? "—")
                    Text("one-time").font(.caption).foregroundStyle(Color.kwTextSecondary)
                }
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(Color.kwTextPrimary)
        }
        .padding(KWLayout.cardPadding)
        .background(Color.kwSurface, in: RoundedRectangle(cornerRadius: KWRadius.planRow, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: KWRadius.planRow, style: .continuous)
                .stroke(isSelected ? Color.kwBrandTeal : .clear, lineWidth: 2)
        }
    }

    private var disclosure: some View {
        let yearly = price(.yearly).map { " Yearly is \($0) per year." } ?? ""
        let monthly = price(.monthly).map { " Monthly is \($0) per month." } ?? ""
        return Text("Payment is charged to your Apple Account at confirmation.\(yearly)\(monthly) Subscriptions renew automatically unless canceled at least 24 hours before the end of the current period, and your account is charged for renewal within 24 hours before the period ends. Manage or cancel anytime in Settings › [your name] › Subscriptions. Lifetime is a one-time purchase and can be shared with up to five family members through Family Sharing. Subscriptions can't be shared. Deleted photos stay in Recently Deleted for 30 days.")
            .font(.caption2)
            .foregroundStyle(Color.kwTextSecondary)
            .multilineTextAlignment(.center)
    }

    private var links: some View {
        VStack(spacing: 4) {
            Button("Restore Purchases") { Task { await store.restore() } }
                .frame(minHeight: 44)
            HStack(spacing: 16) {
                Button("Terms of Use") { openURL(KWLinks.terms) }
                Button("Privacy Policy") { openURL(KWLinks.privacy) }
                Button("Support") { openURL(KWLinks.support) }
            }
            .frame(minHeight: 44)
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(Color.kwBrandTealText)
    }
}
