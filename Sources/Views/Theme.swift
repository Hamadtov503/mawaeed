import SwiftUI
import UIKit

/// Warm, calm look: off-white background, white cards with a hairline border, gold accents.
enum Theme {
    static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }

    static let background = dyn(0xF6F3EC, 0x111312)
    static let card = dyn(0xFFFFFF, 0x1C1F1E)
    static let border = dyn(0xE6E0D2, 0x2C302E)
    static let ink = dyn(0x1C2321, 0xF1F3F2)
    static let muted = dyn(0x6F7673, 0x9AA29F)
    static let gold = dyn(0xA8782E, 0xE2B66A)
    static let goldSoft = dyn(0xF6EEDD, 0x2E2719)
    static let barSelected = dyn(0xEFE6D2, 0x2E2A22)

    static let uiBackground = UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0x111312) : UIColor(hex: 0xF6F3EC) }

    static func pill(_ s: Appointment.Status) -> (fg: Color, bg: Color) {
        switch s {
        case .today: return (dyn(0x8A6514, 0xF2C766), dyn(0xF5EBD3, 0x3A3120))
        case .tomorrow, .week: return (dyn(0x14627A, 0x80D3ED), dyn(0xE3F2F7, 0x14323C))
        case .later: return (dyn(0x2E6B4C, 0x8FD3AE), dyn(0xE4F0E8, 0x1F3329))
        case .past: return (dyn(0x5D6662, 0xA9B1AD), dyn(0xEDEFEE, 0x272B29))
        }
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

    /// Lets the warm background show behind a Form on every iOS version.
    @ViewBuilder func themedForm() -> some View {
        if #available(iOS 16.0, *) {
            self.scrollContentBackground(.hidden).background(Theme.background.ignoresSafeArea())
        } else {
            self.background(Theme.background.ignoresSafeArea())
        }
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
            .font(.footnote.weight(.semibold))
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

/// Section title with a gold side bar, like "موعدك الجاي".
struct SectionHeader: View {
    let title: String
    var detail: String? = nil
    var actionIcon: String? = nil
    var onAction: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            Capsule().fill(Theme.gold).frame(width: 5, height: 24)
            Text(title).font(.title3.bold()).foregroundColor(Theme.ink)
            if let d = detail { Text(d).font(.subheadline).foregroundColor(Theme.muted).lineLimit(1) }
            Spacer()
            if let icon = actionIcon, let run = onAction {
                Button(action: run) { Image(systemName: icon).font(.body).foregroundColor(Theme.muted) }
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
            Image(systemName: icon).font(.system(size: 40)).foregroundColor(Theme.gold)
            Text(title).font(.headline).foregroundColor(Theme.ink)
            if !message.isEmpty {
                Text(message).font(.subheadline).foregroundColor(Theme.muted).multilineTextAlignment(.center)
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
