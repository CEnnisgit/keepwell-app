import SwiftUI

/// Design tokens from design/TOKENS.md. Color sets live in Assets.xcassets (Any / Dark).
extension Color {
    static let kwBrandTeal = Color("BrandTeal")
    static let kwBrandTealText = Color("BrandTealText")
    static let kwOnBrand = Color("OnBrand")
    static let kwBrandTint = Color("BrandTint")
    static let kwBackground = Color("Background")
    static let kwSurface = Color("Surface")
    static let kwTextPrimary = Color("TextPrimary")
    static let kwTextSecondary = Color("TextSecondary")
    static let kwSeparator = Color("Separator")
    static let kwKeep = Color("Keep")
    static let kwDelete = Color("Delete")
}

enum KWRadius {
    static let card: CGFloat = 28
    static let grouped: CGFloat = 16
    static let planRow: CGFloat = 16
    static let button: CGFloat = 14
    static let chip: CGFloat = 9
    static let thumb: CGFloat = 10
    static let badge: CGFloat = 6
}

enum KWLayout {
    static let screenPadding: CGFloat = 24
    static let cardPadding: CGFloat = 16
}

enum KWLinks {
    static let privacy = URL(string: "https://cennisgit.github.io/app-pages/apps/keepwell/privacy/")!
    static let support = URL(string: "https://cennisgit.github.io/app-pages/apps/keepwell/support/")!
    /// Apple's standard EULA, used as the Terms of Use for subscriptions.
    static let terms = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
}

func formatBytes(_ bytes: Int64) -> String {
    bytes.formatted(.byteCount(style: .file))
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.kwOnBrand)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(Color.kwBrandTeal.opacity(isEnabled ? 1 : 0.4),
                        in: RoundedRectangle(cornerRadius: KWRadius.button, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(KWLayout.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.kwSurface, in: RoundedRectangle(cornerRadius: KWRadius.grouped, style: .continuous))
    }
}

extension View {
    func kwCard() -> some View { modifier(CardBackground()) }
}

struct IconChip: View {
    let systemName: String
    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Color.kwBrandTeal)
            .frame(width: 34, height: 34)
            .background(Color.kwBrandTint, in: RoundedRectangle(cornerRadius: KWRadius.chip, style: .continuous))
            .accessibilityHidden(true)
    }
}
