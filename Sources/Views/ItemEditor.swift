import SwiftUI

struct ItemEditor: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var assets = AssetStore.shared
    @State private var draft: Item
    @State private var amountText: String
    @State private var hijri = false
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var addedPhotos: [String] = []
    @State private var removedPhotos: [String] = []
    @State private var usePurchaseDate: Bool

    let isNew: Bool
    let isPushed: Bool
    let onFinish: () -> Void

    init(item: Item, isNew: Bool, isPushed: Bool, onFinish: @escaping () -> Void) {
        _draft = State(initialValue: item)
        _amountText = State(initialValue: item.amount.map { $0.rounded() == $0 ? String(Int($0)) : String($0) } ?? "")
        _usePurchaseDate = State(initialValue: item.purchaseDate != nil)
        self.isNew = isNew
        self.isPushed = isPushed
        self.onFinish = onFinish
    }

    var body: some View {
        Form {
            Section {
                TextField(draft.isPurchaseInvoice ? "اسم الفاتورة أو المشتريات" : "العنوان (مثلاً: استمارة الكامري)", text: $draft.title)
                    .font(.headline)
                if !draft.isPurchaseInvoice {
                    Picker(selection: $draft.category) {
                        ForEach(Category.allCases) { c in
                            Label(c.title, systemImage: c.icon).tag(c)
                        }
                    } label: {
                        Label("النوع", systemImage: draft.category.icon)
                    }
                }
                if draft.category == .task {
                    Toggle(isOn: $draft.isHighPriority) { Label("أولوية عالية", systemImage: "flag.fill") }
                }
            }

            if !assets.records.isEmpty {
                Section(header: Text("ربط بملف")) {
                    Picker("السيارة أو الجهاز", selection: $draft.assetID) {
                        Text("بدون ربط").tag(nil as UUID?)
                        ForEach(assets.records) { asset in
                            Label(asset.name, systemImage: asset.kind.icon).tag(Optional(asset.id))
                        }
                    }
                }
            }

            if draft.category == .warranty {
                warrantySection
            }

            if draft.isPurchaseInvoice {
                Section(header: Text("تفاصيل الشراء")) {
                    DatePicker("تاريخ الشراء", selection: $draft.date, displayedComponents: .date)
                }
            } else if draft.isMedicine {
                medicineSection
            } else {
                dateSection
                repeatSection
                if draft.category == .bill || draft.hasInstallments {
                    installmentsSection
                }
                remindersSection
            }

            Section(header: Text("تفاصيل إضافية")) {
                HStack {
                    Label("المبلغ", systemImage: "banknote")
                    TextField("اختياري", text: $amountText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                    Text("ر.س").foregroundColor(.secondary)
                }
                HStack {
                    Label("المكان", systemImage: "mappin.and.ellipse")
                    TextField("اختياري", text: $draft.location)
                        .multilineTextAlignment(.trailing)
                }
                ZStack(alignment: .topLeading) {
                    if draft.notes.isEmpty {
                        Text("ملاحظات (رقم اللوحة، رقم الطلب، اسم الدكتور…)")
                            .foregroundColor(Color(.placeholderText))
                            .padding(.top, 8)
                            .padding(.leading, 4)
                    }
                    TextEditor(text: $draft.notes)
                        .frame(minHeight: 90)
                }
            }

            photosSection
        }
        .themedList()
        .navigationTitle(draft.isPurchaseInvoice ? (isNew ? "فاتورة شراء" : "تعديل الفاتورة") : (isNew ? "جديد" : "تعديل"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if !isPushed {
                    Button("إلغاء") { cancel() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("حفظ") { save() }
                    .font(.headline)
                    .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .sheet(isPresented: $showCamera) { CameraPicker { addPhoto($0) }.ignoresSafeArea() }
        .sheet(isPresented: $showLibrary) { LibraryPicker { addPhoto($0) } }
        .onChange(of: draft.purchaseDate) { _ in recomputeWarranty() }
        .onChange(of: draft.warrantyMonths) { _ in recomputeWarranty() }
        .onChange(of: draft.category) { c in
            if c == .medicine && draft.doseTimes.isEmpty { draft.doseTimes = [9 * 60]; draft.reminders = [] }
        }
        .onChange(of: draft.hasTime) { has in
            if !has { draft.reminders = draft.reminders.filter { $0 == 0 || $0 >= 1440 } }
            if draft.reminders.isEmpty { draft.reminders = [has ? 60 : 1440] }
        }
    }

    // MARK: Sections

    private var remindersSection: some View {
        Section(header: Text("التنبيهات")) {
            NavigationLink(destination: ReminderPicker(selection: $draft.reminders, hasTime: draft.hasTime)) {
                HStack {
                    Label("ذكّرني", systemImage: "bell.badge.fill")
                    Spacer()
                    Text(ReminderOption.summary(draft.reminders, hasTime: draft.hasTime))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }

    private var medicineSection: some View {
        Group {
            Section(header: Text("الجرعة")) {
                HStack {
                    Label("الكمية", systemImage: "pills")
                    TextField("مثلاً: حبة بعد الأكل", text: $draft.dosage)
                        .multilineTextAlignment(.trailing)
                }
            }
            Section(header: Text("أوقات الجرعات"), footer: Text("يجيك تنبيه بكل جرعة وفيه زر «أخذته ✅».")) {
                ForEach(draft.doseTimes.indices, id: \.self) { i in
                    doseTimeRow(i)
                }
                Button {
                    let last = draft.doseTimes.max() ?? 8 * 60
                    draft.doseTimes.append(min(23 * 60 + 30, last + 4 * 60))
                } label: { Label("أضف جرعة", systemImage: "plus.circle.fill") }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        presetDoses("مرة", [9 * 60])
                        presetDoses("مرتين", [9 * 60, 21 * 60])
                        presetDoses("3 مرات", [8 * 60, 14 * 60, 20 * 60])
                        presetDoses("كل 8 ساعات", [7 * 60, 15 * 60, 23 * 60])
                        presetDoses("4 مرات", [8 * 60, 12 * 60, 16 * 60, 20 * 60])
                    }
                }
            }
            Section(header: Text("المدة")) {
                DatePicker("يبدأ من", selection: $draft.date, displayedComponents: .date)
                Toggle("لمدة محددة", isOn: Binding(
                    get: { draft.endDate != nil },
                    set: { on in
                        draft.endDate = on ? Fmt.greg.date(byAdding: .day, value: 6, to: Fmt.greg.startOfDay(for: draft.date)) : nil
                    }))
                if draft.endDate != nil {
                    Stepper(value: courseDaysBinding, in: 1...365) {
                        HStack {
                            Text("عدد الأيام")
                            Spacer()
                            Text(Fmt.days(courseDays)).foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func doseTimeRow(_ i: Int) -> some View {
        let binding = Binding<Date>(
            get: { AppSettings.date(fromMinutes: draft.doseTimes.indices.contains(i) ? draft.doseTimes[i] : 540) },
            set: { if draft.doseTimes.indices.contains(i) { draft.doseTimes[i] = AppSettings.minutes(from: $0) } })
        return HStack {
            DatePicker("جرعة \(i + 1)", selection: binding, displayedComponents: .hourAndMinute)
            if draft.doseTimes.count > 1 {
                Button {
                    if draft.doseTimes.indices.contains(i) { draft.doseTimes.remove(at: i) }
                } label: {
                    Image(systemName: "minus.circle.fill").foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var courseDays: Int {
        guard let e = draft.endDate else { return 7 }
        let d = Fmt.greg.dateComponents([.day], from: Fmt.greg.startOfDay(for: draft.date), to: Fmt.greg.startOfDay(for: e)).day ?? 0
        return max(1, d + 1)
    }

    private var courseDaysBinding: Binding<Int> {
        Binding(get: { courseDays },
                set: { draft.endDate = Fmt.greg.date(byAdding: .day, value: $0 - 1, to: Fmt.greg.startOfDay(for: draft.date)) })
    }

    private func presetDoses(_ title: String, _ times: [Int]) -> some View {
        Button { draft.doseTimes = times } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Capsule().fill(Color.red.opacity(0.12)))
                .foregroundColor(.red)
        }
        .buttonStyle(.plain)
    }

    private var installmentsSection: some View {
        Section(header: Text("الأقساط"),
                footer: Text(draft.hasInstallments ? installmentsFooter : "لو هي أقساط بعدد محدد، فعّلها وأحسب لك الباقي.")) {
            Toggle("عدد أقساط محدد", isOn: Binding(
                get: { draft.hasInstallments },
                set: { on in
                    draft.installmentsTotal = on ? 12 : nil
                    if on && draft.repeatUnit == .none { draft.repeatUnit = .month; draft.repeatEvery = 1 }
                }))
            if draft.hasInstallments {
                Stepper(value: totalBinding, in: 1...360) {
                    HStack {
                        Text("عدد الأقساط")
                        Spacer()
                        Text("\(draft.installmentsTotal ?? 12)").foregroundColor(.secondary)
                    }
                }
                Stepper(value: $draft.installmentsPaidBefore, in: 0...max(0, (draft.installmentsTotal ?? 12) - 1)) {
                    HStack {
                        Text("دفعت منها قبل")
                        Spacer()
                        Text("\(draft.installmentsPaidBefore)").foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private var totalBinding: Binding<Int> {
        Binding(get: { draft.installmentsTotal ?? 12 },
                set: { v in
                    draft.installmentsTotal = v
                    draft.installmentsPaidBefore = min(draft.installmentsPaidBefore, max(0, v - 1))
                })
    }

    private var installmentsFooter: String {
        var it = draft
        it.amount = Fmt.parseNumber(amountText)
        var text = "باقي \(Fmt.count(it.installmentsLeft, one: "قسط واحد", two: "قسطين", few: "أقساط", many: "قسط"))"
        if let r = it.remainingAmount, r > 0 { text += " = \(Fmt.money(r))" }
        if let last = it.lastInstallmentDate { text += " • آخر قسط \(Fmt.dateText(last, hasTime: false))" }
        return text + ". حط مبلغ القسط تحت في «المبلغ»."
    }

    private var warrantySection: some View {
        Section(header: Text("الضمان"), footer: Text("حط تاريخ الشراء ومدة الضمان، وأنا أحسب تاريخ الانتهاء.")) {
            Toggle("احسب من تاريخ الشراء", isOn: $usePurchaseDate.afterSet { on in
                if on {
                    if draft.purchaseDate == nil { draft.purchaseDate = Fmt.greg.startOfDay(for: Date()) }
                    if draft.warrantyMonths == nil { draft.warrantyMonths = 24 }
                    recomputeWarranty()
                } else {
                    draft.purchaseDate = nil
                    draft.warrantyMonths = nil
                }
            })
            if usePurchaseDate {
                DatePicker("تاريخ الشراء", selection: Binding(
                    get: { draft.purchaseDate ?? Date() },
                    set: { draft.purchaseDate = $0 }), displayedComponents: .date)
                Stepper(value: Binding(get: { draft.warrantyMonths ?? 24 }, set: { draft.warrantyMonths = $0 }), in: 1...120) {
                    HStack {
                        Text("مدة الضمان")
                        Spacer()
                        Text(warrantyLabel(draft.warrantyMonths ?? 24)).foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private var dateSection: some View {
        Section(header: Text(draft.category == .warranty ? "ينتهي الضمان" : (draft.category == .appointment || draft.category == .task ? "الموعد" : "تاريخ الانتهاء / الاستحقاق")),
                footer: Text(otherCalendarText)) {
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
                .disabled(draft.category == .warranty && usePurchaseDate)
            quickDates
        }
    }

    private var quickDates: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                quick("بكرة", .day, 1)
                quick("أسبوع", .day, 7)
                quick("شهر", .month, 1)
                quick("3 أشهر", .month, 3)
                quick("6 أشهر", .month, 6)
                quick("سنة", .year, 1)
                quick("سنتين", .year, 2)
            }
        }
    }

    private func quick(_ title: String, _ comp: Calendar.Component, _ value: Int) -> some View {
        Button {
            let base = draft.hasTime ? Date() : Fmt.greg.startOfDay(for: Date())
            if let d = Fmt.greg.date(byAdding: comp, value: value, to: base) { draft.date = d }
        } label: {
            Text("+ \(title)")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Capsule().fill(Color.brand.opacity(0.12)))
                .foregroundColor(.brand)
        }
        .buttonStyle(.plain)
        .disabled(draft.category == .warranty && usePurchaseDate)
    }

    private var repeatSection: some View {
        Section(header: Text("التكرار"),
                footer: Text(draft.isRecurring ? "لما تعلّمه «تم» ينتقل تلقائياً للموعد الجاي ويرجع يذكّرك." : "")) {
            Picker(selection: $draft.repeatUnit) {
                ForEach(RepeatUnit.allCases) { Text($0.title).tag($0) }
            } label: {
                Label("يتكرر", systemImage: "repeat")
            }
            if draft.isRecurring {
                Stepper(value: $draft.repeatEvery, in: 1...36) {
                    HStack {
                        Text("كل")
                        Spacer()
                        Text(draft.repeatLabel).foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private var photosSection: some View {
        Section(header: Text("صور ومرفقات"), footer: Text("صوّر الاستمارة أو الفاتورة أو كرت الضمان عشان تلقاها وقت الحاجة.")) {
            if !draft.photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(draft.photos, id: \.self) { name in
                            ZStack(alignment: .topTrailing) {
                                PhotoThumb(name: name)
                                Button { removePhoto(name) } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.title3)
                                        .foregroundColor(.white)
                                        .shadow(radius: 2)
                                        .padding(4)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            Button { showCamera = true } label: { Label("صوّر الحين", systemImage: "camera.fill") }
            Button { showLibrary = true } label: { Label("اختر من الصور", systemImage: "photo.on.rectangle") }
        }
    }

    // MARK: Helpers

    private var otherCalendarText: String {
        hijri ? "يوافق: \(Fmt.dateText(draft.date, hasTime: false, long: true))" : "يوافق: \(Fmt.hijriText(draft.date))"
    }

    private func warrantyLabel(_ m: Int) -> String {
        if m % 12 == 0 { return Fmt.years(m / 12) }
        return Fmt.months(m)
    }

    private func recomputeWarranty() {
        guard draft.category == .warranty, usePurchaseDate, let end = draft.warrantyEnd else { return }
        draft.date = end
    }

    private func addPhoto(_ image: UIImage) {
        guard let name = PhotoStore.save(image) else { return }
        draft.photos.append(name)
        addedPhotos.append(name)
    }

    private func removePhoto(_ name: String) {
        draft.photos.removeAll { $0 == name }
        if let i = addedPhotos.firstIndex(of: name) {
            addedPhotos.remove(at: i)
            PhotoStore.delete(name)
        } else {
            removedPhotos.append(name)
        }
    }

    private func save() {
        draft.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.amount = Fmt.parseNumber(amountText)
        if draft.isPurchaseInvoice {
            draft.isDone = true
            draft.doneAt = draft.date
            let purchaseLog = draft.logs.firstIndex { $0.kind == .purchase }
            if let amount = draft.amount {
                if let index = purchaseLog {
                    draft.logs[index].cost = amount
                    draft.logs[index].date = draft.date
                } else {
                    draft.logs.append(LogEntry(date: draft.date, kind: .purchase, cost: amount))
                }
            } else if let index = purchaseLog {
                draft.logs.remove(at: index)
            }
        }
        if draft.category != .warranty || !usePurchaseDate {
            if draft.category != .warranty { draft.purchaseDate = nil; draft.warrantyMonths = nil }
        }
        if draft.isMedicine {
            draft.hasTime = false
            draft.repeatUnit = .none
            if draft.doseTimes.isEmpty { draft.doseTimes = [9 * 60] }
            draft.doseTimes = Array(Set(draft.doseTimes)).sorted()
        } else {
            draft.doseTimes = []
        }
        if draft.category != .bill && !draft.isRecurring { draft.installmentsTotal = nil }
        removedPhotos.forEach(PhotoStore.delete)
        store.upsert(draft)
        if isNew, !draft.isPurchaseInvoice {
            NotificationManager.shared.requestAuthorization()
        }
        onFinish()
    }

    private func cancel() {
        addedPhotos.forEach(PhotoStore.delete)
        onFinish()
    }
}

struct ReminderPicker: View {
    @Binding var selection: [Int]
    let hasTime: Bool

    var body: some View {
        List {
            Section(footer: Text(hasTime ? "" : "للأشياء اللي بدون وقت، التنبيه يجيك الساعة اللي تحددها في الإعدادات.")) {
                ForEach(ReminderOption.options(hasTime: hasTime), id: \.self) { m in
                    Button {
                        if let i = selection.firstIndex(of: m) { selection.remove(at: i) } else { selection.append(m) }
                    } label: {
                        HStack {
                            Text(ReminderOption.label(m, hasTime: hasTime)).foregroundColor(.primary)
                            Spacer()
                            if selection.contains(m) {
                                Image(systemName: "checkmark").foregroundColor(.brand).font(.body.bold())
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("التنبيهات")
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension Binding {
    /// Runs `handler` after the value is set.
    func afterSet(_ handler: @escaping (Value) -> Void) -> Binding<Value> {
        Binding(get: { wrappedValue }, set: { newValue in
            wrappedValue = newValue
            handler(newValue)
        })
    }
}


