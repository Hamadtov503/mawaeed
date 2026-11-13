import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

/// One scrolling page of grouped cards — no sub-pages, so nothing is pushed.
struct SettingsView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var sync: SyncManager

    @State private var importMode: ImportMode = .syncFile
    @State private var picker: PickerRequest? = nil
    @State private var pendingRestore: (items: [Appointment], tasks: [TaskItem])? = nil
    @State private var menu: MenuRequest? = nil
    @State private var calendarAccount: String? = nil
    @State private var syncingByHand = false
    @State private var spinning = false
    @State private var syncStarted = Date()
    /// The word shown on the «زامِن الآن» line once a sync by hand ends: true = done, false = failed.
    @State private var syncResult: Bool? = nil

    enum ImportMode { case syncFile, restore }

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
                calendarGroup
                syncGroup
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
                switch req.mode {
                case .open: handleImport(.success(urls))
                case .move: if let u = urls.first { sync.setFolder(u) }   // the sync file, now in iCloud Drive
                case .export: break
                }
            }
            .ignoresSafeArea()
        }
        .actionMenu($menu)
        // A sync by hand ends with a word on the same line: «تمت المزامنة» in green, or a failure in red.
        .onChange(of: sync.isSyncing) { busy in
            guard !busy, syncingByHand else { return }
            finishSync()
        }
    }

    private func syncNow() {
        // No sync file yet: make a new one (the same as «تصدير»).
        guard sync.isOn else { startSync(); return }
        guard !spinning else { return }
        syncResult = nil
        syncStarted = Date()
        spinning = true
        syncingByHand = true
        sync.sync()
        if !sync.isSyncing { finishSync() }   // nothing started (the file couldn't be reached)
    }

    /// Stops the spinning arrows (after at least a full turn, so a quick sync is still seen) and shows the result.
    private func finishSync() {
        syncingByHand = false
        let wait = max(0, 0.9 - Date().timeIntervalSince(syncStarted))
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
            spinning = false
            withAnimation(.easeOut(duration: 0.25)) { syncResult = sync.lastError == nil }
            let shown = syncResult
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                if shown == true, syncResult == shown { withAnimation(.easeIn(duration: 0.4)) { syncResult = nil } }
            }
        }
    }

    // MARK: Groups

    private var syncGroup: some View {
        SettingsGroup(title: L("المزامنة مع آي كلاود", "iCloud sync"), footer: nil) {
            // Three clearly different marks, each in its own colour.
            Button { syncNow() } label: { syncRow }
            Button { pick(.syncFile) } label: { row(L("استيراد", "Import"), "arrow.down.doc.fill", Theme.forest) }
            Button { startSync() } label: { row(L("تصدير", "Export"), "paperplane.fill", Theme.burgundy) }
        }
    }

    private var calendarGroup: some View {
        SettingsGroup(title: L("التقويم", "Calendar"), footer: nil) {
            Toggle(isOn: Binding(get: { settings.calendarSync }, set: { enableCalendar($0) })) {
                Label(L("مزامنة المواعيد مع تقويم الجهاز", "Sync your appointments with the device calendar"), systemImage: "calendar")
            }
        }
    }

    private var backupGroup: some View {
        SettingsGroup(title: L("النسخ الاحتياطي", "Backup"), footer: nil) {
            Button { export() } label: { Label(L("تصدير نسخة احتياطية", "Export a backup"), systemImage: "externaldrive.badge.plus") }
            Button { pick(.restore) } label: { Label(L("استيراد نسخة احتياطية", "Import a backup"), systemImage: "externaldrive.badge.checkmark") }
        }
    }

    /// «زامِن الآن»: the arrows turn while syncing; then «تمت المزامنة» in green (or a failure in red) on the same line.
    private var syncRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Theme.navy)
                .rotationEffect(.degrees(spinning ? 360 : 0))
                .animation(spinning ? .linear(duration: 0.9).repeatForever(autoreverses: false) : .easeOut(duration: 0.2), value: spinning)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.navy.opacity(0.12)))
            Text(L("زامِن الآن", "Sync now")).foregroundColor(Theme.ink)
            Spacer(minLength: 8)
            if let ok = syncResult {
                Text(ok ? L("تمت المزامنة", "Synced") : L("تعذّرت المزامنة ⓘ", "Sync failed ⓘ"))
                    .font(.app(.subheadline, .semibold))
                    .foregroundColor(ok ? Theme.forest : Theme.burgundy)
                    .transition(.opacity)
                    // A failure can be tapped for the reason.
                    .onTapGesture {
                        guard !ok, let e = sync.lastError else { return }
                        menu = .notice(L("لم تكتمل المزامنة", "Sync didn't finish"), message: e)
                    }
            }
        }
        .contentShape(Rectangle())
    }

    /// A settings row: a coloured mark in a soft square, then the title.
    private func row(_ title: String, _ icon: String, _ color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(color.opacity(0.12)))
            Text(title).foregroundColor(Theme.ink)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
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
                menu = .notice(L("لا توجد صلاحية", "No access"),
                                  message: L("افتح إعدادات الجهاز ← الخصوصية ← التقويمات، واسمح لتطبيق «مواعيدي» بالوصول الكامل.", "Open Settings → Privacy → Calendars and give Mawaeed full access."))
            }
        }
    }

    private func pick(_ mode: ImportMode) {
        importMode = mode
        picker = PickerRequest(mode: .open([.json]))
    }

    /// First phone: save a sync file holding everything on this phone into iCloud Drive; it is used from then on.
    private func startSync() {
        do {
            let url = try sync.makeStarterFile()
            menu = MenuRequest(
                title: L(sync.isOn ? "تصدير ملف المزامنة" : "إنشاء ملف مزامنة جديد", sync.isOn ? "Exporting the sync file" : "Creating a new sync file"),
                message: L("ستُفتح شاشة الحفظ: اختر iCloud Drive (ومجلدًا إن شئت)، ثم اضغط «نقل» أو «حفظ» في الأعلى.",
                           "The save screen opens: choose iCloud Drive (and a folder if you like), then tap «Move» or «Save» at the top."),
                actions: [
                    MenuAction(title: L("متابعة", "Continue"), icon: "icloud.and.arrow.up") { picker = PickerRequest(mode: .move(url)) },
                    MenuAction(title: L("إلغاء", "Cancel"), icon: "xmark") {},
                ])
        } catch {
            menu = .notice(L("تعذّر تجهيز الملف", "Couldn't prepare the file"), message: error.localizedDescription)
        }
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
            menu = .notice(L("تعذّر تجهيز النسخة", "Couldn't prepare the copy"), message: error.localizedDescription)
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let e):
            menu = .notice(L("تعذّر فتح الملف", "Couldn't open"), message: e.localizedDescription)
        case .success(let urls):
            guard let url = urls.first else { return }
            if importMode == .syncFile {
                sync.setFolder(url)
            } else {
                do {
                    let b = try sync.readBackup(at: url)
                    pendingRestore = (b.items.filter { $0.isAppointment }, b.tasks)
                    let n = pendingRestore!
                    menu = MenuRequest(title: L("استيراد \(Fmt.appointments(n.items.count)) و\(Fmt.tasks(n.tasks.count)) من النسخة", "Restore \(Fmt.appointments(n.items.count)) and \(Fmt.tasks(n.tasks.count)) from the copy"), actions: [
                        MenuAction(title: L("الدمج مع البيانات الحالية", "Merge with current"), icon: "arrow.triangle.merge") { restore(replace: false) },
                        MenuAction(title: L("استبدال جميع البيانات", "Replace everything"), icon: "arrow.2.squarepath", destructive: true) { restore(replace: true) },
                        MenuAction(title: L("إلغاء", "Cancel"), icon: "xmark") { pendingRestore = nil },
                    ])
                } catch {
                    menu = .notice(L("تعذّرت قراءة الملف", "Can't read the file"), message: L("تأكد أنه نسخة من تطبيق مواعيدي.\n\(error.localizedDescription)", "Make sure it's a Mawaeed backup.\n\(error.localizedDescription)"))
                }
            }
        }
    }

    private func restore(replace: Bool) {
        guard let b = pendingRestore else { return }
        store.restore(b.items, tasks: b.tasks, replace: replace)
        pendingRestore = nil
        menu = .notice(L("تم الاستيراد ✅", "Restored ✅"), message: L("تم استيراد \(Fmt.appointments(b.items.count)) و\(Fmt.tasks(b.tasks.count)).", "Restored \(Fmt.appointments(b.items.count)) and \(Fmt.tasks(b.tasks.count))."))
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
