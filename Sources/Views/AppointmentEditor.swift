import SwiftUI

/// Add or edit an appointment, shown as a sheet: title and place, the date (Hijri or Gregorian)
/// with the time under it, one reminder, and notes. The date and time open as popups that close
/// on an outside tap; picking a day closes the calendar at once.
struct AppointmentEditor: View {
    @EnvironmentObject var store: Store
    @State private var draft: Appointment
    @State private var hijri = true          // Hijri is the default way to pick the date
    @State private var pickingDay = false
    @State private var pickingTime = false
    @Namespace private var calendarSwitch
    let isNew: Bool
    let onFinish: () -> Void

    init(appointment: Appointment, isNew: Bool, onFinish: @escaping () -> Void) {
        var a = appointment
        if !a.hasTime {
            // Appointments always have a time now; an old all-day one starts at 9:00.
            a.hasTime = true
            a.date = Fmt.greg.date(bySettingHour: 9, minute: 0, second: 0, of: a.date) ?? a.date
        }
        if a.reminders.count > 1 { a.reminders = [a.reminders.max() ?? 60] }
        _draft = State(initialValue: a)
        self.isNew = isNew
        self.onFinish = onFinish
    }

    static func blank() -> Appointment {
        var a = Appointment()
        let cal = Fmt.greg
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date())) ?? Date()
        a.date = cal.date(bySettingHour: 10, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        a.hasTime = true
        a.reminders = [60]
        return a
    }

    var body: some View {
        AppNavigation {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    titleCard
                    dateCard
                    group(L("ذكّرني", "Remind me")) { reminderChoice }
                    group(L("ملاحظات", "Notes")) {
                        ZStack(alignment: .topLeading) {
                            if draft.notes.isEmpty {
                                Text(L("رقم الحجز، اسم الدكتور، الأوراق المطلوبة…", "Booking number, doctor's name, documents to bring…"))
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
            .navigationTitle(isNew ? L("موعد جديد", "New appointment") : L("تعديل الموعد", "Edit appointment"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("إلغاء", "Cancel"), action: onFinish) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("حفظ", "Save"), action: save)
                        .font(.app(.headline))
                        .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .popup(isPresented: $pickingDay) {
                DayPickerPopup(date: $draft.date, hijri: hijri) { close() }
            }
            .popup(isPresented: $pickingTime) {
                TimePickerPopup(date: $draft.date) { close() }
            }
        }
    }

    // MARK: Cards

    private var titleCard: some View {
        group(nil) {
            TextField(L("عنوان الموعد", "Appointment title"), text: $draft.title).font(.app(.headline))
            Divider()
            HStack(spacing: 8) {
                Image(systemName: "mappin.and.ellipse").foregroundColor(Theme.burgundy)
                TextField(L("المكان (مثلاً: مستشفى الملك فهد)", "Place (e.g. King Fahad Hospital)"), text: $draft.location)
            }
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
            group(L("الموعد", "Appointment")) {
                // A SwiftUI segmented control (not UISegmentedControl).
                HStack(spacing: 6) {
                    calendarOption(L("هجري", "Hijri"), true)          // right in Arabic
                    calendarOption(L("ميلادي", "Gregorian"), false)   // left in Arabic
                }
                .padding(4)
                .background(Capsule().fill(Theme.background))

                PickerRow(title: L("التاريخ", "Date"),
                          value: hijri ? Fmt.hijriText(draft.date) : Fmt.dateText(draft.date, hasTime: false),
                          icon: "calendar") { open(day: true) }
                Divider()
                PickerRow(title: L("الوقت", "Time"), value: Fmt.timeText(draft.date), icon: "clock") { open(day: false) }
            }
            Text(hijri ? L("يوافق: \(Fmt.dateText(draft.date, hasTime: false, long: true))", "Same as: \(Fmt.dateText(draft.date, hasTime: false, long: true))")
                       : L("يوافق: \(Fmt.hijriText(draft.date))", "Same as: \(Fmt.hijriText(draft.date))"))
                .font(.app(.caption)).foregroundColor(Theme.muted).padding(.horizontal, 6)
        }
    }

    /// One reminder at most: tapping the chosen one again clears it.
    private var reminderChoice: some View {
        let options = ReminderOption.options(hasTime: true)
        return VStack(spacing: 0) {
            ForEach(options, id: \.self) { m in
                let on = draft.reminders.first == m
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { draft.reminders = on ? [] : [m] }
                } label: {
                    HStack {
                        Text(ReminderOption.label(m, hasTime: true)).foregroundColor(Theme.ink)
                        Spacer()
                        Image(systemName: on ? "largecircle.fill.circle" : "circle")
                            .font(.title3)
                            .foregroundColor(on ? Theme.burgundy : Theme.muted.opacity(0.5))
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
        Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { hijri = value } } label: {
            Text(title)
                .font(.app(.subheadline, .semibold))
                .foregroundColor(hijri == value ? .white : Theme.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background {
                    if hijri == value {
                        Capsule().fill(Theme.burgundy)
                            .matchedGeometryEffect(id: "selection", in: calendarSwitch)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
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

    private func save() {
        draft.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.location = draft.location.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.hasTime = true
        store.upsert(draft)
        onFinish()
    }
}

/// TextEditor has an opaque background on iOS 15; hide it where possible.
struct ClearTextEditorBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content.scrollContentBackground(.hidden)
        } else {
            content
        }
    }
}
