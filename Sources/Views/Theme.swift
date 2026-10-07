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
    /// Espresso black by night, warm ivory by day; never a plain grey.
    static let screenBackground: Color = dynamic(dark: 0x110D0B, light: 0xF6F0E7)
    static let cardBackground: Color = dynamic(dark: 0x1D1714, light: 0xFFFCF7)
    static let chipBackground: Color = dynamic(dark: 0x2A221D, light: 0xECE3D5)
    /// Filled gold for primary buttons and selected chips, with the text that sits on it.
    static let accentFill: Color = dynamic(dark: 0xD6BE8C, light: 0x8A6A2C)
    static let onAccent: Color = dynamic(dark: 0x1A1408, light: 0xFFFFFF)
    /// The thin gold line on the hero card and around portrait photos.
    static let goldLine: Color = Color(hex: 0xE9D4A6)
    /// Gold into rose into violet. Used only where Apple Intelligence is at work,
    /// so the "magic" colour always means AI.
    static let aurora: LinearGradient = LinearGradient(
        colors: [Color(hex: 0xD6A95C), Color(hex: 0xC8607A), Color(hex: 0x7B5CC8)],
        startPoint: .leading,
        endPoint: .trailing
    )
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
        return hexes(palette).map { Color(hex: $0) }
    }

    /// The same two stops as 0xRRGGBB, so the widget snapshot can carry them.
    static func hexes(_ palette: OccasionPalette) -> [UInt] {
        switch palette {
        case .sunset:
            return [0x8A3F30, 0x9E5C3C]
        case .ocean:
            return [0x1C4A58, 0x2F7480]
        case .berry:
            return [0x5A2A47, 0x87455F]
        case .lime:
            return [0x2C4A3A, 0x467457]
        case .candy:
            return [0x833643, 0x9C5C68]
        case .midnight:
            return [0x1F2C44, 0x3B5372]
        case .peach:
            return [0x82452A, 0x99613D]
        case .grape:
            return [0x42325A, 0x6B5486]
        }
    }

    private static func dynamic(dark: UInt, light: UInt) -> Color {
        return Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255.0,
                green: CGFloat((hex >> 8) & 0xFF) / 255.0,
                blue: CGFloat(hex & 0xFF) / 255.0,
                alpha: 1
            )
        })
    }

    static func gradient(_ palette: OccasionPalette) -> LinearGradient {
        return LinearGradient(colors: colors(palette), startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // Type
    static func font(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        return Font.system(size: size, weight: weight, design: .rounded)
    }

    /// Serif for titles, names and big day counts; rounded stays for everything else.
    static func display(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        return Font.system(size: size, weight: weight, design: .serif)
    }

    /// Small spaced capitals such as "NEXT UP". Pair with `.tracking(2)`.
    static let eyebrowFont: Font = Theme.font(12, weight: .semibold)

    static let chipFont: Font = Theme.font(15, weight: .semibold)

    /// Navigation bar titles in the same serif. Called once, before any bar exists.
    static func applyNavigationBarFonts() {
        let bar = UINavigationBar.appearance()
        if let large = UIFont.systemFont(ofSize: 34, weight: .regular).fontDescriptor.withDesign(.serif) {
            bar.largeTitleTextAttributes = [.font: UIFont(descriptor: large, size: 34)]
        }
        if let inline = UIFont.systemFont(ofSize: 17, weight: .semibold).fontDescriptor.withDesign(.serif) {
            bar.titleTextAttributes = [.font: UIFont(descriptor: inline, size: 17)]
        }
    }

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
            return Theme.accentFill
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
            return Theme.onAccent
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
                .background(isSelected ? Theme.accentFill : Theme.chipBackground, in: Capsule())
                .foregroundStyle(isSelected ? Theme.onAccent : Color.primary)
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
            // A soft warm light from the top left, as if the card sat near a lamp.
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .fill(LinearGradient(colors: [Color.white.opacity(0.12), Color.clear], startPoint: .topLeading, endPoint: .center))
                    .allowsHitTesting(false)
            }
            .shadow(color: Color.black.opacity(0.18), radius: 14, x: 0, y: 6)
            .foregroundStyle(Theme.onGradientText)
    }
}

/// Light is the default; Settings also offers dark and following the iPhone.
enum AppAppearance: String, CaseIterable, Identifiable {
    case dark
    case light
    case system

    static let storageKey: String = "appearance"
    static let defaultChoice: AppAppearance = .light

    var id: String { return rawValue }

    var label: String {
        switch self {
        case .dark:
            return "Dark"
        case .light:
            return "Light"
        case .system:
            return "Auto"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .dark:
            return .dark
        case .light:
            return .light
        case .system:
            return nil
        }
    }
}

extension View {
    /// Forms and lists on the warm screen colour instead of the system grey.
    func themedFormBackground() -> some View {
        return self
            .scrollContentBackground(.hidden)
            .background(Theme.screenBackground)
    }
}
