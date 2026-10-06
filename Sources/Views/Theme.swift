import SwiftUI
import UIKit

extension Color {
    /// Color(hex: 0xFF5F6D) -> red/green/blue 0...1 from 0xRRGGBB
    init(hex: UInt) {
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue)
    }
}

enum Theme {
    // Radii
    static let cardRadius: CGFloat = 28
    static let fieldRadius: CGFloat = 16

    // Motion
    static let spring: Animation = .spring(response: 0.4, dampingFraction: 0.72)
    static let bouncy: Animation = .spring(response: 0.5, dampingFraction: 0.55)

    // Colors
    /// The icon's champagne gold. It is calibrated against near-black, so light mode
    /// uses a deeper version to keep small tinted labels readable.
    static let accent: Color = Color(uiColor: UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.839, green: 0.745, blue: 0.549, alpha: 1)
        }
        return UIColor(red: 0.494, green: 0.388, blue: 0.161, alpha: 1)
    })
    static let screenBackground: Color = Color(uiColor: .systemGroupedBackground)
    static let cardBackground: Color = Color(uiColor: .secondarySystemGroupedBackground)
    static let chipBackground: Color = Color(uiColor: .secondarySystemFill)
    static let onGradientText: Color = .white
    static let confettiColors: [Color] = [
        Color(hex: 0xD6BE8C), Color(hex: 0xC2A15F), Color(hex: 0xB08A5A),
        Color(hex: 0xE8E2D6), Color(hex: 0x9A8C6E), .white
    ]

    /// Two stops per palette, topLeading -> bottomTrailing. Deep and desaturated to sit
    /// beside the gold-on-charcoal app icon. Every stop keeps at least 4.5:1 against white,
    /// because the day count and card titles are white heavy type drawn straight on top.
    /// The case names are persisted in occasions.json, so they never change, only the hues.
    static func colors(_ palette: OccasionPalette) -> [Color] {
        switch palette {
        case .sunset:
            return [Color(hex: 0x8A3F30), Color(hex: 0x9E5C3C)]
        case .ocean:
            return [Color(hex: 0x1C4A58), Color(hex: 0x2F7480)]
        case .berry:
            return [Color(hex: 0x5A2A47), Color(hex: 0x87455F)]
        case .lime:
            return [Color(hex: 0x2C4A3A), Color(hex: 0x467457)]
        case .candy:
            return [Color(hex: 0x833643), Color(hex: 0x9C5C68)]
        case .midnight:
            return [Color(hex: 0x1F2C44), Color(hex: 0x3B5372)]
        case .peach:
            return [Color(hex: 0x82452A), Color(hex: 0x99613D)]
        case .grape:
            return [Color(hex: 0x42325A), Color(hex: 0x6B5486)]
        }
    }

    static func gradient(_ palette: OccasionPalette) -> LinearGradient {
        return LinearGradient(colors: colors(palette), startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // Type
    static func font(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        return Font.system(size: size, weight: weight, design: .rounded)
    }

    static let chipFont: Font = Theme.font(15, weight: .semibold)

    static let emojiChoices: [String] = ["🎂", "🎉", "💍", "❤️", "🥂", "🎓", "🏡", "👶", "🐶", "🐱", "🌸", "✈️", "🎄", "🎁", "⭐️", "🏆"]
}

struct PillButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, onGradient, destructive }

    let kind: Kind

    init(_ kind: Kind = .primary) {
        self.kind = kind
    }

    private var fill: Color {
        switch kind {
        case .primary:
            return Color.primary
        case .secondary:
            return Theme.chipBackground
        case .onGradient:
            return Color.white.opacity(0.22)
        case .destructive:
            return Theme.chipBackground
        }
    }

    private var foreground: Color {
        switch kind {
        case .primary:
            return Color(uiColor: .systemBackground)
        case .secondary:
            return Color.primary
        case .onGradient:
            return Color.white
        case .destructive:
            return Color.red
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.font(17, weight: .bold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 20)
            .background(fill, in: Capsule())
            .foregroundStyle(foreground)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(Theme.spring, value: configuration.isPressed)
    }
}

struct Chip: View {
    let label: String
    let isSelected: Bool
    let font: Font
    let action: () -> Void

    init(_ label: String, isSelected: Bool, font: Font = Theme.chipFont, action: @escaping () -> Void) {
        self.label = label
        self.isSelected = isSelected
        self.font = font
        self.action = action
    }

    var body: some View {
        Button {
            action()
        } label: {
            Text(label)
                .font(font)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? Color.primary : Theme.chipBackground, in: Capsule())
                .foregroundStyle(isSelected ? Color(uiColor: .systemBackground) : Color.primary)
        }
        .buttonStyle(.plain)
        .animation(Theme.spring, value: isSelected)
    }
}

struct GradientCard<Content: View>: View {
    let palette: OccasionPalette
    let content: () -> Content

    init(palette: OccasionPalette, @ViewBuilder content: @escaping () -> Content) {
        self.palette = palette
        self.content = content
    }

    var body: some View {
        content()
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.gradient(palette), in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .foregroundStyle(Theme.onGradientText)
    }
}
