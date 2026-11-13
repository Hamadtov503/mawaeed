import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

/// One scrolling page of grouped cards — no sub-pages, so nothing is pushed.
struct SettingsView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var sync: SyncManager

    @State private var importMode: ImportMode = .folder
    @State private var picker: PickerRequest? = nil
    @State private var pendingRestore: (items: [Appointment], tasks: [TaskItem])? = nil
    @State private var menu: MenuRequest? = nil
    @State private var calendarAccount: String? = nil

    enum ImportMode { case folder, restore }

    /// One Files picker at a time: choosing the sync folder, a backup to restore, or where to save a backup.
    struct PickerRequest: Identifiable {
        let id = UUID()
        let mode: DocumentPicker.Mode
    }

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
                syncGroup
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
        .sheet(item: $picker) { req in
            DocumentPicker(mode: req.mode) { urls in
                if case .open = req.mode { handleImport(.success(urls)) }
            }
            .ignoresSafeArea()
        }
        .actionMenu($menu)
    }

    // MARK: Groups

    private var syncGroup: some View {
        SettingsGroup(title: L("المزامنة مع آي كلاود", "iCloud sync"),
              footer: sync.isOn
                ? L("أي تعديل ينحفظ في المجلد، والجوال الثاني يسحبه أول ما تفتح التطبيق وكل 30 ثانية وهو مفتوح.", "Every change is saved to the folder; the other phone picks it up when the app opens and every 30 seconds while open.")
                : L("مواعيدك ومهامك تنحفظ في ملف داخل آي كلاود درايف حقك، فتبقى لو غيرت جوالك وتطلع في جوال ثاني. اختر مجلد هنا، وفي الجوال الثاني اختر نفس المجلد.", "Your appointments and tasks are kept in a file in your own iCloud Drive, so they survive a new phone and show on another one. Pick a folder here, and the same folder on the other phone.")) {
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
                Button { pick(.folder) } label: { Label(L("فعّل المزامنة واختر مجلد في آي كلاود درايف", "Turn on sync and pick an iCloud Drive folder"), systemImage: "icloud.fill") }
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
                menu = .notice(L("ما فيه صلاحية", "No access"),
                                  message: L("افتح إعدادات الجوال ← الخصوصية ← التقويمات، واسمح لـ«مواعيدي» بالوصول الكامل.", "Open Settings → Privacy → Calendars and give Mawaeed full access."))
            }
        }
    }

    private func pick(_ mode: ImportMode) {
        importMode = mode
        guard mode == .folder else {
            picker = PickerRequest(mode: .open([.json]))
            return
        }
        // iOS's folder picker looks like a file browser, so say how it works before opening it.
        menu = MenuRequest(
            title: L("اختيار مجلد المزامنة", "Choosing the sync folder"),
            message: L("بتنفتح شاشة الملفات: اختر iCloud Drive، وادخل للمجلد اللي تبيه (أو سوّ مجلد جديد من زر ⋯)، وأنت داخله اضغط «فتح» فوق.",
                       "The Files screen opens: choose iCloud Drive, go into the folder you want (or make a new one from ⋯), and while inside it tap «Open» at the top."),
            actions: [
                MenuAction(title: L("متابعة", "Continue"), icon: "folder") {
                    picker = PickerRequest(mode: .open([.folder]))
                },
                MenuAction(title: L("إلغاء", "Cancel"), icon: "xmark") {},
            ])
    }

    private func export() {
        do {
            let file = SyncFile(items: store.items.map { var a = $0; a.calendarEventID = nil; return a }, tasks: store.tasks, deleted: nil)
            // Written to a temporary file named after today, then handed to the Files picker to save a copy.
            let name = L("مواعيدي-\(Fmt.fileStamp.string(from: Date()))", "Mawaeed-\(Fmt.fileStamp.string(from: Date()))") + ".json"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try Store.encoder.encode(file).write(to: url, options: .atomic)
            picker = PickerRequest(mode: .export(url))
        } catch {
            menu = .notice(L("ما قدرت أجهّز النسخة", "Couldn't prepare the copy"), message: error.localizedDescription)
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let e):
            menu = .notice(L("ما انفتح", "Couldn't open"), message: e.localizedDescription)
        case .success(let urls):
            guard let url = urls.first else { return }
            if importMode == .folder {
                sync.setFolder(url)
            } else {
                do {
                    let b = try sync.readBackup(at: url)
                    pendingRestore = (b.items.filter { $0.isAppointment }, b.tasks)
                    let n = pendingRestore!
                    menu = MenuRequest(title: L("استرجاع \(Fmt.appointments(n.items.count)) و\(Fmt.tasks(n.tasks.count)) من النسخة", "Restore \(Fmt.appointments(n.items.count)) and \(Fmt.tasks(n.tasks.count)) from the copy"), actions: [
                        MenuAction(title: L("دمج مع الموجود", "Merge with current"), icon: "arrow.triangle.merge") { restore(replace: false) },
                        MenuAction(title: L("استبدال كل شي", "Replace everything"), icon: "arrow.2.squarepath", destructive: true) { restore(replace: true) },
                        MenuAction(title: L("إلغاء", "Cancel"), icon: "xmark") { pendingRestore = nil },
                    ])
                } catch {
                    menu = .notice(L("الملف ما ينقرأ", "Can't read the file"), message: L("تأكد إنه نسخة من مواعيدي.\n\(error.localizedDescription)", "Make sure it's a Mawaeed backup.\n\(error.localizedDescription)"))
                }
            }
        }
    }

    private func restore(replace: Bool) {
        guard let b = pendingRestore else { return }
        store.restore(b.items, tasks: b.tasks, replace: replace)
        pendingRestore = nil
        menu = .notice(L("تم الاسترجاع ✅", "Restored ✅"), message: L("رجّعت \(Fmt.appointments(b.items.count)) و\(Fmt.tasks(b.tasks.count)).", "Restored \(Fmt.appointments(b.items.count)) and \(Fmt.tasks(b.tasks.count))."))
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
