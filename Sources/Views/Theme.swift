import SwiftUI
import UIKit

/// Beige base with four deep accents: burgundy, navy, forest green and slate.
enum Theme {
    static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }

    // Base
    static let background = dyn(0xF4EDE1, 0x15130F)
    static let card = dyn(0xFBF7EF, 0x201D18)
    static let sand = dyn(0xEDE2CF, 0x2A251E)
    static let border = dyn(0xE2D5BF, 0x342E26)
    static let ink = dyn(0x2B2522, 0xF2ECE3)
    static let muted = dyn(0x7D7369, 0xA69D90)

    // Accents
    static let burgundy = dyn(0x7B1E2E, 0xC9576A)
    static let navy = dyn(0x1E2C47, 0x8EA6D6)
    static let forest = dyn(0x1F4D3A, 0x7CC4A2)
    static let slate = dyn(0x3B3F45, 0xB5BAC2)

    /// The side menu and its edge tab: deep burgundy fading to a warm brown.
    static let menuTop = Color(red: 0.43, green: 0.11, blue: 0.17)
    static let menuBottom = Color(red: 0.66, green: 0.42, blue: 0.27)

    static let barSelected = dyn(0xEADCC6, 0x352D24)

    static let uiBackground = UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0x15130F) : UIColor(hex: 0xF4EDE1) }
    static let uiInk = UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0xF2ECE3) : UIColor(hex: 0x2B2522) }

    static func pill(_ s: Appointment.Status) -> (fg: Color, bg: Color) {
        switch s {
        case .today: return (burgundy, dyn(0xF3E1DF, 0x3A2024))
        case .tomorrow, .week: return (navy, dyn(0xE2E7F0, 0x1D2536))
        case .later: return (forest, dyn(0xE0EBE3, 0x1B2E25))
        case .past: return (slate, dyn(0xE7E4DE, 0x2A2A2A))
        }
    }
}

/// IBM Plex Sans Arabic for all text, Aref Ruqaa for the calligraphic weekday.
enum AppFont {
    /// Plex Arabic looks larger than SF at the same point size; every size is scaled by this.
    static let scale: CGFloat = 0.92

    static func name(_ w: Font.Weight) -> String {
        switch w {
        case .bold, .heavy, .black: return "IBMPlexSansArabic-Bold"
        case .semibold: return "IBMPlexSansArabic-SemiBold"
        case .medium: return "IBMPlexSansArabic-Medium"
        default: return "IBMPlexSansArabic-Regular"
        }
    }

    static func size(_ style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: return 34
        case .title: return 28
        case .title2: return 22
        case .title3: return 20
        case .headline, .body: return 17
        case .callout: return 16
        case .subheadline: return 15
        case .footnote: return 13
        case .caption: return 12
        case .caption2: return 11
        @unknown default: return 17
        }
    }

    static func ui(_ size: CGFloat, _ w: Font.Weight = .regular) -> UIFont {
        UIFont(name: name(w), size: size * scale) ?? .systemFont(ofSize: size)
    }
}

extension Font {
    /// The app font for a text style (scales with Dynamic Type). Headlines default to semibold.
    static func app(_ style: Font.TextStyle, _ weight: Font.Weight? = nil) -> Font {
        let w = weight ?? (style == .headline ? .semibold : .regular)
        return .custom(AppFont.name(w), size: AppFont.size(style) * AppFont.scale, relativeTo: style)
    }

    static func app(size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom(AppFont.name(weight), size: size * AppFont.scale)
    }

    static func ruqaa(size: CGFloat) -> Font {
        .custom("ArefRuqaa-Bold", size: size)
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

extension View {
    func card(padding: CGFloat = 16, radius: CGFloat = 24) -> some View {
        self.padding(padding)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }

    /// Right-to-left, Arabic locale with Western digits, Gregorian calendar.
    /// Applied at the app root and again at the root of every sheet. SwiftUI does not pick up the
    /// direction on its own here: without it, Form/List content was drawn mirrored.
    func appEnvironment() -> some View {
        self.environment(\.layoutDirection, Fmt.isArabic ? .rightToLeft : .leftToRight)
            .environment(\.locale, Fmt.locale)
            .environment(\.calendar, Fmt.greg)
            .font(.app(.body))
            .preferredColorScheme(.light)   // always the beige look, even in dark mode
    }
}

struct Tile: View {
    let icon: String
    var color: Color = .brand
    var size: CGFloat = 50

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(color.opacity(0.13))
            .frame(width: size, height: size)
            .overlay(Image(systemName: icon).font(.system(size: size * 0.42, weight: .semibold)).foregroundColor(color))
    }
}

struct StatusPill: View {
    let text: String
    let status: Appointment.Status

    var body: some View {
        let c = Theme.pill(status)
        Text(text)
            .font(.app(.footnote, .semibold))
            .foregroundColor(c.fg)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(c.bg))
            .lineLimit(1)
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
                if let icon = icon { Image(systemName: icon).font(.app(.caption)) }
                Text(title).font(.app(.subheadline, .semibold))
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

/// Section title with a burgundy side bar, like "موعدك الجاي".
struct SectionHeader: View {
    let title: String
    var detail: String? = nil
    var actionIcon: String? = nil
    var onAction: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            Capsule().fill(Theme.burgundy).frame(width: 5, height: 24)
            Text(title).font(.app(.title3, .bold)).foregroundColor(Theme.ink)
            if let d = detail { Text(d).font(.app(.subheadline)).foregroundColor(Theme.muted).lineLimit(1) }
            Spacer()
            if let icon = actionIcon, let run = onAction {
                Button(action: run) { Image(systemName: icon).font(.app(.body)).foregroundColor(Theme.muted) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.top, 4)
    }
}

struct EmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 40)).foregroundColor(Theme.burgundy)
            Text(title).font(.app(.headline)).foregroundColor(Theme.ink)
            if !message.isEmpty {
                Text(message).font(.app(.subheadline)).foregroundColor(Theme.muted).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}

/// NavigationStack on iOS 16+, NavigationView on iOS 15. The app never pushes pages
/// (details and forms open as sheets): pushed pages were drawn mirrored in right-to-left.
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

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
