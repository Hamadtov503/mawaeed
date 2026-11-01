import SwiftUI

struct ItemDetailView: View {
    let itemID: UUID
    @EnvironmentObject var store: Store
    @Environment(\.presentationMode) private var presentationMode
    @State private var showEdit = false
    @State private var showRenew = false
    @State private var confirmDelete = false
    @State private var viewer: PhotoRef? = nil
    @State private var shareItems: [Any]? = nil

    var body: some View {
        if let item = store.item(itemID) {
            content(item)
        } else {
            EmptyStateView(icon: "trash", title: "تم حذف هذا العنصر", message: "")
        }
    }

    private func content(_ item: Item) -> some View {
        let u = item.urgency()
        return List {
            Section {
                VStack(spacing: 12) {
                    IconBadge(icon: item.displayIcon, color: item.category.color, size: 64)
                    Text(item.title).font(.title2.bold()).multilineTextAlignment(.center)
                    Text(item.category.title).font(.subheadline).foregroundColor(.secondary)
                    if item.isDone {
                        Label(item.isMedicine ? "متوقف" : "منجز", systemImage: "checkmark.seal.fill")
                            .font(.headline).foregroundColor(.green)
                    } else if item.isMedicine {
                        let a = item.adherence()
                        Text(a.due == 0 ? "بداية الكورس" : "التزامك آخر 7 أيام: \(a.taken) من \(a.due)")
                            .font(.headline)
                            .foregroundColor(a.due > 0 && a.taken < a.due ? .orange : .green)
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(Capsule().fill(Color.red.opacity(0.08)))
                    } else {
                        Text(Fmt.countdown(to: item.date, hasTime: item.hasTime))
                            .font(.headline)
                            .foregroundColor(u.color)
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(Capsule().fill(u.color.opacity(0.12)))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            if item.isMedicine {
                Section(header: Text("الدواء")) {
                    if !item.dosage.isEmpty { row("pills", "الجرعة", item.dosage) }
                    row("clock", "الأوقات", item.doseTimesLabel)
                    row("calendar", "من", Fmt.dateText(item.date, hasTime: false))
                    row("hourglass", "المدة", item.courseLabel)
                }
                let today = store.doses().filter { $0.item.id == item.id }
                if !today.isEmpty {
                    Section(header: Text("جرعات اليوم")) {
                        ForEach(today) { DoseRow(dose: $0) }
                    }
                }
            } else {
                Section(header: Text(item.category == .warranty ? "انتهاء الضمان" : "التاريخ")) {
                    row("calendar", "ميلادي", Fmt.dateText(item.date, hasTime: false, long: true))
                    row("moon.fill", "هجري", Fmt.hijriText(item.date))
                    if item.hasTime { row("clock", "الوقت", Fmt.timeText(item.date)) }
                    row("repeat", "التكرار", item.repeatLabel)
                    row("bell.fill", "التنبيه", ReminderOption.summary(item.reminders, hasTime: item.hasTime))
                    if let s = item.snoozeUntil, s > Date() {
                        row("zzz", "مؤجّل لين", Fmt.dateText(s, hasTime: true))
                    }
                }
            }

            if item.hasInstallments, let total = item.installmentsTotal {
                Section(header: Text("الأقساط")) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("مدفوع \(min(item.installmentsPaid, total)) من \(total)").font(.headline)
                            Spacer()
                            Text(item.installmentsLeft == 0 ? "خلصت 🎉" : "باقي \(item.installmentsLeft)")
                                .foregroundColor(.secondary)
                        }
                        ProgressView(value: Double(min(item.installmentsPaid, total)), total: Double(total))
                            .tint(.green)
                    }
                    .padding(.vertical, 4)
                    if let r = item.remainingAmount, r > 0 { row("banknote", "المبلغ المتبقي", Fmt.money(r)) }
                    if let last = item.lastInstallmentDate { row("flag.checkered", "آخر قسط", Fmt.dateText(last, hasTime: false)) }
                }
            }

            if item.category == .warranty, let p = item.purchaseDate {
                Section(header: Text("الضمان")) {
                    row("bag.fill", "تاريخ الشراء", Fmt.dateText(p, hasTime: false))
                    if let m = item.warrantyMonths { row("hourglass", "مدة الضمان", Fmt.months(m)) }
                }
            }

            if item.amount != nil || !item.location.isEmpty {
                Section(header: Text("تفاصيل")) {
                    if let a = item.amount {
                        row("banknote", "المبلغ", Fmt.money(a))
                        if let m = item.monthlyCost, item.repeatUnit != .month || item.repeatEvery != 1 {
                            row("chart.bar", "يعادل شهرياً", Fmt.money((m * 100).rounded() / 100))
                        }
                    }
                    if !item.location.isEmpty {
                        Button { openMaps(item.location) } label: {
                            row("mappin.and.ellipse", "المكان", item.location)
                        }
                    }
                }
            }

            if !item.notes.isEmpty {
                Section(header: Text("ملاحظات")) {
                    Text(item.notes).textSelection(.enabled)
                }
            }

            if !item.photos.isEmpty {
                Section(header: Text("المرفقات")) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(item.photos, id: \.self) { name in
                                Button { viewer = PhotoRef(id: name) } label: { PhotoThumb(name: name, size: 96) }
                                    .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            if !item.history.isEmpty {
                Section(header: Text(item.hasInstallments ? "الأقساط المدفوعة" : "سجل التجديد")) {
                    ForEach(Array(item.history.reversed()), id: \.self) { d in
                        Label(Fmt.dateText(d, hasTime: item.hasTime), systemImage: "checkmark.circle")
                            .foregroundColor(.secondary)
                    }
                }
            }

            Section {
                if item.isDone {
                    Button { store.reopen(item.id) } label: {
                        Label(item.isMedicine ? "رجّع الدواء" : "إرجاعه كغير منجز", systemImage: "arrow.uturn.backward")
                    }
                } else if item.isMedicine {
                    Button { withAnimation { store.complete(item.id) } } label: {
                        Label("أوقفت الدواء / خلص الكورس", systemImage: "stop.circle.fill").foregroundColor(.orange)
                    }
                } else if item.hasInstallments {
                    Button { withAnimation { store.complete(item.id) } } label: {
                        Label(item.installmentsLeft <= 1 ? "دفعت آخر قسط 🎉" : "دفعت هالقسط ✅", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                } else if item.isRecurring {
                    Button { withAnimation { store.complete(item.id) } } label: {
                        Label("تم — جدّده لـ \(Fmt.dateText(item.nextOccurrence(), hasTime: item.hasTime))", systemImage: "arrow.clockwise.circle.fill")
                            .foregroundColor(.green)
                    }
                    Button { showRenew = true } label: {
                        Label("جدّد بتاريخ ثاني…", systemImage: "calendar.badge.plus")
                    }
                } else {
                    Button { withAnimation { store.complete(item.id) } } label: {
                        Label("تم ✅", systemImage: "checkmark.circle.fill").foregroundColor(.green)
                    }
                }
                Button { shareItems = [item.shareText] + item.photos.compactMap { PhotoStore.image($0) } } label: {
                    Label("مشاركة", systemImage: "square.and.arrow.up")
                }
                Button { _ = store.duplicate(item.id) } label: {
                    Label("نسخة مكررة", systemImage: "plus.square.on.square")
                }
                Button(role: .destructive) { confirmDelete = true } label: {
                    Label("حذف", systemImage: "trash").foregroundColor(.red)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("تعديل") { showEdit = true }
            }
        }
        .sheet(isPresented: $showEdit) {
            NavigationView {
                ItemEditor(item: item, isNew: false, isPushed: false) { showEdit = false }
            }
            .environmentObject(store)
            .environment(\.layoutDirection, .rightToLeft)
            .environment(\.locale, Fmt.locale)
            .environment(\.calendar, Fmt.greg)
        }
        .sheet(isPresented: $showRenew) {
            RenewSheet(item: item) { date in
                store.complete(item.id, newDate: date)
                showRenew = false
            } onCancel: { showRenew = false }
            .environment(\.layoutDirection, .rightToLeft)
            .environment(\.locale, Fmt.locale)
            .environment(\.calendar, Fmt.greg)
        }
        .sheet(isPresented: Binding(get: { shareItems != nil }, set: { if !$0 { shareItems = nil } })) {
            ShareSheet(items: shareItems ?? [])
        }
        .fullScreenCover(item: $viewer) { PhotoViewer(name: $0.id) }
        .confirmationDialog("متأكد تبي تحذف «\(item.title)»؟", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("حذف", role: .destructive) {
                presentationMode.wrappedValue.dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { store.delete(item.id) }
            }
            Button("إلغاء", role: .cancel) {}
        }
    }

    private func row(_ icon: String, _ title: String, _ value: String) -> some View {
        HStack {
            Label(title, systemImage: icon).foregroundColor(.secondary)
            Spacer()
            Text(value).foregroundColor(.primary).multilineTextAlignment(.trailing)
        }
    }

    private func openMaps(_ place: String) {
        let q = place.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? place
        if let url = URL(string: place.hasPrefix("http") ? place : "http://maps.apple.com/?q=\(q)") {
            UIApplication.shared.open(url)
        }
    }
}

struct RenewSheet: View {
    let item: Item
    let onRenew: (Date) -> Void
    let onCancel: () -> Void
    @State private var date: Date
    @State private var hijri = false

    init(item: Item, onRenew: @escaping (Date) -> Void, onCancel: @escaping () -> Void) {
        self.item = item
        self.onRenew = onRenew
        self.onCancel = onCancel
        _date = State(initialValue: item.nextOccurrence())
    }

    var body: some View {
        NavigationView {
            Form {
                Section(footer: Text("التاريخ الحالي: \(Fmt.dateText(item.date, hasTime: item.hasTime)) — بعد التجديد يصير الموعد الجديد ويرجع التنبيه تلقائي.")) {
                    Picker("التقويم", selection: $hijri) {
                        Text("ميلادي").tag(false)
                        Text("هجري").tag(true)
                    }
                    .pickerStyle(.segmented)
                    DatePicker("الانتهاء الجديد", selection: $date,
                               displayedComponents: item.hasTime ? [.date, .hourAndMinute] : [.date])
                        .environment(\.calendar, hijri ? Fmt.hijriCalendar : Fmt.greg)
                        .environment(\.locale, hijri ? Fmt.hijriLocale : Fmt.locale)
                        .id(hijri)
                    Text(hijri ? Fmt.dateText(date, hasTime: false, long: true) : Fmt.hijriText(date))
                        .font(.footnote).foregroundColor(.secondary)
                }
            }
            .navigationTitle("تجديد")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء", action: onCancel) }
                ToolbarItem(placement: .confirmationAction) { Button("جدّد") { onRenew(date) } }
            }
        }
    }
}
