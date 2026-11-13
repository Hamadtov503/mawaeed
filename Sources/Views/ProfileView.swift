import SwiftUI

/// Your profile, opened from the person button on home: your name (shown in the home greeting).
struct ProfileView: View {
    @EnvironmentObject var settings: AppSettings
    @FocusState private var editing: Bool

    private var name: String { settings.userName.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                // A round badge with the first letter of the name (or a person when there is none).
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Theme.burgundy, Theme.burgundy.opacity(0.8)], startPoint: .top, endPoint: .bottom))
                    if let first = name.first {
                        Text(String(first)).font(.app(size: 40, .bold)).foregroundColor(.white)
                    } else {
                        Image(systemName: "person.fill").font(.system(size: 38)).foregroundColor(.white)
                    }
                }
                .frame(width: 96, height: 96)
                .shadow(color: Theme.burgundy.opacity(0.3), radius: 10, y: 5)
                .padding(.top, 10)
                .animation(Router.soft, value: name)

                VStack(alignment: .leading, spacing: 8) {
                    Text(L("اسمك", "Your name")).font(.app(.footnote, .bold)).foregroundColor(Theme.muted).padding(.horizontal, 6)
                    TextField(L("اكتب اسمك", "Type your name"), text: $settings.userName)
                        .font(.app(.body))
                        .focused($editing)
                        .submitLabel(.done)
                        .foregroundColor(Theme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card(padding: 16)
                        .accessibilityIdentifier("field.name")
                    Text(L("يطلع في الترحيب بالرئيسية بعد «صبآح الخير / مسآء الخير».", "Shown in the home greeting."))
                        .font(.app(.caption)).foregroundColor(Theme.muted).padding(.horizontal, 6)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
            .frame(maxWidth: 650)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background.ignoresSafeArea())
        .onTapGesture { editing = false }
    }
}
