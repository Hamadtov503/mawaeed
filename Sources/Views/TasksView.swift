import SwiftUI

/// مهامي: open tasks grouped (late, today, coming, no date) or the finished ones. The plus adds a task.
struct TasksView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    @State private var showDone = false

    var body: some View {
        let now = Date()
        let open = store.openTasks
        let late = open.filter { $0.isOverdue(now: now) }
        let today = open.filter { $0.isDue(on: now) && !$0.isOverdue(now: now) }
        let coming = open.filter { ($0.due ?? .distantPast) > now && !$0.isDue(on: now) }
        let undated = open.filter { $0.due == nil }
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageTitle(title: "مهامي") { router.newTask() }

                HStack(spacing: 8) {
                    Chip(title: "الحالية", selected: !showDone) { withAnimation(Router.soft) { showDone = false } }
                    Chip(title: "المنجزة", icon: "checkmark", selected: showDone) { withAnimation(Router.soft) { showDone = true } }
                }

                if showDone {
                    if store.doneTasks.isEmpty {
                        empty("ما فيه مهام منجزة")
                    } else {
                        TaskList(tasks: store.doneTasks)
                    }
                } else if open.isEmpty {
                    empty("ما عندك مهام — اضغط ➕ وأضف وحدة")
                } else {
                    group("متأخرة", late, Theme.burgundy)
                    group("اليوم", today, Theme.navy)
                    group("القادمة", coming, Theme.forest)
                    group("بدون تاريخ", undated, Theme.slate)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 28)
            .frame(maxWidth: 650)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background.ignoresSafeArea())
    }

    @ViewBuilder
    private func group(_ title: String, _ list: [TaskItem], _ color: Color) -> some View {
        if !list.isEmpty {
            HStack(spacing: 6) {
                Capsule().fill(color).frame(width: 4, height: 18)
                Text(title).font(.app(.subheadline, .bold)).foregroundColor(color)
                Text("\(list.count)").font(.app(.caption, .bold)).foregroundColor(color)
            }
            .padding(.horizontal, 4)
            TaskList(tasks: list)
        }
    }

    private func empty(_ text: String) -> some View {
        Text(text).font(.app(.subheadline)).foregroundColor(Theme.muted)
            .frame(maxWidth: .infinity).padding(.vertical, 24).card()
    }
}

/// A page title with the plus button on the left.
struct PageTitle: View {
    let title: String
    let onAdd: () -> Void

    var body: some View {
        HStack {
            Text(title).font(.app(size: 30, .bold)).foregroundColor(Theme.ink)
            Spacer()
            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(Theme.burgundy))
                    .shadow(color: Theme.burgundy.opacity(0.3), radius: 6, y: 3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("إضافة")
        }
        .padding(.top, 8)
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
            .accessibilityLabel(task.isDone ? "إلغاء الإنجاز" : "تم")

            Button { router.editingTask = task } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title.isEmpty ? "بدون عنوان" : task.title)
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
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
        .contextMenu {
            Button { router.editingTask = task } label: { Label("تعديل", systemImage: "pencil") }
            Button(role: .destructive) { withAnimation(Router.soft) { store.deleteTask(task.id) } } label: {
                Label("حذف", systemImage: "trash")
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
                        TextField("وش المهمة؟", text: $draft.title).font(.app(.headline))
                    }
                    card {
                        Toggle("لها تاريخ", isOn: $hasDate.animation(Router.soft))
                        if hasDate {
                            Toggle("وقت محدد", isOn: $draft.hasTime.animation(Router.soft))
                            HStack {
                                Text(draft.hasTime ? "التاريخ والوقت" : "التاريخ")
                                Spacer()
                                DatePicker("", selection: Binding(get: { draft.due ?? defaultDue }, set: { draft.due = $0 }),
                                           displayedComponents: draft.hasTime ? [.date, .hourAndMinute] : [.date])
                                    .labelsHidden()
                            }
                            Text("يوافق: \(Fmt.hijriText(draft.due ?? defaultDue))")
                                .font(.app(.caption)).foregroundColor(Theme.muted)
                            Toggle("ذكّرني", isOn: $draft.remind)
                        }
                    }
                    card {
                        ZStack(alignment: .topLeading) {
                            if draft.notes.isEmpty {
                                Text("ملاحظات").foregroundColor(Theme.muted.opacity(0.7)).padding(.top, 8).padding(.leading, 5)
                            }
                            TextEditor(text: $draft.notes).frame(minHeight: 80).modifier(ClearTextEditorBackground())
                        }
                    }
                    if !isNew {
                        Button(role: .destructive) { confirmDelete = true } label: {
                            Label("حذف المهمة", systemImage: "trash").font(.app(.body, .semibold))
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
            .navigationTitle(isNew ? "مهمة جديدة" : "تعديل المهمة")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء", action: onFinish) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("حفظ", action: save)
                        .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("تحذف المهمة؟", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("حذف", role: .destructive) {
                    store.deleteTask(draft.id)
                    onFinish()
                }
                Button("إلغاء", role: .cancel) {}
            }
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
