import SwiftUI

struct AssetsView: View {
    @ObservedObject private var assets = AssetStore.shared
    @EnvironmentObject private var store: Store
    @State private var kind: AssetKind = .vehicle
    @State private var search = ""
    @State private var editing: Asset?

    private var filtered: [Asset] {
        assets.records.filter {
            $0.kind == kind && (search.isEmpty || [$0.name, $0.model, $0.identifier].joined(separator: " ").localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    PageHeader(title: "ممتلكاتي", subtitle: "لكل سيارة وجهاز ملف يجمع كل تفاصيله")
                    Picker("نوع الممتلكات", selection: $kind) {
                        Text("سياراتي").tag(AssetKind.vehicle)
                        Text("أجهزتي").tag(AssetKind.device)
                    }.pickerStyle(.segmented)
                    if filtered.isEmpty {
                        EmptyStateView(icon: kind.icon, title: search.isEmpty ? "ابدأ بإضافة \(kind.title)" : "ما فيه نتائج",
                                       message: "اجمع الصيانة والضمان والوثائق والمصاريف في ملف واحد.")
                            .card()
                    }
                    ForEach(filtered) { asset in
                        NavigationLink(destination: AssetDetailView(assetID: asset.id)) {
                            assetCard(asset)
                        }.buttonStyle(.plain)
                    }
                    Button {
                        var asset = Asset(); asset.kind = kind; editing = asset
                    } label: {
                        Label("إضافة \(kind.title)", systemImage: "plus.circle.fill")
                            .font(.headline).frame(maxWidth: .infinity).padding(18)
                            .foregroundColor(.white).background(RoundedRectangle(cornerRadius: 20).fill(Color.brand))
                    }
                }.padding(16)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("الأجهزة والسيارات")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "الاسم، الموديل، اللوحة أو الرقم التسلسلي")
        .sheet(item: $editing) { AssetEditor(asset: $0) }
        .alert("تعذّر الحفظ", isPresented: Binding(get: { assets.errorMessage != nil }, set: { if !$0 { assets.errorMessage = nil } })) {
            Button("تمام") { assets.errorMessage = nil }
        } message: { Text(assets.errorMessage ?? "") }
    }

    private func assetCard(_ asset: Asset) -> some View {
        let pending = store.activeSorted.filter { $0.assetID == asset.id }
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Tile(icon: asset.kind.icon, size: 54)
                VStack(alignment: .leading, spacing: 5) {
                    Text(asset.name).font(.title3.bold()).foregroundColor(Theme.ink)
                    Text([asset.model, asset.identifier].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption).foregroundColor(Theme.muted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.left").font(.caption.bold()).foregroundColor(Theme.muted)
            }
            Divider()
            if let next = pending.first {
                HStack(alignment: .top) {
                    Text(next.title).font(.subheadline).foregroundColor(Theme.ink)
                    Spacer()
                    StatusPill(text: Fmt.countdown(to: next.date, hasTime: next.hasTime), urgency: next.urgency())
                }
            } else {
                Label("ما فيه مواعيد معلّقة", systemImage: "checkmark.circle")
                    .font(.subheadline).foregroundColor(Theme.muted)
            }
            Text("\(pending.count) موعد للمتابعة").font(.caption).foregroundColor(Theme.muted)
        }.card(padding: 20)
    }
}

struct AssetDetailView: View {
    let assetID: UUID
    @ObservedObject private var assets = AssetStore.shared
    @EnvironmentObject private var store: Store
    @Environment(\.presentationMode) private var presentation
    @State private var editing: Asset?
    @State private var newItem: Item?
    @State private var confirmDelete = false

    private var linked: [Item] { store.items.filter { $0.assetID == assetID }.sorted { $0.date < $1.date } }

    var body: some View {
        Group {
            if let asset = assets.asset(assetID) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 14) {
                            Tile(icon: asset.kind.icon, size: 64)
                            PageHeader(title: asset.name, subtitle: asset.model)
                            if !asset.identifier.isEmpty {
                                Label(asset.identifier, systemImage: asset.kind == .vehicle ? "car" : "barcode")
                                    .font(.subheadline).foregroundColor(Theme.muted)
                            }
                            if !asset.notes.isEmpty { Text(asset.notes).font(.subheadline).foregroundColor(Theme.muted) }
                        }.card(padding: 22)

                        HStack {
                            Label("إجمالي السجل", systemImage: "banknote")
                            Spacer()
                            Text(Fmt.money(linked.flatMap { $0.logs }.compactMap { $0.cost }.reduce(0, +))).bold()
                        }.font(.subheadline).card()

                        Text("إضافة للملف").font(.headline).foregroundColor(Theme.ink)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            Button {
                                newItem = Item.purchaseInvoice(assetID: asset.id)
                            } label: {
                                Label("فاتورة شراء", systemImage: "doc.text.fill").font(.subheadline.bold())
                                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                                    .foregroundColor(Color.brand).background(RoundedRectangle(cornerRadius: 18).fill(Theme.tile))
                            }.buttonStyle(.plain)
                            quickAdd("صيانة", .maintenance, "wrench.and.screwdriver.fill", asset)
                            quickAdd("ضمان", .warranty, "checkmark.shield.fill", asset)
                            quickAdd(asset.kind == .vehicle ? "فحص دوري" : "وثيقة", .document, "doc.text.fill", asset)
                            quickAdd("مهمة", .task, "checklist", asset)
                        }
                        let active = linked.filter { !$0.isDone }
                        SectionBlock(title: "المواعيد والضمانات", icon: "calendar", color: .brand, count: active.count) {
                            if active.isEmpty {
                                Text("أضف موعدًا من الأزرار أعلاه، أو اربط عنصرًا موجودًا من صفحة تعديله.")
                                    .font(.subheadline).foregroundColor(Theme.muted).card()
                            }
                            ForEach(active) { ItemCard(item: $0) }
                        }
                        let completed = linked.filter { $0.isDone }
                        if !completed.isEmpty {
                            SectionBlock(title: "المنجزة", icon: "checkmark.circle", color: .green, count: completed.count) {
                                ForEach(completed) { ItemCard(item: $0) }
                            }
                        }
                        let logs = linked.flatMap { item in item.logs.map { (item: item, log: $0) } }.sorted { $0.log.date > $1.log.date }
                        if !logs.isEmpty {
                            SectionBlock(title: "سجل الصيانة والمصاريف", icon: "clock.arrow.circlepath", color: .brand, count: logs.count) {
                                ForEach(logs, id: \.log.id) { entry in
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(entry.item.title).font(.headline)
                                        Text("\(entry.log.kind.title) · \(Fmt.dateText(entry.log.date, hasTime: false))")
                                            .font(.caption).foregroundColor(Theme.muted)
                                        if let cost = entry.log.cost { Text(Fmt.money(cost)).font(.subheadline.bold()) }
                                        if !entry.log.note.isEmpty { Text(entry.log.note).font(.subheadline) }
                                    }.frame(maxWidth: .infinity, alignment: .leading).card()
                                }
                            }
                        }
                    }.padding(16)
                }.background(Theme.background.ignoresSafeArea())
                .navigationTitle("ملف \(asset.kind.title)")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Menu {
                            Button("تعديل البيانات") { editing = asset }
                            Button("حذف الملف", role: .destructive) { confirmDelete = true }
                        } label: { Image(systemName: "ellipsis.circle") }
                    }
                }
            } else { Text("هذا الملف غير موجود") }
        }
        .sheet(item: $editing) { AssetEditor(asset: $0) }
        .sheet(item: $newItem) { item in
            NavigationView {
                ItemEditor(item: item, isNew: true, isPushed: false) { newItem = nil }
            }.navigationViewStyle(.stack)
        }
        .confirmationDialog("حذف ملف الممتلكات؟", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("حذف الملف فقط", role: .destructive) {
                if assets.delete(assetID) { presentation.wrappedValue.dismiss() }
            }
        } message: { Text("تبقى المواعيد والضمانات وسجلاتها محفوظة ضمن أشيائي.") }
    }

    private func quickAdd(_ title: String, _ category: Category, _ icon: String, _ asset: Asset) -> some View {
        Button {
            var item = Item()
            item.title = "\(title) — \(asset.name)"
            item.category = category
            item.assetID = asset.id
            if category == .document || category == .warranty { item.reminders = [43200, 10080, 1440] }
            newItem = item
        } label: {
            Label(title, systemImage: icon).font(.subheadline.bold())
                .frame(maxWidth: .infinity).padding(.vertical, 16)
                .foregroundColor(Color.brand).background(RoundedRectangle(cornerRadius: 18).fill(Theme.tile))
        }.buttonStyle(.plain)
    }
}

struct AssetEditor: View {
    @ObservedObject private var assets = AssetStore.shared
    @Environment(\.presentationMode) private var presentation
    @State var asset: Asset

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("البيانات الأساسية")) {
                    TextField("الاسم (مثلاً: الكامري أو مكيف الصالة)", text: $asset.name)
                    Picker("النوع", selection: $asset.kind) {
                        ForEach(AssetKind.allCases) { Text($0.title).tag($0) }
                    }
                    TextField("الماركة والموديل", text: $asset.model)
                    TextField(asset.kind == .vehicle ? "رقم اللوحة" : "الرقم التسلسلي", text: $asset.identifier)
                }
                Section(header: Text("ملاحظات")) { TextEditor(text: $asset.notes).frame(minHeight: 100) }
            }.themedList()
            .navigationTitle("بيانات الممتلكات").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { presentation.wrappedValue.dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("حفظ") {
                        asset.name = asset.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        if assets.save(asset) { presentation.wrappedValue.dismiss() }
                    }.disabled(asset.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("تعذّر الحفظ", isPresented: Binding(get: { assets.errorMessage != nil }, set: { if !$0 { assets.errorMessage = nil } })) {
                Button("تمام") { assets.errorMessage = nil }
            } message: { Text(assets.errorMessage ?? "") }
        }.navigationViewStyle(.stack)
    }
}

