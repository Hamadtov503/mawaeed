import SwiftUI

struct AppEntryView: View {
    @ObservedObject private var auth = AuthManager.shared
    @AppStorage("welcomePassed") private var welcomePassed = false

    var body: some View {
        Group {
            if welcomePassed || auth.signedIn || !auth.configured { RootView() }
            else { WelcomeView() }
        }.onAppear { auth.restoreSession() }
    }
}

struct WelcomeView: View {
    @ObservedObject private var auth = AuthManager.shared
    @AppStorage("welcomePassed") private var welcomePassed = false
    @Environment(\.presentationMode) private var presentation
    var fromSettings = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack {
                    Label("موعد", systemImage: "calendar.badge.clock").font(.title3.bold()).foregroundColor(Color.brand)
                    Spacer()
                    Text("كل شيء في وقته").font(.caption).foregroundColor(Theme.muted)
                }.padding(.top, 24)
                ZStack {
                    RoundedRectangle(cornerRadius: 36).fill(Theme.tile)
                    VStack(spacing: 18) {
                        Image(systemName: "calendar.badge.checkmark")
                            .font(.system(size: 70, weight: .light)).foregroundColor(Color.brand)
                        HStack(spacing: 12) {
                            feature("car.fill", "سياراتك")
                            feature("checkmark.shield.fill", "ضماناتك")
                            feature("checklist", "مهامك")
                        }
                    }.padding(28)
                }.frame(minHeight: 235)
                VStack(alignment: .leading, spacing: 12) {
                    Text("راحة بالك،\nتبدأ بموعد.")
                        .font(.system(size: 38, weight: .bold, design: .rounded)).foregroundColor(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("مواعيدك ومهامك وصيانة ممتلكاتك، مرتبة في مكان واحد.")
                        .font(.body).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
                }
                VStack(spacing: 12) {
                    providerButton("المتابعة باستخدام Apple", icon: "apple.logo", provider: "apple")
                    providerButton("المتابعة باستخدام Google", icon: "globe", provider: "google")
                    if auth.busy { ProgressView("جارٍ التحقق من حسابك…") }
                    if !auth.configured {
                        Text("تسجيل الحسابات بانتظار تفعيل الخدمة. تقدر تبدأ الآن على جهازك.")
                            .font(.caption).foregroundColor(Theme.muted).multilineTextAlignment(.center)
                    }
                    Button("المتابعة على هذا الجهاز") {
                        welcomePassed = true
                        if fromSettings { presentation.wrappedValue.dismiss() }
                    }.font(.subheadline.bold()).padding(.vertical, 8)
                }
                Text("بياناتك محفوظة على هذا الجهاز. للمزامنة والنسخ الاحتياطي فعّل iCloud Drive من الإعدادات. تسجيل الحساب وحده لا يرفع بياناتك إلى السحابة.")
                    .font(.caption).foregroundColor(Theme.muted).multilineTextAlignment(.center)
            }.padding(24).frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
        }
        .background(Theme.background.ignoresSafeArea())
        .alert("تسجيل الدخول", isPresented: Binding(get: { auth.errorMessage != nil }, set: { if !$0 { auth.errorMessage = nil } })) {
            Button("تمام") { auth.errorMessage = nil }
        } message: { Text(auth.errorMessage ?? "") }
        .onChange(of: auth.signedIn) { signedIn in
            if signedIn && fromSettings { presentation.wrappedValue.dismiss() }
        }
    }

    private func feature(_ icon: String, _ title: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.title3)
            Text(title).font(.caption)
        }.foregroundColor(Color.brand).frame(maxWidth: .infinity)
    }

    private func providerButton(_ title: String, icon: String, provider: String) -> some View {
        Button { auth.signIn(provider: provider) } label: {
            Label(title, systemImage: icon)
                .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 18)
                .foregroundColor(provider == "apple" ? Theme.card : Theme.ink)
                .background(RoundedRectangle(cornerRadius: 18).fill(provider == "apple" ? Theme.ink : Theme.card))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.border, lineWidth: 1))
        }.disabled(!auth.configured || auth.busy)
        .opacity(!auth.configured ? 0.5 : 1)
    }
}

struct AccountSettingsView: View {
    @ObservedObject private var auth = AuthManager.shared
    @State private var showSignIn = false
    @State private var confirmSignOut = false

    var body: some View {
        Group {
            if auth.signedIn {
                Label(auth.email ?? "حسابك متصل", systemImage: "person.crop.circle.fill")
                Button("تسجيل الخروج من هذا الجهاز", role: .destructive) { confirmSignOut = true }
            } else {
                Button { showSignIn = true } label: { Label("تسجيل الدخول", systemImage: "person.crop.circle") }
            }
            Text("الدخول يعرّف حسابك فقط. البيانات مشتركة بين مستخدمي هذا الجهاز؛ لا توجد مزامنة مرتبطة بحساب Google أو Apple حاليًا.")
                .font(.caption).foregroundColor(.secondary)
        }
        .sheet(isPresented: $showSignIn) { WelcomeView(fromSettings: true) }
        .confirmationDialog("تسجيل الخروج؟", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("تسجيل الخروج", role: .destructive) { auth.signOut() }
        } message: { Text("ستبقى المواعيد والملفات محفوظة على الجهاز ومتاحة عند المتابعة محليًا.") }
    }
}

