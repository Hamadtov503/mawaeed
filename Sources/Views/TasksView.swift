import SwiftUI

/// مهامي: search, a centred plus, then «مهامك الحالية» and «مهامك المنجزة»
/// (each only once it has something in it). Swiping right-to-left goes back home.
struct TasksView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    @State private var query = ""

    private func matches(_ t: TaskItem) -> Bool {
        query.isEmpty || t.title.localizedCaseInsensitiveContains(query) || t.notes.localizedCaseInsensitiveContains(query)
    }

    var body: some View {
        let open = store.openTasks.filter(matches)
        let done = store.doneTasks.filter(matches)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(L("مهامي", "Tasks")).font(.app(size: 26, .bold)).foregroundColor(Theme.ink).padding(.top, 2)
                SearchField(prompt: L("ابحث في مهامك", "Search your tasks"), text: $query)
                AddButton(label: L("مهمة جديدة", "New task"), hint: L("اضغط على علامة + لإضافة مهمة لإنجازها", "Tap + to add a task to get done"), id: "addTask") { router.newTask() }

                if !open.isEmpty {
                    BandHeader(title: L("مهامك الحالية", "Your current tasks"), count: open.count, color: Theme.forest)
                    TaskList(tasks: open)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                if !done.isEmpty {
                    BandHeader(title: L("مهامك المنجزة", "Your completed tasks"), count: done.count, color: Theme.slate)
                    TaskList(tasks: done)
                        .transition(.opacity)
                }
                if open.isEmpty && done.isEmpty && !query.isEmpty {
                    Text(L("ما فيه نتائج لـ«\(query)»", "No results for “\(query)”")).font(.app(.subheadline)).foregroundColor(Theme.muted)
                        .frame(maxWidth: .infinity).padding(.top, 8)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 28)
            .frame(maxWidth: 650)
            .frame(maxWidth: .infinity)
            .animation(Router.soft, value: open.map(\.id))
            .animation(Router.soft, value: done.map(\.id))
        }
        .background(Theme.background.ignoresSafeArea())
        .swipeBackHome()
    }
}

/// Tasks in one card, separated by thin lines. On the home page they are read-only:
/// tapping a task opens it, and it is marked done from there.
struct TaskList: View {
    let tasks: [TaskItem]
    var interactive = true

    var body: some View {
        VStack(spacing: 0) {
            ForEach(tasks) { t in
                TaskRow(task: t, interactive: interactive)
                if t.id != tasks.last?.id { Divider().padding(.leading, 52) }
            }
        }
        .card(padding: 12)
    }
}

struct TaskRow: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    let task: TaskItem
    var interactive = true

    var body: some View {
        HStack(spacing: 12) {
            if interactive { statusMark }      // no tick on the home page: a task is finished from inside it
            TaskIcon(task: task, size: 42)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(task.title.isEmpty ? L("بدون عنوان", "Untitled") : task.title)
                        .font(.app(.body, .medium))
                        .foregroundColor(task.isDone ? Theme.muted : Theme.ink)
                        .strikethrough(task.isDone, color: Theme.muted)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(task.priority.title)
                        .font(.app(size: 10, .bold))
                        .foregroundColor(task.priority.color)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(task.priority.color.opacity(0.12)))
                        .fixedSize()
                }
                HStack(spacing: 4) {
                    Image(systemName: task.isScheduled ? (task.remind && !task.isDone ? "bell.fill" : "calendar") : "infinity")
                        .font(.system(size: 10))
                    Text(task.dueText ?? L("مفتوحة", "Open"))
                        .lineLimit(1)
                }
                .font(.app(.caption))
                .foregroundColor(task.isOverdue() ? Theme.burgundy : Theme.muted)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        // A tap gesture rather than a Button, so a sideways swipe over the row doesn't open it.
        .onTapGesture { router.editingTask = task }
        .accessibilityAddTraits(.isButton)
        .onLongPress {
            let t = task
            router.menu = MenuRequest(title: t.title, actions: [
                MenuAction(title: L("تعديل", "Edit"), icon: "pencil") { router.editingTask = t },
                MenuAction(title: L("حذف", "Delete"), icon: "trash", destructive: true) { withAnimation(Router.soft) { store.deleteTask(t.id) } },
            ])
        }
    }

    /// A tappable tick on the tasks page; on the home page only a status mark.
    @ViewBuilder
    private var statusMark: some View {
        let mark = Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 22, weight: .regular))
            .foregroundColor(task.isDone ? Theme.forest : (task.isOverdue() ? Theme.burgundy : Theme.muted.opacity(0.6)))
        if interactive {
            Button {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                withAnimation(Router.soft) { store.toggleTask(task.id) }
            } label: { mark }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isDone ? L("إلغاء الإنجاز", "Mark not done") : L("تم", "Done"))
        } else {
            mark.accessibilityHidden(true)
        }
    }
}

/// The task's icon: the user's picture if there is one, otherwise the chosen symbol.
/// Same size and corner shape as an appointment's icon tile.
struct TaskIcon: View {
    let task: TaskItem
    var size: CGFloat = 42

    var body: some View {
        if let data = task.iconImage, let ui = UIImage(data: data) {
            Image(uiImage: ui)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
                .opacity(task.isDone ? 0.55 : 1)
        } else {
            Tile(icon: task.displayIcon, color: task.isDone ? Theme.muted : task.priority.color, size: size)
        }
    }
}

enum IconImage {
    /// Crops to a centred square and shrinks to 120×120, so any picture becomes a small icon (~5 KB).
    static func make(from image: UIImage) -> Data? {
        let side = min(image.size.width, image.size.height)
        guard side > 0 else { return nil }
        let target: CGFloat = 120
        let scale = target / side
        let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let out = UIGraphicsImageRenderer(size: CGSize(width: target, height: target), format: format).image { _ in
            image.draw(in: CGRect(x: (target - drawSize.width) / 2, y: (target - drawSize.height) / 2,
                                  width: drawSize.width, height: drawSize.height))
        }
        return out.jpegData(compressionQuality: 0.8)
    }
}

/// Add or edit a task (a sheet; cards in a ScrollView, no Form): title and icon, priority,
/// open or scheduled (start now or at a chosen time, and an end), reminder, notes, done.
struct TaskEditor: View {
    @EnvironmentObject var store: Store
    @State private var draft: TaskItem
    @State private var scheduled: Bool
    @State private var startNow: Bool
    @State private var picking: Picking? = nil
    @State private var choosingPhoto = false
    @State private var choosingIcon = false
    @State private var menu: MenuRequest? = nil
    @State private var photoMenu: MenuRequest? = nil
    let onFinish: () -> Void

    enum Picking { case startDay, startTime, endDay, endTime }

    init(task: TaskItem, onFinish: @escaping () -> Void) {
        var t = task
        if t.due != nil {
            t.hasTime = true
            if t.start == nil { t.start = t.createdAt }
        }
        _draft = State(initialValue: t)
        _scheduled = State(initialValue: t.due != nil)
        _startNow = State(initialValue: false)
        self.onFinish = onFinish
    }

    private var isNew: Bool { store.task(draft.id) == nil }

    var body: some View {
        AppNavigation {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    card(L("عنوان المهمة", "Task title")) {
                        // The title, with the two icon buttons on the same line.
                        HStack(spacing: 10) {
                            TextField(L("وش المهمة؟", "What's the task?"), text: $draft.title).font(.app(.headline))
                                .accessibilityIdentifier("field.taskTitle")
                            iconPicker
                        }
                    }

                    card(L("مدى أهمية المهمة", "How important")) {
                        HStack(spacing: 6) {
                            ForEach(TaskPriority.allCases) { p in
                                segment(p.title, on: draft.priority == p, color: p.color) { draft.priority = p }
                            }
                        }
                    }

                    card(L("مدة إنجاز المهمة", "Time to complete")) {
                        HStack(spacing: 6) {
                            segment(L("مفتوح", "Open"), on: !scheduled, color: Theme.slate) { setScheduled(false) }
                            segment(L("محدد بوقت", "Scheduled"), on: scheduled, color: Theme.navy) { setScheduled(true) }
                        }
                        if scheduled {
                          VStack(alignment: .leading, spacing: 12) {
                            Text(L("بداية المهمة", "Start")).font(.app(.footnote, .bold)).foregroundColor(Theme.muted)
                            HStack(spacing: 6) {
                                segment(L("الآن", "Now"), on: startNow, color: Theme.forest) {
                                    startNow = true
                                    draft.start = Date()
                                    fixEnd()
                                }
                                segment(L("وقت وتاريخ", "Pick a time"), on: !startNow, color: Theme.forest) { startNow = false }
                            }
                            if !startNow {
                                VStack(alignment: .leading, spacing: 12) {
                                    PickerRow(title: L("التاريخ", "Date"), value: Fmt.dateText(startBinding.wrappedValue, hasTime: false),
                                              icon: "calendar") { open(.startDay) }
                                    PickerRow(title: L("الوقت", "Time"), value: Fmt.timeText(startBinding.wrappedValue),
                                              icon: "clock") { open(.startTime) }
                                }
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                            Divider()
                            Text(L("نهاية المهمة", "End")).font(.app(.footnote, .bold)).foregroundColor(Theme.muted)
                            PickerRow(title: L("التاريخ", "Date"), value: Fmt.dateText(endBinding.wrappedValue, hasTime: false),
                                      icon: "calendar") { open(.endDay) }
                                .accessibilityIdentifier("row.date")
                            PickerRow(title: L("الوقت", "Time"), value: Fmt.timeText(endBinding.wrappedValue),
                                      icon: "clock") { open(.endTime) }
                            Toggle(L("ذكّرني عند نهاية المهمة", "Remind me at the end"), isOn: $draft.remind)
                          }
                          .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)),
                                                  removal: .opacity))
                        }
                    }

                    card(L("ملاحظات", "Notes")) {
                        ZStack(alignment: .topLeading) {
                            if draft.notes.isEmpty {
                                Text(L("تفاصيل إضافية…", "More details…")).foregroundColor(Theme.muted.opacity(0.7)).padding(.top, 8).padding(.leading, 5)
                            }
                            TextEditor(text: $draft.notes).frame(minHeight: 80).modifier(ClearTextEditorBackground())
                        }
                    }

                    if !isNew {
                        Button {
                            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                            store.toggleTask(draft.id)
                            onFinish()
                        } label: {
                            Label(draft.isDone ? L("إرجاعها غير منجزة", "Mark as not done") : L("تم إنجاز المهمة", "Mark as done"),
                                  systemImage: draft.isDone ? "arrow.uturn.backward" : "checkmark.circle.fill")
                                .font(.app(.body, .bold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background(Capsule().fill(draft.isDone ? Theme.slate : Theme.forest))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("button.toggleDone")

                        Button(role: .destructive) {
                            menu = MenuRequest(title: L("تحذف المهمة؟", "Delete this task?"), actions: [
                                MenuAction(title: L("حذف", "Delete"), icon: "trash", destructive: true) {
                                    store.deleteTask(draft.id)
                                    onFinish()
                                },
                                MenuAction(title: L("إلغاء", "Cancel"), icon: "xmark") {},
                            ])
                        } label: {
                            Label(L("حذف المهمة", "Delete task"), systemImage: "trash").font(.app(.body, .semibold))
                                .foregroundColor(Theme.burgundy)
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                        .card(padding: 4)
                    }
                }
                .padding(18)
                .frame(maxWidth: 650)
                .frame(maxWidth: .infinity)
                .animation(.spring(response: 0.4, dampingFraction: 0.88), value: scheduled)
                .animation(.spring(response: 0.4, dampingFraction: 0.88), value: startNow)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(isNew ? L("مهمة جديدة", "New task") : L("تعديل المهمة", "Edit task"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("إلغاء", "Cancel"), action: onFinish) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("حفظ", "Save"), action: save)
                        .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("button.save")
                }
            }
            .popup(isPresented: $choosingIcon, top: 126) { iconGrid }   // just under the title card, over the headings below it
            .popup(isPresented: Binding(get: { picking == .startDay }, set: { if !$0 { picking = nil } })) {
                DayPickerPopup(date: startBinding, hijri: false) { close() }
            }
            .popup(isPresented: Binding(get: { picking == .startTime }, set: { if !$0 { picking = nil } })) {
                TimePickerPopup(date: startBinding) { close() }
            }
            .popup(isPresented: Binding(get: { picking == .endDay }, set: { if !$0 { picking = nil } })) {
                DayPickerPopup(date: endBinding, hijri: false) { close() }
            }
            .popup(isPresented: Binding(get: { picking == .endTime }, set: { if !$0 { picking = nil } })) {
                TimePickerPopup(date: endBinding) { close() }
            }
            .actionMenu($menu)
            .actionMenu($photoMenu, top: 126)   // just under the title card, over the headings below it
        }
    }

    // MARK: Pieces

    /// Two buttons only: your own picture (a colourful flower, like a photo album), and a magnifying
    /// glass that opens the grid of icons.
    private var iconPicker: some View {
        HStack(spacing: 10) {
            Group {
                Group {
                    if let data = draft.iconImage, let ui = UIImage(data: data) {
                        Image(uiImage: ui).resizable().scaledToFill()
                    } else {
                        PhotosFlower().padding(6)
                    }
                }
                .frame(width: 42, height: 42)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                // Drawn inside the edge, so the long-press preview (which cuts at the edge) shows the
                // same frame as the button and nothing jumps when the menu closes.
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(draft.iconImage != nil ? draft.priority.color : Theme.border, lineWidth: draft.iconImage != nil ? 2.5 : 1))
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .onTapGesture { choosingPhoto = true }
            // A long press on the picture offers to remove it (the icon comes back).
            .onLongPress {
                guard draft.iconImage != nil else { return }
                photoMenu = MenuRequest(actions: [
                    MenuAction(title: L("احذف الصورة", "Remove picture"), icon: "trash", destructive: true) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { draft.iconImage = nil }
                    },
                ])
            }
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(L("صورة من الألبوم", "Picture from Photos"))
            .accessibilityIdentifier("button.taskPhoto")

            Button {
                // Put the keyboard away so the whole grid shows.
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) { choosingIcon = true }
            } label: {
                SearchGlass()
                    .padding(9)
                    .frame(width: 42, height: 42)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("اختر أيقونة", "Choose an icon"))
            .accessibilityIdentifier("button.taskIcons")
        }
        .fixedSize()
        .sheet(isPresented: $choosingPhoto) {
            PhotoPicker { image in
                if let data = IconImage.make(from: image) {
                    withAnimation(.easeInOut(duration: 0.2)) { draft.iconImage = data }
                }
            }
            .ignoresSafeArea()
        }
    }

    /// The icons to choose from; picking one closes the grid.
    private var iconGrid: some View {
        VStack(spacing: 12) {
            Text(L("اختر أيقونة", "Choose an icon")).font(.app(.headline, .bold)).foregroundColor(Theme.ink)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 10) {
                ForEach(TaskItem.icons, id: \.self) { name in
                    let on = draft.iconImage == nil && draft.displayIcon == name
                    Button {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
                            draft.icon = name
                            draft.iconImage = nil
                            choosingIcon = false
                        }
                    } label: {
                        Image(systemName: name)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(on ? .white : draft.priority.color)
                            .frame(width: 50, height: 50)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(on ? draft.priority.color : draft.priority.color.opacity(0.1)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("icon.\(name)")
                }
            }
        }
    }

    private func segment(_ title: String, on: Bool, color: Color, _ action: @escaping () -> Void) -> some View {
        Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { action() } } label: {
            Text(title)
                .font(.app(.subheadline, .semibold))
                .foregroundColor(on ? .white : Theme.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(Capsule().fill(on ? color : Theme.sand))
        }
        .buttonStyle(.plain)
    }

    private var startBinding: Binding<Date> {
        Binding(get: { draft.start ?? Date() }, set: { draft.start = $0; fixEnd() })
    }

    private var endBinding: Binding<Date> {
        Binding(get: { draft.due ?? defaultEnd }, set: { draft.due = $0; fixEnd() })
    }

    private var defaultEnd: Date { (draft.start ?? Date()).addingTimeInterval(3600) }

    /// The end can't be before the start: push it to an hour after.
    private func fixEnd() {
        guard let st = draft.start else { return }
        if let d = draft.due, d < st { draft.due = st.addingTimeInterval(3600) }
    }

    private func setScheduled(_ on: Bool) {
        scheduled = on
        if on {
            draft.hasTime = true
            if draft.start == nil { draft.start = Date(); startNow = true }
            if draft.due == nil { draft.due = defaultEnd }
        }
    }

    private func open(_ p: Picking) {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) { picking = p }
    }

    private func close() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) { picking = nil }
    }

    private func card<C: View>(_ title: String?, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let t = title {
                Text(t).font(.app(.footnote, .bold)).foregroundColor(Theme.muted).padding(.horizontal, 6)
            }
            VStack(alignment: .leading, spacing: 12) { content() }
                .foregroundColor(Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(padding: 16)
        }
    }

    private func save() {
        draft.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if scheduled {
            draft.hasTime = true
            if startNow || draft.start == nil { draft.start = draft.start ?? Date() }
            if draft.due == nil { draft.due = defaultEnd }
            fixEnd()
        } else {
            draft.start = nil
            draft.due = nil
            draft.hasTime = false
        }
        if draft.icon == nil { draft.icon = "checklist" }
        store.upsertTask(draft)
        onFinish()
    }
}


/// The "pick a photo" mark: a flower of see-through petals in the app's own colours
/// (burgundy, rose, sand gold, forest, teal, navy, slate and plum), overlapping softly.
struct PhotosFlower: View {
    private let colors: [Color] = [
        Theme.burgundy,
        Color(red: 0.76, green: 0.36, blue: 0.42),   // rose
        Color(red: 0.80, green: 0.62, blue: 0.30),   // sand gold
        Color(red: 0.45, green: 0.62, blue: 0.36),   // olive
        Theme.forest,
        Color(red: 0.22, green: 0.50, blue: 0.55),   // teal
        Theme.navy,
        Color(red: 0.45, green: 0.32, blue: 0.55),   // plum
    ]

    var body: some View {
        GeometryReader { g in
            let side = min(g.size.width, g.size.height)
            ZStack {
                ForEach(colors.indices, id: \.self) { i in
                    Capsule()
                        .fill(LinearGradient(colors: [colors[i].opacity(0.95), colors[i].opacity(0.6)],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: side * 0.3, height: side * 0.5)
                        .offset(y: -side * 0.25)
                        .rotationEffect(.degrees(Double(i) * 45))
                        .blendMode(.multiply)
                }
                Circle().fill(Theme.card).frame(width: side * 0.12, height: side * 0.12)
            }
            .frame(width: side, height: side)
            .compositingGroup()
            .position(x: g.size.width / 2, y: g.size.height / 2)
        }
        .accessibilityHidden(true)
    }
}

/// The "choose an icon" mark: a magnifying glass drawn to match the app: a navy ring with a soft
/// glint, and a rounded burgundy handle.
struct SearchGlass: View {
    var body: some View {
        GeometryReader { g in
            let s = min(g.size.width, g.size.height)
            let r = s * 0.31                                   // ring radius
            let c = CGPoint(x: s * 0.42, y: s * 0.42)          // ring centre
            let line = s * 0.11
            ZStack {
                // Handle, from the ring's edge down to the bottom-right.
                Path { p in
                    let a = CGFloat.pi / 4
                    p.move(to: CGPoint(x: c.x + (r + line * 0.3) * cos(a), y: c.y + (r + line * 0.3) * sin(a)))
                    p.addLine(to: CGPoint(x: s * 0.88, y: s * 0.88))
                }
                .stroke(Theme.burgundy, style: StrokeStyle(lineWidth: line * 1.45, lineCap: .round))
                // Lens and ring.
                Circle()
                    .fill(Theme.sand.opacity(0.55))
                    .frame(width: r * 2, height: r * 2)
                    .position(c)
                Circle()
                    .stroke(Theme.navy, lineWidth: line)
                    .frame(width: r * 2, height: r * 2)
                    .position(c)
                // Glint inside the lens, upper left.
                Path { p in
                    p.addArc(center: c, radius: r * 0.62, startAngle: .degrees(200), endAngle: .degrees(250), clockwise: false)
                }
                .stroke(Color.white, style: StrokeStyle(lineWidth: line * 0.55, lineCap: .round))
                Path { p in
                    p.addArc(center: c, radius: r * 0.62, startAngle: .degrees(265), endAngle: .degrees(282), clockwise: false)
                }
                .stroke(Color.white, style: StrokeStyle(lineWidth: line * 0.55, lineCap: .round))
            }
            .frame(width: s, height: s)
            .position(x: g.size.width / 2, y: g.size.height / 2)
        }
        .environment(\.layoutDirection, .leftToRight)   // the handle always points to the bottom right
        .accessibilityHidden(true)
    }
}
