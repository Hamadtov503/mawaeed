import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

/// One scrolling page of grouped cards — no sub-pages, so nothing is pushed.
struct SettingsView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var sync: SyncManager

    @State private var notifStatus: UNAuthorizationStatus = .notDetermined
    @State private var importMode: ImportMode = .folder
    @State private var showImporter = false
    @State private var showExporter = false
    @State private var exportDoc = BackupDocument(data: Data())
    @State private var pendingRestore: [Appointment]? = nil
    @State private var alert: AlertInfo? = nil
    @State private var calendarAccount: String? = nil

    enum ImportMode { case folder, restore }

    struct AlertInfo: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("الإعدادات").font(.system(size: 32, weight: .bold)).foregroundColor(Theme.ink).padding(.top, 8)
                notifications
                syncGroup
                calendarGroup
                backupGroup
                Text("مواعيدي · الإصدار \(version)")
                    .font(.caption).foregroundColor(Theme.muted)
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
            .frame(maxWidth: 650)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background.ignoresSafeArea())
        .onAppear(perform: refresh)
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: importMode == .folder ? [.folder] : [.json],
                      allowsMultipleSelection: false) { handleImport($0) }
        .fileExporter(isPresented: $showExporter, document: exportDoc, contentType: .json,
                      defaultFilename: "مواعيدي-\(Fmt.fileStamp.string(from: Date()))") { result in
            if case .failure(let e) = result { alert = AlertInfo(title: "ما انحفظ الملف", message: e.localizedDescription) }
        }
        .confirmationDialog("استرجاع \(pendingRestore?.count ?? 0) موعد من النسخة",
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

    // MARK: Groups

    private var notifications: some View {
        SettingsGroup(title: "التنبيهات", footer: "ملخص الصباح يجيك الأيام اللي فيها مواعيد.") {
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
                    Button("فعّلها") { NotificationManager.shared.requestAuthorization { _ in refresh() } }
                }
            }
            Toggle(isOn: $settings.digestEnabled) { Label("ملخص الصباح", systemImage: "sun.max.fill") }
            if settings.digestEnabled {
                DatePicker("وقت الملخص", selection: minutes(\.digestMinutes), displayedComponents: .hourAndMinute)
            }
            DatePicker("تنبيه المواعيد اللي بدون وقت", selection: minutes(\.reminderMinutes), displayedComponents: .hourAndMinute)
            Button { NotificationManager.shared.sendTest() } label: {
                Label("جرّب تنبيه (بعد 5 ثواني)", systemImage: "paperplane.fill")
            }
        }
    }

    private var syncGroup: some View {
        SettingsGroup(title: "المزامنة بين الأجهزة",
              footer: sync.isOn
                ? "أي تعديل ينحفظ في المجلد، والجوال الثاني يسحبه أول ما تفتح التطبيق وكل 30 ثانية وهو مفتوح."
                : "عشان نفس المواعيد تطلع في جوال ثاني: اختر مجلد في iCloud Drive هنا، وفي الجوال الثاني اختر نفس المجلد.") {
            if sync.isOn {
                info("folder.fill", "المجلد", sync.folderName ?? "")
                info(sync.isSyncing ? "arrow.triangle.2.circlepath.icloud" : "checkmark.icloud.fill", "آخر مزامنة",
                     sync.isSyncing ? "جاري…" : (sync.lastSync.map { Fmt.dateText($0, hasTime: true) } ?? "—"))
                Button { sync.sync() } label: { Label("زامن الحين", systemImage: "arrow.triangle.2.circlepath") }
                Button { pick(.folder) } label: { Label("غيّر المجلد", systemImage: "folder.badge.gearshape") }
                Button(role: .destructive) { sync.turnOff() } label: {
                    Label("أوقف المزامنة على هالجوال", systemImage: "xmark.icloud").foregroundColor(.red)
                }
            } else {
                Button { pick(.folder) } label: { Label("فعّل المزامنة — اختر مجلد في iCloud Drive", systemImage: "icloud.fill") }
            }
            if let e = sync.lastError { Text(e).font(.footnote).foregroundColor(.orange) }
        }
    }

    private var calendarGroup: some View {
        SettingsGroup(title: "تقويم iCloud", footer: "يضيف مواعيدك في تقويم اسمه «مواعيدي» في حسابك، فتشوفها في تطبيق التقويم بالجوال والماك والساعة.") {
            Toggle(isOn: Binding(get: { settings.calendarSync }, set: { enableCalendar($0) })) {
                Label("اعرض مواعيدي في التقويم", systemImage: "calendar")
            }
            if settings.calendarSync, let acc = calendarAccount {
                info("person.crop.circle", "الحساب", acc)
            }
        }
    }

    private var backupGroup: some View {
        SettingsGroup(title: "نسخة احتياطية يدوية", footer: nil) {
            Button { export() } label: { Label("صدّر نسخة لأي مكان…", systemImage: "square.and.arrow.up") }
            Button { pick(.restore) } label: { Label("استرجع من نسخة…", systemImage: "arrow.down.doc.fill") }
        }
    }

    private func info(_ icon: String, _ title: String, _ value: String) -> some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            Text(value).foregroundColor(Theme.muted).lineLimit(1)
        }
    }

    // MARK: Actions

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    private func minutes(_ key: ReferenceWritableKeyPath<AppSettings, Int>) -> Binding<Date> {
        Binding(get: { AppSettings.date(fromMinutes: settings[keyPath: key]) },
                set: { settings[keyPath: key] = AppSettings.minutes(from: $0) })
    }

    private func refresh() {
        NotificationManager.shared.status { notifStatus = $0 }
        calendarAccount = settings.calendarSync ? CalendarSync.shared.accountName : nil
    }

    private func enableCalendar(_ on: Bool) {
        guard on else { settings.calendarSync = false; refresh(); return }
        CalendarSync.shared.requestAccess { granted in
            settings.calendarSync = granted
            refresh()
            if !granted {
                alert = AlertInfo(title: "ما فيه صلاحية",
                                  message: "افتح إعدادات الجوال ← الخصوصية ← التقويمات، واسمح لـ«مواعيدي» بالوصول الكامل.")
            }
        }
    }

    private func pick(_ mode: ImportMode) {
        importMode = mode
        DispatchQueue.main.async { showImporter = true }
    }

    private func export() {
        do {
            let file = SyncFile(items: store.items.map { var a = $0; a.calendarEventID = nil; return a }, deleted: nil)
            exportDoc = BackupDocument(data: try Store.encoder.encode(file))
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
                sync.setFolder(url)
            } else {
                do {
                    pendingRestore = try sync.readBackup(at: url).filter { $0.isAppointment }
                } catch {
                    alert = AlertInfo(title: "الملف ما ينقرأ", message: "تأكد إنه نسخة من مواعيدي.\n\(error.localizedDescription)")
                }
            }
        }
    }

    private func restore(replace: Bool) {
        guard let list = pendingRestore else { return }
        store.restore(list, replace: replace)
        pendingRestore = nil
        alert = AlertInfo(title: "تم الاسترجاع ✅", message: "رجّعت \(list.count) موعد.")
    }
}

/// A titled card of settings rows.
private struct SettingsGroup<Content: View>: View {
    let title: String
    let footer: String?
    let content: Content

    init(title: String, footer: String?, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.footnote.bold()).foregroundColor(Theme.muted).padding(.horizontal, 6)
            VStack(alignment: .leading, spacing: 16) { content }
                .buttonStyle(.borderless)
                .foregroundColor(Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(padding: 16)
            if let f = footer {
                Text(f).font(.caption).foregroundColor(Theme.muted).padding(.horizontal, 6)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
