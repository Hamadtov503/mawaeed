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

/// Tasks in one card, separated by thin lines.
struct TaskList: View {
    let tasks: [TaskItem]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(tasks) { t in
                TaskRow(task: t)
                if t.id != tasks.last?.id { Divider().padding(.leading, 44) }
            }
        }
        .card(padding: 12)
    }
}

struct TaskRow: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    let task: TaskItem

    var body: some View {
        HStack(spacing: 12) {
            Button {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                withAnimation(Router.soft) { store.toggleTask(task.id) }
            } label: {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundColor(task.isDone ? Theme.forest : (task.isOverdue() ? Theme.burgundy : Theme.muted.opacity(0.6)))
                    .scaleEffect(task.isDone ? 1.05 : 1)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isDone ? L("إلغاء الإنجاز", "Mark not done") : L("تم", "Done"))

            VStack(alignment: .leading, spacing: 2) {
                    Text(task.title.isEmpty ? L("بدون عنوان", "Untitled") : task.title)
                        .font(.app(.body, .medium))
                        .foregroundColor(task.isDone ? Theme.muted : Theme.ink)
                        .strikethrough(task.isDone, color: Theme.muted)
                        .lineLimit(2)
                    if let due = task.dueText {
                        HStack(spacing: 4) {
                            Image(systemName: task.remind && !task.isDone ? "bell.fill" : "calendar")
                                .font(.system(size: 10))
                            Text(due)
                        }
                        .font(.app(.caption))
                        .foregroundColor(task.isOverdue() ? Theme.burgundy : Theme.muted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                // A tap gesture rather than a Button, so a sideways swipe over the row doesn't open it.
                .onTapGesture { router.editingTask = task }
                .accessibilityAddTraits(.isButton)
        }
        .padding(.vertical, 8)
        .contextMenu {
            Button { router.editingTask = task } label: { Label(L("تعديل", "Edit"), systemImage: "pencil") }
            Button(role: .destructive) { withAnimation(Router.soft) { store.deleteTask(task.id) } } label: {
                Label(L("حذف", "Delete"), systemImage: "trash")
            }
        }
    }
}

/// Add or edit a task (a sheet; cards in a ScrollView, no Form).
struct TaskEditor: View {
    @EnvironmentObject var store: Store
    @State private var draft: TaskItem
    @State private var hasDate: Bool
    @State private var confirmDelete = false
    @State private var pickingDay = false
    @State private var pickingTime = false
    let onFinish: () -> Void

    init(task: TaskItem, onFinish: @escaping () -> Void) {
        _draft = State(initialValue: task)
        _hasDate = State(initialValue: task.due != nil)
        self.onFinish = onFinish
    }

    private var isNew: Bool { store.task(draft.id) == nil }

    var body: some View {
        AppNavigation {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    card {
                        TextField(L("وش المهمة؟", "What's the task?"), text: $draft.title).font(.app(.headline))
                            .accessibilityIdentifier("field.taskTitle")
                    }
                    card {
                        Toggle(L("لها تاريخ", "Has a date"), isOn: $hasDate.animation(Router.soft))
                            .accessibilityIdentifier("toggle.hasDate")
                        if hasDate {
                            Toggle(L("وقت محدد", "Specific time"), isOn: $draft.hasTime.animation(Router.soft))
                            PickerRow(title: L("التاريخ", "Date"), value: Fmt.dateText(dueBinding.wrappedValue, hasTime: false),
                                      icon: "calendar") { open(day: true) }
                                .accessibilityIdentifier("row.date")
                            if draft.hasTime {
                                PickerRow(title: L("الوقت", "Time"), value: Fmt.timeText(dueBinding.wrappedValue),
                                          icon: "clock") { open(day: false) }
                            }
                            Text(L("يوافق: \(Fmt.hijriText(draft.due ?? defaultDue))", "Same as: \(Fmt.hijriText(draft.due ?? defaultDue))"))
                                .font(.app(.caption)).foregroundColor(Theme.muted)
                            Toggle(L("ذكّرني", "Remind me"), isOn: $draft.remind)
                        }
                    }
                    card {
                        ZStack(alignment: .topLeading) {
                            if draft.notes.isEmpty {
                                Text(L("ملاحظات", "Notes")).foregroundColor(Theme.muted.opacity(0.7)).padding(.top, 8).padding(.leading, 5)
                            }
                            TextEditor(text: $draft.notes).frame(minHeight: 80).modifier(ClearTextEditorBackground())
                        }
                    }
                    if !isNew {
                        Button(role: .destructive) { confirmDelete = true } label: {
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
            .popup(isPresented: $pickingDay) {
                DayPickerPopup(date: dueBinding, hijri: false) { close() }
            }
            .popup(isPresented: $pickingTime) {
                TimePickerPopup(date: dueBinding) { close() }
            }
            .confirmationDialog(L("تحذف المهمة؟", "Delete this task?"), isPresented: $confirmDelete, titleVisibility: .visible) {
                Button(L("حذف", "Delete"), role: .destructive) {
                    store.deleteTask(draft.id)
                    onFinish()
                }
                Button(L("إلغاء", "Cancel"), role: .cancel) {}
            }
        }
    }

    private var dueBinding: Binding<Date> {
        Binding(get: { draft.due ?? defaultDue }, set: { draft.due = $0 })
    }

    private func open(day: Bool) {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
            if day { pickingDay = true } else { pickingTime = true }
        }
    }

    private func close() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
            pickingDay = false
            pickingTime = false
        }
    }

    private var defaultDue: Date {
        let cal = Fmt.greg
        return cal.date(bySettingHour: 17, minute: 0, second: 0, of: Date()) ?? Date()
    }

    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 14) { content() }
            .foregroundColor(Theme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: 16)
    }

    private func save() {
        draft.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if hasDate { draft.due = draft.due ?? defaultDue } else { draft.due = nil }
        store.upsertTask(draft)
        onFinish()
    }
}
