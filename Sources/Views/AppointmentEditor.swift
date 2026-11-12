import SwiftUI

/// Add or edit an appointment, shown as a sheet. Built from cards in a ScrollView rather than a
/// Form: Form/List rows are system list cells and were drawn mirrored in right-to-left.
struct AppointmentEditor: View {
    @EnvironmentObject var store: Store
    @State private var draft: Appointment
    @State private var hijri = false
    let isNew: Bool
    let onFinish: () -> Void

    init(appointment: Appointment, isNew: Bool, onFinish: @escaping () -> Void) {
        _draft = State(initialValue: appointment)
        self.isNew = isNew
        self.onFinish = onFinish
    }

    static func blank() -> Appointment {
        var a = Appointment()
        let cal = Fmt.greg
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date())) ?? Date()
        a.date = cal.date(bySettingHour: 10, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        return a
    }

    var body: some View {
        AppNavigation {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    titleCard
                    dateCard
                    group("المكان") {
                        TextField("مثلاً: مستشفى الملك فهد", text: $draft.location)
                    }
                    group("ذكّرني") { remindersList }
                    group("ملاحظات") {
                        ZStack(alignment: .topLeading) {
                            if draft.notes.isEmpty {
                                Text("رقم الحجز، اسم الدكتور، الأوراق المطلوبة…")
                                    .foregroundColor(Theme.muted.opacity(0.7))
                                    .padding(.top, 8).padding(.leading, 5)
                            }
                            TextEditor(text: $draft.notes)
                                .frame(minHeight: 90)
                                .modifier(ClearTextEditorBackground())
                        }
                    }
                }
                .padding(18)
                .frame(maxWidth: 650)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(isNew ? "موعد جديد" : "تعديل الموعد")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء", action: onFinish) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("حفظ", action: save)
                        .font(.app(.headline))
                        .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onChange(of: draft.hasTime) { has in
                if !has { draft.reminders = draft.reminders.filter { $0 == 0 || $0 >= 1440 } }
                if draft.reminders.isEmpty { draft.reminders = [has ? 60 : 1440] }
            }
        }
    }

    // MARK: Cards

    private var titleCard: some View {
        group(nil) {
            TextField("عنوان الموعد", text: $draft.title).font(.app(.headline))
            if isNew {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Suggestion.all) { s in
                            Chip(title: s.title, icon: s.icon, selected: draft.icon == s.icon && draft.title == s.title) {
                                draft.title = s.title
                                draft.icon = s.icon
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var dateCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            group("الموعد") {
                // A SwiftUI segmented control (not UISegmentedControl).
                HStack(spacing: 6) {
                    calendarOption("ميلادي", false)
                    calendarOption("هجري", true)
                }
                .padding(4)
                .background(Capsule().fill(Theme.background))

                Toggle("وقت محدد", isOn: $draft.hasTime)

                HStack {
                    Text(draft.hasTime ? "التاريخ والوقت" : "التاريخ")
                    Spacer()
                    DatePicker("", selection: $draft.date,
                               displayedComponents: draft.hasTime ? [.date, .hourAndMinute] : [.date])
                        .labelsHidden()
                        .environment(\.calendar, hijri ? Fmt.hijriCalendar : Fmt.greg)
                        .environment(\.locale, hijri ? Fmt.hijriLocale : Fmt.locale)
                        .id(hijri)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        quick("اليوم", 0)
                        quick("بكرة", 1)
                        quick("بعد يومين", 2)
                        quick("بعد أسبوع", 7)
                    }
                }
            }
            Text(hijri ? "يوافق: \(Fmt.dateText(draft.date, hasTime: false, long: true))" : "يوافق: \(Fmt.hijriText(draft.date))")
                .font(.app(.caption)).foregroundColor(Theme.muted).padding(.horizontal, 6)
        }
    }

    private var remindersList: some View {
        let options = ReminderOption.options(hasTime: draft.hasTime)
        return VStack(spacing: 0) {
            ForEach(options, id: \.self) { m in
                Button {
                    if let i = draft.reminders.firstIndex(of: m) { draft.reminders.remove(at: i) } else { draft.reminders.append(m) }
                } label: {
                    HStack {
                        Text(ReminderOption.label(m, hasTime: draft.hasTime)).foregroundColor(Theme.ink)
                        Spacer()
                        Image(systemName: draft.reminders.contains(m) ? "checkmark.circle.fill" : "circle")
                            .font(.app(.title3))
                            .foregroundColor(draft.reminders.contains(m) ? .brand : Theme.muted.opacity(0.5))
                    }
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if m != options.last { Divider() }
            }
        }
    }

    private func group<C: View>(_ title: String?, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let t = title {
                Text(t).font(.app(.footnote, .bold)).foregroundColor(Theme.muted).padding(.horizontal, 6)
            }
            VStack(alignment: .leading, spacing: 14) { content() }
                .foregroundColor(Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(padding: 16)
        }
    }

    private func calendarOption(_ title: String, _ value: Bool) -> some View {
        Button { withAnimation(.easeInOut(duration: 0.15)) { hijri = value } } label: {
            Text(title)
                .font(.app(.subheadline, .semibold))
                .foregroundColor(hijri == value ? .white : Theme.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Capsule().fill(hijri == value ? Theme.burgundy : Color.clear))
        }
        .buttonStyle(.plain)
    }

    private func quick(_ title: String, _ days: Int) -> some View {
        Button {
            let cal = Fmt.greg
            let base = cal.date(byAdding: .day, value: days, to: cal.startOfDay(for: Date())) ?? Date()
            let c = cal.dateComponents([.hour, .minute], from: draft.date)
            draft.date = cal.date(bySettingHour: c.hour ?? 10, minute: c.minute ?? 0, second: 0, of: base) ?? base
        } label: {
            Text(title)
                .font(.app(.caption, .semibold))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Capsule().fill(Theme.burgundy.opacity(0.15)))
                .foregroundColor(Theme.burgundy)
        }
        .buttonStyle(.plain)
    }

    private func save() {
        draft.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.location = draft.location.trimmingCharacters(in: .whitespacesAndNewlines)
        store.upsert(draft)
        onFinish()
    }
}

/// TextEditor has an opaque background on iOS 15; hide it where possible.
private struct ClearTextEditorBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content.scrollContentBackground(.hidden)
        } else {
            content
        }
    }
}
