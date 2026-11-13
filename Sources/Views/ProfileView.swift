import SwiftUI

/// Your profile, opened from the person button on home: your picture and your name (shown in the
/// home greeting). Tap the picture to choose one from Photos; long-press it to remove it.
struct ProfileView: View {
    @EnvironmentObject var settings: AppSettings
    @FocusState private var editing: Bool
    @State private var choosingPhoto = false
    @State private var menu: MenuRequest? = nil

    private var name: String { settings.userName.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 10) {
                    ProfileBadge(size: 104)
                        .overlay(alignment: .bottomTrailing) {
                            // A small camera on the corner: this picture can be changed.
                            Image(systemName: "camera.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(Theme.navy))
                                .overlay(Circle().stroke(Theme.background, lineWidth: 3))
                        }
                        .contentShape(Circle())
                        .onTapGesture { choosingPhoto = true }
                        .onLongPress {
                            guard settings.profileImage != nil else { return }
                            menu = MenuRequest(actions: [
                                MenuAction(title: L("غيّر الصورة", "Change picture"), icon: "photo") { choosingPhoto = true },
                                MenuAction(title: L("احذف الصورة", "Remove picture"), icon: "trash", destructive: true) {
                                    withAnimation(Router.soft) { settings.profileImage = nil }
                                },
                            ])
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityLabel(L("صورتك", "Your picture"))
                        .accessibilityIdentifier("profile.photo")
                    Text(settings.profileImage == nil ? L("اضغط لإضافة صورة", "Tap to add a picture") : L("اضغط لتغيير الصورة، واضغط مطولاً لحذفها", "Tap to change, long-press to remove"))
                        .font(.app(.caption)).foregroundColor(Theme.muted)
                }
                .padding(.top, 10)

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
                    Text(L("يظهر في الترحيب بالصفحة الرئيسية بعد «صبآح الخير / مسآء الخير».", "Shown in the home greeting."))
                        .font(.app(.caption)).foregroundColor(Theme.muted).padding(.horizontal, 6)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
            .frame(maxWidth: 650)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background.ignoresSafeArea().onTapGesture { editing = false })
        .sheet(isPresented: $choosingPhoto) {
            PhotoPicker { image in
                if let data = IconImage.make(from: image, size: 360) {
                    withAnimation(Router.soft) { settings.profileImage = data }
                }
            }
            .ignoresSafeArea()
        }
        .actionMenu($menu, top: 150)
    }
}

/// Your picture in a circle, or the first letter of your name, or a person mark.
struct ProfileBadge: View {
    @EnvironmentObject var settings: AppSettings
    let size: CGFloat

    var body: some View {
        let name = settings.userName.trimmingCharacters(in: .whitespaces)
        ZStack {
            if let data = settings.profileImage, let ui = UIImage(data: data) {
                Image(uiImage: ui).resizable().scaledToFill()
            } else {
                Circle().fill(LinearGradient(colors: [Theme.burgundy, Theme.burgundy.opacity(0.8)], startPoint: .top, endPoint: .bottom))
                if let first = name.first {
                    Text(String(first)).font(.app(size: size * 0.4, .bold)).foregroundColor(.white)
                } else {
                    Image(systemName: "person.fill").font(.system(size: size * 0.38)).foregroundColor(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .shadow(color: Theme.burgundy.opacity(size > 60 ? 0.3 : 0), radius: 10, y: 5)
        .animation(Router.soft, value: settings.profileImage)
        .animation(Router.soft, value: name)
    }
}
