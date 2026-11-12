import SwiftUI

/// First screen the app shows: a short welcome splash every launch, and the intro the first time.
struct AppEntry: View {
    @EnvironmentObject var settings: AppSettings
    @State private var splash = true

    var body: some View {
        ZStack {
            if settings.onboarded {
                RootView()
            } else {
                OnboardingView {
                    withAnimation(.easeInOut(duration: 0.45)) { settings.onboarded = true }
                }
                .transition(.opacity)
            }
            if splash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(10)
                    .onTapGesture { withAnimation(.easeOut(duration: 0.3)) { splash = false } }
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                withAnimation(.easeOut(duration: 0.5)) { splash = false }
            }
        }
    }
}

/// The logo grows in with the name in Ruqaa calligraphy.
struct SplashView: View {
    @State private var shown = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            PatternBackground().opacity(0.6)
            VStack(spacing: 14) {
                Image("Logo")
                    .resizable().scaledToFit()
                    .frame(width: 150, height: 150)
                    .scaleEffect(shown ? 1 : 0.7)
                    .opacity(shown ? 1 : 0)
                Text(L("مواعيدي", "Mawaeed"))
                    .font(.ruqaa(size: 52))
                    .foregroundColor(Theme.burgundy)
                    .opacity(shown ? 1 : 0)
                    .offset(y: shown ? 0 : 12)
                Text(L("مواعيدك في مكان واحد", "All your appointments in one place"))
                    .font(.app(.subheadline, .medium))
                    .foregroundColor(Theme.muted)
                    .opacity(shown ? 1 : 0)
            }
        }
        .onAppear { withAnimation(.spring(response: 0.6, dampingFraction: 0.75)) { shown = true } }
    }
}

/// A faint grid of eight-pointed stars, the same motif as the app icon.
struct PatternBackground: View {
    var body: some View {
        GeometryReader { g in
            let step: CGFloat = 120
            let cols = Int(g.size.width / step) + 2
            let rows = Int(g.size.height / step) + 2
            ZStack {
                ForEach(0..<(cols * rows), id: \.self) { i in
                    EightPointStar()
                        .stroke(Theme.sand, lineWidth: 1.5)
                        .frame(width: 70, height: 70)
                        .position(x: CGFloat(i % cols) * step + step / 2 - 30, y: CGFloat(i / cols) * step + step / 2 - 30)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

struct EightPointStar: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: r.midX, y: r.midY), rad = min(r.width, r.height) / 2
        for rot in [0.0, 45.0] {
            let pts = [45.0, 135.0, 225.0, 315.0].map { a -> CGPoint in
                let t = (a + rot) * .pi / 180
                return CGPoint(x: c.x + rad * CGFloat(cos(t)), y: c.y + rad * CGFloat(sin(t)))
            }
            p.addLines(pts)
            p.closeSubpath()
        }
        return p
    }
}

/// Three steps: welcome, your name, notifications.
struct OnboardingView: View {
    @EnvironmentObject var settings: AppSettings
    let onDone: () -> Void
    @State private var step = 0
    @State private var name = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            PatternBackground().opacity(0.45)
                .onAppear { name = settings.userName }
            VStack(spacing: 0) {
                Spacer(minLength: 20)
                Group {
                    switch step {
                    case 0: welcome
                    case 1: nameStep
                    default: notificationsStep
                    }
                }
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)))
                .id(step)
                Spacer(minLength: 20)
                dots.padding(.bottom, 18)
                primaryButton
                secondaryButton
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
            .frame(maxWidth: 560)
        }
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(spacing: 18) {
            Image("Logo").resizable().scaledToFit().frame(width: 130, height: 130)
            Text(L("مواعيدي", "Mawaeed")).font(.ruqaa(size: 56)).foregroundColor(Theme.burgundy)
            Text(L("سجّل مواعيدك، وأنا أذكّرك قبلها بالوقت اللي يناسبك.", "Add your appointments and I'll remind you ahead, when it suits you."))
                .font(.app(.title3, .medium)).foregroundColor(Theme.ink)
                .multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 14) {
                feature("bell.badge.fill", Theme.burgundy, L("تنبيهات قبل الموعد", "Reminders before"), L("من وقت الموعد إلى قبل أسبوع، وملخص كل صباح.", "From the time itself to a week before, plus a morning summary."))
                feature("moon.stars.fill", Theme.forest, L("هجري وميلادي", "Hijri & Gregorian"), L("كل موعد بالتاريخين، وتقدر تدخله بالهجري.", "Every date in both calendars, and you can enter it in Hijri."))
                feature("checklist", Theme.navy, L("مواعيدك ومهامك", "Appointments & tasks"), L("تقويم هجري وميلادي يجمعها، ومزامنة بين أجهزتك.", "One Hijri/Gregorian calendar for both, synced across your devices."))
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.border, lineWidth: 1))
        }
    }

    private var nameStep: some View {
        VStack(spacing: 18) {
            Tile(icon: "person.fill", color: Theme.navy, size: 84)
            Text(L("وش نناديك؟", "What should we call you?")).font(.app(.title, .bold)).foregroundColor(Theme.ink)
            Text(L("اسمك يطلع في الترحيب: «مساء الخير 🌷 اسمك».", "Your name appears in the greeting."))
                .font(.app(.subheadline)).foregroundColor(Theme.muted).multilineTextAlignment(.center)
            TextField(L("اسمك", "Your name"), text: $name)
                .font(.app(.title3, .semibold))
                .multilineTextAlignment(.center)
                .focused($nameFocused)
                .submitLabel(.next)
                .onSubmit(next)
                .padding(.vertical, 16)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.card))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.border, lineWidth: 1))
        }
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { nameFocused = true } }
    }

    private var notificationsStep: some View {
        VStack(spacing: 18) {
            Tile(icon: "bell.and.waves.left.and.right.fill", color: Theme.burgundy, size: 84)
            Text(name.isEmpty ? L("خلّني أذكّرك", "Let me remind you") : L("خلّني أذكّرك يا \(name)", "Let me remind you, \(name)"))
                .font(.app(.title, .bold)).foregroundColor(Theme.ink).multilineTextAlignment(.center)
            Text(L("فعّل التنبيهات عشان يوصلك تذكير قبل كل موعد، وملخص الصباح.", "Turn on notifications to get a reminder before each appointment and a morning summary."))
                .font(.app(.body)).foregroundColor(Theme.muted).multilineTextAlignment(.center)
        }
    }

    private func feature(_ icon: String, _ color: Color, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Tile(icon: icon, color: color, size: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.app(.subheadline, .bold)).foregroundColor(Theme.ink)
                Text(detail).font(.app(.caption)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Controls

    private var dots: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { i in
                Capsule().fill(i == step ? Theme.burgundy : Theme.border)
                    .frame(width: i == step ? 22 : 8, height: 8)
            }
        }
        .animation(.easeInOut, value: step)
    }

    private var primaryButton: some View {
        Button(action: next) {
            Text(step == 0 ? L("يلا نبدأ", "Let's start") : (step == 1 ? L("التالي", "Next") : L("فعّل التنبيهات", "Turn on notifications")))
                .font(.app(.headline, .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(Capsule().fill(Theme.burgundy))
                .shadow(color: Theme.burgundy.opacity(0.3), radius: 10, y: 5)
        }
        .buttonStyle(.plain)
    }

    private var secondaryButton: some View {
        Button(step == 2 ? L("لاحقاً", "Later") : (step == 1 ? L("تخطي", "Skip") : " ")) {
            if step == 1 { advance() } else if step == 2 { finish() }
        }
        .font(.app(.subheadline, .semibold))
        .foregroundColor(Theme.muted)
        .padding(.top, 12)
        .opacity(step == 0 ? 0 : 1)
        .disabled(step == 0)
    }

    private func next() {
        switch step {
        case 1:
            settings.userName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            advance()
        case 2:
            NotificationManager.shared.requestAuthorization { _ in finish() }
        default:
            advance()
        }
    }

    private func advance() {
        nameFocused = false
        withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) { step += 1 }
    }

    private func finish() {
        onDone()
    }
}
