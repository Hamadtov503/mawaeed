import SwiftUI

struct ItemEditor: View {
    @EnvironmentObject var store: Store
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
                TextField("العنوان (مثلاً: استمارة الكامري)", text: $draft.title)
                    .font(.headline)
                Picker(selection: $draft.category) {
                    ForEach(Category.allCases) { c in
                        Label(c.title, systemImage: c.icon).tag(c)
                    }
                } label: {
                    Label("النوع", systemImage: draft.category.icon)
                }
            }

            if draft.category == .warranty {
                warrantySection
            }

            dateSection
            repeatSection

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
        .navigationTitle(isNew ? "جديد" : "تعديل")
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
        .onChange(of: draft.hasTime) { has in
            if !has { draft.reminders = draft.reminders.filter { $0 == 0 || $0 >= 1440 } }
            if draft.reminders.isEmpty { draft.reminders = [has ? 60 : 1440] }
        }
    }

    // MARK: Sections

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
        if draft.category != .warranty || !usePurchaseDate {
            if draft.category != .warranty { draft.purchaseDate = nil; draft.warrantyMonths = nil }
        }
        removedPhotos.forEach(PhotoStore.delete)
        store.upsert(draft)
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
