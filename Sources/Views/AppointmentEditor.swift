import SwiftUI

/// Add or edit an appointment. Always shown as a sheet, so a Form is safe here.
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
            Form {
                Section {
                    TextField("عنوان الموعد", text: $draft.title).font(.headline)
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
                            .padding(.vertical, 4)
                        }
                    }
                }

                Section(header: Text("الموعد"), footer: Text(otherCalendar)) {
                    Picker("التقويم", selection: $hijri) {
                        Text("ميلادي").tag(false)
                        Text("هجري").tag(true)
                    }
                    .pickerStyle(.segmented)
                    Toggle("وقت محدد", isOn: $draft.hasTime)
                    DatePicker(draft.hasTime ? "التاريخ والوقت" : "التاريخ", selection: $draft.date,
                               displayedComponents: draft.hasTime ? [.date, .hourAndMinute] : [.date])
                        .environment(\.calendar, hijri ? Fmt.hijriCalendar : Fmt.greg)
                        .environment(\.locale, hijri ? Fmt.hijriLocale : Fmt.locale)
                        .id(hijri)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            quick("اليوم", 0)
                            quick("بكرة", 1)
                            quick("بعد يومين", 2)
                            quick("بعد أسبوع", 7)
                        }
                    }
                }

                Section(header: Text("المكان")) {
                    TextField("مثلاً: مستشفى الملك فهد", text: $draft.location)
                }

                Section(header: Text("ذكّرني")) {
                    ForEach(ReminderOption.options(hasTime: draft.hasTime), id: \.self) { m in
                        Button {
                            if let i = draft.reminders.firstIndex(of: m) { draft.reminders.remove(at: i) } else { draft.reminders.append(m) }
                        } label: {
                            HStack {
                                Text(ReminderOption.label(m, hasTime: draft.hasTime)).foregroundColor(Theme.ink)
                                Spacer()
                                if draft.reminders.contains(m) {
                                    Image(systemName: "checkmark").font(.body.bold()).foregroundColor(.brand)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section(header: Text("ملاحظات")) {
                    TextEditor(text: $draft.notes).frame(minHeight: 90)
                }
            }
            .themedForm()
            .navigationTitle(isNew ? "موعد جديد" : "تعديل الموعد")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء", action: onFinish) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("حفظ", action: save)
                        .font(.headline)
                        .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onChange(of: draft.hasTime) { has in
                if !has { draft.reminders = draft.reminders.filter { $0 == 0 || $0 >= 1440 } }
                if draft.reminders.isEmpty { draft.reminders = [has ? 60 : 1440] }
            }
        }
    }

    private var otherCalendar: String {
        hijri ? "يوافق: \(Fmt.dateText(draft.date, hasTime: false, long: true))" : "يوافق: \(Fmt.hijriText(draft.date))"
    }

    private func quick(_ title: String, _ days: Int) -> some View {
        Button {
            let cal = Fmt.greg
            let base = cal.date(byAdding: .day, value: days, to: cal.startOfDay(for: Date())) ?? Date()
            let c = cal.dateComponents([.hour, .minute], from: draft.date)
            draft.date = cal.date(bySettingHour: c.hour ?? 10, minute: c.minute ?? 0, second: 0, of: base) ?? base
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Capsule().fill(Theme.gold.opacity(0.15)))
                .foregroundColor(Theme.gold)
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
