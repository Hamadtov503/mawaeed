import SwiftUI
import UniformTypeIdentifiers
import UserNotifications
import EventKit

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var backup: SyncManager

    @State private var notifStatus: UNAuthorizationStatus = .notDetermined
    @State private var importMode: ImportMode = .folder
    @State private var showImporter = false
    @State private var showExporter = false
    @State private var exportDoc = BackupDocument(data: Data())
    @State private var pendingRestore: Backup? = nil
    @State private var alert: AlertInfo? = nil
    @State private var calendarAccount: String? = nil

    enum ImportMode { case folder, restore }

    struct AlertInfo: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    var body: some View {
        NavigationView {
            Form {
                notificationsSection
                iCloudSection
                backupSection
                generalSection
                exportSection
                privacySection
                aboutSection
            }
            .themedList()
            .navigationTitle("الإعدادات")
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

    // MARK: Sections

    private var notificationsSection: some View {
        Section(header: Text("التنبيهات"),
                footer: Text("ملخص الصباح يجيك كل يوم فيه شي مستحق أو متأخر.")) {
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
            Button { NotificationManager.shared.sendTest() } label: {
                Label("جرّب تنبيه (بعد 5 ثواني)", systemImage: "paperplane.fill")
            }
        }
    }

    private var iCloudSection: some View {
        Section(header: Text("الربط مع iCloud"),
                footer: Text("يضيف مواعيدك في تقويم اسمه «مواعيدي» داخل حساب iCloud، والمهام في قائمة «مواعيدي» في تطبيق التذكيرات — فتشوفها في الماك والآيباد والساعة. لو علّمت مهمة منجزة في التذكيرات، تنعلّم هنا بعد.")) {
            Toggle(isOn: Binding(get: { settings.calendarSync }, set: { on in enable(.event, on) })) {
                Label("تقويم iCloud", systemImage: "calendar")
            }
            Toggle(isOn: Binding(get: { settings.remindersSync }, set: { on in enable(.reminder, on) })) {
                Label("تطبيق التذكيرات (للمهام)", systemImage: "checklist")
            }
            if settings.calendarSync, let acc = calendarAccount {
                HStack {
                    Text("الحساب").foregroundColor(.secondary)
                    Spacer()
                    Text(acc)
                }
                .font(.footnote)
            }
        }
    }

    private var backupSection: some View {
        Section(header: Text("المزامنة بين الأجهزة (iCloud Drive)"),
                footer: Text(backup.isOn
                             ? "أي تعديل ينحفظ في المجلد، والأجهزة الثانية تسحبه أول ما تفتح التطبيق وكل 30 ثانية وهو مفتوح."
                             : "عشان تفتح نفس البيانات من جوال ثاني: اختر هنا مجلد في iCloud Drive (مثلاً سوّ مجلد اسمه «مواعيدي»)، وفي الجوال الثاني ثبّت التطبيق واختر نفس المجلد. لو الجوال الثاني بحساب Apple ثاني، شارك المجلد معه من تطبيق الملفات.")) {
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
                if let other = backup.otherDevice {
                    HStack {
                        Label("آخر تعديل من", systemImage: "iphone")
                        Spacer()
                        Text(other).foregroundColor(.secondary)
                    }
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
        Section(header: Text("نسخة احتياطية يدوية")) {
            Button { export() } label: { Label("صدّر نسخة لأي مكان…", systemImage: "square.and.arrow.up") }
            Button { pick(.restore) } label: { Label("استرجع من نسخة…", systemImage: "arrow.down.doc.fill") }
        }
    }

    private var generalSection: some View {
        Section(header: Text("عام")) {
            Picker(selection: $settings.currency) {
                ForEach(AppSettings.currencies, id: \.self) { Text($0).tag($0) }
            } label: {
                Label("العملة", systemImage: "banknote")
            }
        }
    }

    private var privacySection: some View {
        Section(header: Text("الخصوصية")) {
            Toggle(isOn: $settings.lockEnabled) {
                Label("قفل التطبيق بـ \(AppLock.biometryName)", systemImage: "lock.fill")
            }
        }
    }

    private var aboutSection: some View {
        Section {
            HStack {
                Text("العناصر")
                Spacer()
                Text("\(store.items.filter { !$0.isDone }.count) نشطة • \(store.items.filter { $0.isDone }.count) منجزة")
                    .foregroundColor(.secondary)
            }
            HStack {
                Text("الإصدار")
                Spacer()
                Text(version).foregroundColor(.secondary)
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
        calendarAccount = settings.calendarSync ? CalendarSync.shared.calendarAccountName : nil
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
        store.restore(b, replace: replace)
        pendingRestore = nil
        alert = AlertInfo(title: "تم الاسترجاع ✅", message: "رجّعت \(b.items.count) عنصر.")
    }
}

