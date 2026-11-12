import SwiftUI
import UIKit

/// Calm, card-based look: warm off-white background, white cards with a hairline border,
/// soft icon tiles and coloured status pills.
enum Theme {
    static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }

    static let background = dyn(0xF6F5F0, 0x111312)
    static let card = dyn(0xFFFFFF, 0x1C1F1E)
    static let border = dyn(0xE6E4DC, 0x2C302E)
    static let tile = dyn(0xEEF2EF, 0x26302C)
    static let ink = dyn(0x1C2321, 0xF1F3F2)
    static let muted = dyn(0x6F7673, 0x9AA29F)
    static let barSelected = dyn(0xE3ECE9, 0x2A3632)

    static let uiBackground = UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0x111312) : UIColor(hex: 0xF6F5F0) }

    /// Pill colours by urgency.
    static func pill(_ u: Urgency) -> (fg: Color, bg: Color) {
        switch u {
        case .overdue: return (dyn(0xB2392C, 0xFF8A7A), dyn(0xF9E3DF, 0x3A2220))
        case .today: return (dyn(0x8A6514, 0xF2C766), dyn(0xF5EBD3, 0x3A3120))
        case .week: return (dyn(0x9A5B12, 0xF0B070), dyn(0xF7E9DA, 0x3A2C20))
        case .month, .later: return (dyn(0x2E6B4C, 0x8FD3AE), dyn(0xE4F0E8, 0x1F3329))
        case .done: return (dyn(0x5D6662, 0xA9B1AD), dyn(0xEDEFEE, 0x272B29))
        }
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

struct CardStyle: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View { modifier(CardStyle(padding: padding)) }

    /// Lets the warm background show behind List / Form on every iOS version.
    @ViewBuilder func themedList() -> some View {
        if #available(iOS 16.0, *) {
            self.scrollContentBackground(.hidden).background(Theme.background.ignoresSafeArea())
        } else {
            self.background(Theme.background.ignoresSafeArea())
        }
    }
}

struct StatusPill: View {
    let text: String
    let urgency: Urgency

    var body: some View {
        let c = Theme.pill(urgency)
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundColor(c.fg)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(c.bg))
            .lineLimit(1)
    }
}

struct Tile: View {
    let icon: String
    var color: Color = .brand
    var size: CGFloat = 52

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
            .fill(color.opacity(0.12))
            .frame(width: size, height: size)
            .overlay(Image(systemName: icon).font(.system(size: size * 0.42, weight: .semibold)).foregroundColor(color))
    }
}

struct Chip: View {
    let title: String
    var icon: String? = nil
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon = icon { Image(systemName: icon).font(.caption) }
                Text(title).font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .foregroundColor(selected ? .white : Theme.ink)
            .background(Capsule().fill(selected ? Color.brand : Theme.card))
            .overlay(Capsule().stroke(selected ? Color.clear : Theme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// Big page title with a muted subtitle, like a header of a native page.
struct PageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 34, weight: .bold)).foregroundColor(Theme.ink)
            if !subtitle.isEmpty {
                Text(subtitle).font(.subheadline).foregroundColor(Theme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }
}

/// NavigationStack on iOS 16+ (better right-to-left push/pop handling), NavigationView on iOS 15.
struct AppNavigation<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        if #available(iOS 16.0, *) {
            NavigationStack { content }
        } else {
            NavigationView { content }.navigationViewStyle(.stack)
        }
    }
}
