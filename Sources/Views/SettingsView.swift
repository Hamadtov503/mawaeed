import SwiftUI
import UniformTypeIdentifiers
import UserNotifications
import EventKit

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var backup: SyncManager
    @Environment(\.dismiss) private var dismiss

    @State private var notifStatus: UNAuthorizationStatus = .notDetermined
    @State private var importMode: ImportMode = .folder
    @State private var showImporter = false
    @State private var showExporter = false
    @State private var exportDoc = BackupDocument(data: Data())
    @State private var pendingRestore: Backup? = nil
    @State private var alert: AlertInfo? = nil

    enum ImportMode { case folder, restore }

    struct AlertInfo: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    /// Settings sub-pages swap in place with a SwiftUI animation instead of a navigation push:
    /// the system push animation drew these pages mirrored in right-to-left.
    enum Page: String, Identifiable {
        case notifications, sync, privacy, more, account
        var id: String { rawValue }
        var title: String {
            switch self {
            case .notifications: return "التنبيهات"
            case .sync: return "المزامنة والنسخ"
            case .privacy: return "الخصوصية"
            case .more: return "تفضيلات إضافية"
            case .account: return "الحساب"
            }
        }
    }

    @State private var page: Page? = nil

    var body: some View {
        AppNavigation {
            ZStack {
                Theme.background.ignoresSafeArea()
                if let p = page {
                    pageContent(p)
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .trailing)))
                        .zIndex(1)
                } else {
                    rootPage
                        .transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity),
                                                removal: .move(edge: .leading).combined(with: .opacity)))
                }
            }
            .navigationTitle(page?.title ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if page != nil {
                        Button { go(nil) } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.backward").font(.body.weight(.semibold))
                                Text("رجوع")
                            }
                        }
                    } else {
                        Button("إغلاق") { dismiss() }
                    }
                }
            }
            .onAppear(perform: refreshStatus)
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: importMode == .folder ? [.folder] : [.json],
                          allowsMultipleSelection: false) { result in
                handleImport(result)
            }
            .fileExporter(isPresented: $showExporter, document: exportDoc, contentType: .json,
                          defaultFilename: "مواعيدي-\(Fmt.fileStamp.string(from: Date()))") { result in
                if case .failure(let e) = result {
                    alert = AlertInfo(title: "ما انحفظ الملف", message: e.localizedDescription)
                }
            }
            .confirmationDialog("استرجاع \(pendingRestore?.items.count ?? 0) عنصر من النسخة",
                                isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }),
                                titleVisibility: .visible) {
                Button("دمج مع الموجود") { restore(replace: false) }
                Button("استبدال كل شي", role: .destructive) { restore(replace: true) }
                Button("إلغاء", role: .cancel) { pendingRestore = nil }
            }
            .alert(item: $alert) { a in
                Alert(title: Text(a.title), message: Text(a.message), dismissButton: .default(Text("تمام")))
            }
        }
        .navigationViewStyle(.stack)
    }

    private func go(_ p: Page?) {
        withAnimation(.easeInOut(duration: 0.28)) { page = p }
        if p != nil { refreshStatus() }
    }

    private var rootPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageHeader(title: "الإعدادات", subtitle: "خلّ التطبيق يشتغل بالطريقة اللي تناسبك")
                tile(.notifications, "التنبيهات", "الأوقات والملخص اليومي", "bell.fill", .orange)
                tile(.sync, "المزامنة والنسخ الاحتياطي",
                     backup.isOn ? "مزامنة iCloud Drive مفعّلة" : "اربط أجهزتك أو احفظ نسخة من بياناتك", "icloud.fill", .blue)
                tile(.privacy, "الخصوصية", "قفل التطبيق", "lock.shield.fill", .teal)
                tile(.more, "تفضيلات إضافية", "العملة والربط مع تطبيقات Apple", "slider.horizontal.3", .indigo)
                if AuthManager.shared.configured {
                    tile(.account, "الحساب", "إدارة تسجيل الدخول", "person.crop.circle.fill", .purple)
                }
                Text("مواعيدي · الإصدار \(version)")
                    .font(.caption).foregroundColor(Theme.muted)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
            }.padding(18).frame(maxWidth: 650).frame(maxWidth: .infinity)
        }
    }

    private func tile(_ p: Page, _ title: String, _ subtitle: String, _ icon: String, _ tint: Color) -> some View {
        Button { go(p) } label: {
            SettingsTile(title: title, subtitle: subtitle, icon: icon, tint: tint)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func pageContent(_ p: Page) -> some View {
        switch p {
        case .notifications: preferencePage { notificationsSection }
        case .sync: preferencePage { backupSection; exportSection }
        case .privacy: preferencePage { privacySection }
        case .more: preferencePage { generalSection; iCloudSection }
        case .account: preferencePage { PrefGroup("الحساب") { AccountSettingsView() } }
        }
    }

    // MARK: Sections

    private func preferencePage<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) { content() }
                .padding(16).frame(maxWidth: 650).frame(maxWidth: .infinity)
        }
        .background(Theme.background.ignoresSafeArea())
    }
        .background(Theme.background.ignoresSafeArea())
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .onAppear(perform: refreshStatus)
    }

    private var notificationsSection: some View {
        PrefGroup("التنبيهات", footer: "ملخص الصباح يجيك كل يوم فيه شي مستحق أو متأخر.") {
            HStack {
                Label("حالة التنبيهات", systemImage: "bell.fill")
                Spacer()
                switch notifStatus {
                case .authorized, .provisional, .ephemeral:
                    Text("شغّالة ✅").foregroundColor(.green)
                case .denied:
                    Button("مقفلة — افتح الإعدادات") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    .foregroundColor(.red)
                default:
                    Button("فعّلها") { NotificationManager.shared.requestAuthorization { _ in refreshStatus() } }
                }
            }
            DatePicker("وقت التنبيه للأشياء بدون وقت", selection: minutesBinding(\.reminderMinutes), displayedComponents: .hourAndMinute)
            Toggle(isOn: $settings.digestEnabled) { Label("ملخص الصباح", systemImage: "sun.max.fill") }
            if settings.digestEnabled {
                DatePicker("وقت الملخص", selection: minutesBinding(\.digestMinutes), displayedComponents: .hourAndMinute)
            }
            Toggle(isOn: $settings.overdueNag) { Label("ألحّ علي إذا تأخرت (7 المساء)", systemImage: "exclamationmark.bubble.fill") }
        }
    }

    private var iCloudSection: some View {
        PrefGroup("الربط مع iCloud", footer: "اعرض مواعيدك ومهامك في تطبيقَي التقويم والتذكيرات من Apple.") {
            Toggle(isOn: Binding(get: { settings.calendarSync }, set: { on in enable(.event, on) })) {
                Label("تقويم iCloud", systemImage: "calendar")
            }
            Toggle(isOn: Binding(get: { settings.remindersSync }, set: { on in enable(.reminder, on) })) {
                Label("تطبيق التذكيرات (للمهام)", systemImage: "checklist")
            }
        }
    }

    private var backupSection: some View {
        PrefGroup("المزامنة بين الأجهزة (iCloud Drive)",
                  footer: backup.isOn
                    ? "التغييرات تتزامن بين الأجهزة المرتبطة بهذا المجلد."
                    : "اختر نفس مجلد iCloud Drive على كل جهاز تبي تزامنه.") {
            if backup.isOn {
                HStack {
                    Label("المجلد", systemImage: "folder.fill")
                    Spacer()
                    Text(backup.folderName ?? "").foregroundColor(.secondary)
                }
                HStack {
                    Label("آخر مزامنة", systemImage: backup.isSyncing ? "arrow.triangle.2.circlepath.icloud" : "checkmark.icloud.fill")
                    Spacer()
                    Text(backup.isSyncing ? "جاري…" : (backup.lastSync.map { Fmt.dateText($0, hasTime: true) } ?? "—"))
                        .foregroundColor(.secondary)
                }
                Button { backup.sync() } label: { Label("زامن الحين", systemImage: "arrow.triangle.2.circlepath") }
                Button { pick(.folder) } label: { Label("غيّر المجلد", systemImage: "folder.badge.gearshape") }
                Button(role: .destructive) { backup.turnOff() } label: {
                    Label("أوقف المزامنة على هالجوال", systemImage: "xmark.icloud")
                }
            } else {
                Button { pick(.folder) } label: {
                    Label("فعّل المزامنة — اختر مجلد في iCloud Drive", systemImage: "icloud.fill")
                }
            }
            if let err = backup.lastError {
                Text(err).font(.footnote).foregroundColor(.orange)
            }
        }
    }

    private var exportSection: some View {
        PrefGroup("نسخة احتياطية يدوية") {
            Button { export() } label: { Label("صدّر نسخة لأي مكان…", systemImage: "square.and.arrow.up") }
            Button { pick(.restore) } label: { Label("استرجع من نسخة…", systemImage: "arrow.down.doc.fill") }
        }
    }

    private var generalSection: some View {
        PrefGroup("عام") {
            HStack {
                Label("العملة", systemImage: "banknote")
                Spacer()
                Picker("العملة", selection: $settings.currency) {
                    ForEach(AppSettings.currencies, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
        }
    }

    private var privacySection: some View {
        PrefGroup("الخصوصية") {
            Toggle(isOn: $settings.lockEnabled) {
                Label("قفل التطبيق بـ \(AppLock.biometryName)", systemImage: "lock.fill")
            }
        }
    }

    // MARK: Actions

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    private func minutesBinding(_ key: ReferenceWritableKeyPath<AppSettings, Int>) -> Binding<Date> {
        Binding(get: { AppSettings.date(fromMinutes: settings[keyPath: key]) },
                set: { settings[keyPath: key] = AppSettings.minutes(from: $0) })
    }

    private func refreshStatus() {
        NotificationManager.shared.status { notifStatus = $0 }
    }

    private func enable(_ type: EKEntityType, _ on: Bool) {
        let apply: (Bool) -> Void = { value in
            if type == .event { settings.calendarSync = value } else { settings.remindersSync = value }
            refreshStatus()
        }
        guard on else { apply(false); return }
        CalendarSync.shared.requestAccess(type) { granted in
            if granted {
                apply(true)
            } else {
                apply(false)
                alert = AlertInfo(title: "ما فيه صلاحية",
                                  message: "افتح الإعدادات ← الخصوصية ← \(type == .event ? "التقويمات" : "التذكيرات") واسمح لـ«مواعيدي» بالوصول الكامل.")
            }
        }
    }

    private func pick(_ mode: ImportMode) {
        importMode = mode
        // Let SwiftUI pick up the new content types before presenting.
        DispatchQueue.main.async { showImporter = true }
    }

    private func export() {
        do {
            exportDoc = BackupDocument(data: try Backup.make(items: store.items).encoded())
            showExporter = true
        } catch {
            alert = AlertInfo(title: "ما قدرت أجهّز النسخة", message: error.localizedDescription)
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let e):
            alert = AlertInfo(title: "ما انفتح", message: e.localizedDescription)
        case .success(let urls):
            guard let url = urls.first else { return }
            if importMode == .folder {
                backup.setFolder(url)
            } else {
                do {
                    pendingRestore = try backup.readBackup(at: url)
                } catch {
                    alert = AlertInfo(title: "الملف ما ينقرأ", message: "تأكد إنه نسخة من مواعيدي.\n\(error.localizedDescription)")
                }
            }
        }
    }

    private func restore(replace: Bool) {
        guard let b = pendingRestore else { return }
        guard store.restore(b, replace: replace) else {
            pendingRestore = nil
            alert = AlertInfo(title: "لم يتم الاسترجاع", message: AssetStore.shared.errorMessage ?? "تعذّر حفظ الممتلكات.")
            return
        }
        pendingRestore = nil
        alert = AlertInfo(title: "تم الاسترجاع ✅", message: "رجّعت \(b.items.count) عنصر.")
    }
}




/// A titled card of settings rows, used instead of Form sections.
struct PrefGroup<Content: View>: View {
    let title: String
    var footer: String? = nil
    let content: Content

    init(_ title: String, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.footnote.bold()).foregroundColor(Theme.muted).padding(.horizontal, 6)
            VStack(alignment: .leading, spacing: 16) { content }
                .buttonStyle(.borderless)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(padding: 16)
            if let f = footer, !f.isEmpty {
                Text(f).font(.caption).foregroundColor(Theme.muted).padding(.horizontal, 6)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
