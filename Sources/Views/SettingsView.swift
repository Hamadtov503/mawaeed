import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

/// One scrolling page of grouped cards — no sub-pages, so nothing is pushed.
struct SettingsView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var sync: SyncManager

    @State private var importMode: ImportMode = .folder
    @State private var showImporter = false
    @State private var showExporter = false
    @State private var exportDoc = BackupDocument(data: Data())
    @State private var pendingRestore: (items: [Appointment], tasks: [TaskItem])? = nil
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
                SettingsGroup(title: L("اللغة", "Language"), footer: nil) {
                    HStack(spacing: 8) {
                        ForEach(AppLanguage.allCases) { lang in
                            Chip(title: lang.title, selected: settings.language == lang) {
                                guard settings.language != lang else { return }
                                withAnimation(.easeInOut(duration: 0.3)) { settings.language = lang }
                            }
                        }
                    }
                }
                SettingsGroup(title: L("اسمك", "Your name"), footer: L("يطلع في الترحيب بالرئيسية بعد «صباح الخير / مساء الخير».", "Shown in the home greeting.")) {
                    TextField(L("اكتب اسمك", "Type your name"), text: $settings.userName).font(.app(.body))
                }
                calendarGroup
                backupGroup
                Text(L("مواعيدي — الإصدار \(version)", "Mawaeed · Version \(version)"))
                    .font(.app(.caption)).foregroundColor(Theme.muted)
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .padding(.horizontal, 18)
            .padding(.top, 6)
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
                      defaultFilename: L("مواعيدي-\(Fmt.fileStamp.string(from: Date()))", "Mawaeed-\(Fmt.fileStamp.string(from: Date()))")) { result in
            if case .failure(let e) = result { alert = AlertInfo(title: L("ما انحفظ الملف", "The file wasn't saved"), message: e.localizedDescription) }
        }
        .confirmationDialog(L("استرجاع \(Fmt.appointments(pendingRestore?.items.count ?? 0)) و\(Fmt.tasks(pendingRestore?.tasks.count ?? 0)) من النسخة", "Restore \(Fmt.appointments(pendingRestore?.items.count ?? 0)) and \(Fmt.tasks(pendingRestore?.tasks.count ?? 0)) from the copy"),
                            isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }),
                            titleVisibility: .visible) {
            Button(L("دمج مع الموجود", "Merge with current")) { restore(replace: false) }
            Button(L("استبدال كل شي", "Replace everything"), role: .destructive) { restore(replace: true) }
            Button(L("إلغاء", "Cancel"), role: .cancel) { pendingRestore = nil }
        }
        .alert(item: $alert) { a in
            Alert(title: Text(a.title), message: Text(a.message), dismissButton: .default(Text(L("تمام", "OK"))))
        }
    }

    // MARK: Groups

    private var syncGroup: some View {
        SettingsGroup(title: L("المزامنة بين الأجهزة", "Sync between devices"),
              footer: sync.isOn
                ? L("أي تعديل ينحفظ في المجلد، والجوال الثاني يسحبه أول ما تفتح التطبيق وكل 30 ثانية وهو مفتوح.", "Every change is saved to the folder; the other phone picks it up when the app opens and every 30 seconds while open.")
                : L("عشان نفس المواعيد تطلع في جوال ثاني: اختر مجلد في iCloud Drive هنا، وفي الجوال الثاني اختر نفس المجلد.", "To see the same data on another phone: pick a folder in iCloud Drive here, and the same folder on the other phone.")) {
            if sync.isOn {
                info("folder.fill", L("المجلد", "Folder"), sync.folderName ?? "")
                info(sync.isSyncing ? "arrow.triangle.2.circlepath.icloud" : "checkmark.icloud.fill", L("آخر مزامنة", "Last sync"),
                     sync.isSyncing ? L("جاري…", "Syncing…") : (sync.lastSync.map { Fmt.dateText($0, hasTime: true) } ?? "—"))
                Button { sync.sync() } label: { Label(L("زامن الحين", "Sync now"), systemImage: "arrow.triangle.2.circlepath") }
                Button { pick(.folder) } label: { Label(L("غيّر المجلد", "Change folder"), systemImage: "folder.badge.gearshape") }
                Button(role: .destructive) { sync.turnOff() } label: {
                    Label(L("أوقف المزامنة على هالجوال", "Stop syncing on this phone"), systemImage: "xmark.icloud").foregroundColor(.red)
                }
            } else {
                Button { pick(.folder) } label: { Label(L("فعّل المزامنة — اختر مجلد في iCloud Drive", "Turn on sync — pick an iCloud Drive folder"), systemImage: "icloud.fill") }
            }
            if let e = sync.lastError { Text(e).font(.app(.footnote)).foregroundColor(.orange) }
        }
    }

    private var calendarGroup: some View {
        SettingsGroup(title: L("التقويم", "Calendar"), footer: nil) {
            Toggle(isOn: Binding(get: { settings.calendarSync }, set: { enableCalendar($0) })) {
                Label(L("زامن مواعيدك مع تقويم الجهاز", "Sync your appointments with the device calendar"), systemImage: "calendar")
            }
        }
    }

    private var backupGroup: some View {
        SettingsGroup(title: L("نسخة احتياطية يدوية", "Manual backup"), footer: nil) {
            Button { export() } label: { Label(L("صدّر نسخة لأي مكان…", "Export a copy…"), systemImage: "square.and.arrow.up") }
            Button { pick(.restore) } label: { Label(L("استرجع من نسخة…", "Restore from a copy…"), systemImage: "arrow.down.doc.fill") }
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
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "0.1"
        let b = info?["CFBundleVersion"] as? String ?? "1"
        let channel = (info?["MawaeedChannel"] as? String).map { $0.isEmpty ? "" : " \($0)" } ?? ""
        return "\(v)\(channel) (\(b))"
    }

    private func minutes(_ key: ReferenceWritableKeyPath<AppSettings, Int>) -> Binding<Date> {
        Binding(get: { AppSettings.date(fromMinutes: settings[keyPath: key]) },
                set: { settings[keyPath: key] = AppSettings.minutes(from: $0) })
    }

    private func refresh() {
        calendarAccount = settings.calendarSync ? CalendarSync.shared.accountName : nil
    }

    private func enableCalendar(_ on: Bool) {
        guard on else { settings.calendarSync = false; refresh(); return }
        CalendarSync.shared.requestAccess { granted in
            settings.calendarSync = granted
            refresh()
            if !granted {
                alert = AlertInfo(title: L("ما فيه صلاحية", "No access"),
                                  message: L("افتح إعدادات الجوال ← الخصوصية ← التقويمات، واسمح لـ«مواعيدي» بالوصول الكامل.", "Open Settings → Privacy → Calendars and give Mawaeed full access."))
            }
        }
    }

    private func pick(_ mode: ImportMode) {
        importMode = mode
        DispatchQueue.main.async { showImporter = true }
    }

    private func export() {
        do {
            let file = SyncFile(items: store.items.map { var a = $0; a.calendarEventID = nil; return a }, tasks: store.tasks, deleted: nil)
            exportDoc = BackupDocument(data: try Store.encoder.encode(file))
            showExporter = true
        } catch {
            alert = AlertInfo(title: L("ما قدرت أجهّز النسخة", "Couldn't prepare the copy"), message: error.localizedDescription)
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let e):
            alert = AlertInfo(title: L("ما انفتح", "Couldn't open"), message: e.localizedDescription)
        case .success(let urls):
            guard let url = urls.first else { return }
            if importMode == .folder {
                sync.setFolder(url)
            } else {
                do {
                    let b = try sync.readBackup(at: url)
                    pendingRestore = (b.items.filter { $0.isAppointment }, b.tasks)
                } catch {
                    alert = AlertInfo(title: L("الملف ما ينقرأ", "Can't read the file"), message: L("تأكد إنه نسخة من مواعيدي.\n\(error.localizedDescription)", "Make sure it's a Mawaeed backup.\n\(error.localizedDescription)"))
                }
            }
        }
    }

    private func restore(replace: Bool) {
        guard let b = pendingRestore else { return }
        store.restore(b.items, tasks: b.tasks, replace: replace)
        pendingRestore = nil
        alert = AlertInfo(title: L("تم الاسترجاع ✅", "Restored ✅"), message: L("رجّعت \(Fmt.appointments(b.items.count)) و\(Fmt.tasks(b.tasks.count)).", "Restored \(Fmt.appointments(b.items.count)) and \(Fmt.tasks(b.tasks.count))."))
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
            Text(title).font(.app(.footnote, .bold)).foregroundColor(Theme.muted).padding(.horizontal, 6)
            VStack(alignment: .leading, spacing: 16) { content }
                .buttonStyle(.borderless)
                .foregroundColor(Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(padding: 16)
            if let f = footer {
                Text(f).font(.app(.caption)).foregroundColor(Theme.muted).padding(.horizontal, 6)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
