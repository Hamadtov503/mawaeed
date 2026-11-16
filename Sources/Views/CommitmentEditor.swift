import SwiftUI

/// Add or edit a commitment (a sheet; cards in a ScrollView, like the task form): title and icon,
/// the total, when it is due (open or by a date), the payments with what is paid and what is left,
/// notes, and delete.
struct CommitmentEditor: View {
    @EnvironmentObject var store: Store
    @State private var draft: Commitment
    @State private var totalText: String
    @State private var dated: Bool
    @State private var payText = ""
    @State private var payDate = Date()
    @State private var picking: Picking? = nil
    @State private var choosingIcon = false
    @State private var menu: MenuRequest? = nil
    let onFinish: () -> Void

    enum Picking { case due, payment }

    init(commitment: Commitment, onFinish: @escaping () -> Void) {
        _draft = State(initialValue: commitment)
        _totalText = State(initialValue: Fmt.amountField(commitment.total))
        _dated = State(initialValue: commitment.due != nil)
        self.onFinish = onFinish
    }

    private var isNew: Bool { store.commitment(draft.id) == nil }
    private var total: Double { Fmt.parseAmount(totalText) ?? 0 }
    private var canSave: Bool { !draft.title.trimmingCharacters(in: .whitespaces).isEmpty && total > 0 }

    /// The draft with the total as typed, for the live figures.
    private var live: Commitment { var c = draft; c.total = total; return c }

    var body: some View {
        AppNavigation {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    card(L("عنوان الالتزام", "Title")) {
                        HStack(spacing: 10) {
                            TextField(L("مثلًا: قرض السيارة", "e.g. Car loan"), text: $draft.title).font(.app(.headline))
                                .accessibilityIdentifier("field.commitmentTitle")
                            iconButton
                        }
                    }

                    card(L("المبلغ الإجمالي", "Total amount")) {
                        HStack(spacing: 8) {
                            TextField(L("المبلغ", "Amount"), text: $totalText)
                                .keyboardType(.decimalPad)
                                .font(.app(.title3, .bold))
                                .accessibilityIdentifier("field.total")
                            Text(L("ر.س", "SAR")).font(.app(.body, .semibold)).foregroundColor(Theme.muted)
                        }
                    }

                    card(L("موعد السداد", "Due")) {
                        HStack(spacing: 6) {
                            segment(L("مفتوح", "Open"), on: !dated, color: Theme.slate) { setDated(false) }
                            segment(L("محدد بتاريخ", "By a date"), on: dated, color: Theme.navy) { setDated(true) }
                        }
                        if dated {
                            PickerRow(title: L("آخر موعد للسداد", "Pay by"), value: Fmt.dateText(dueBinding.wrappedValue, hasTime: false),
                                      icon: "calendar") { open(.due) }
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }

                    card(L("السداد", "Payments")) {
                        summary
                        if !draft.payments.isEmpty {
                            Divider()
                            ForEach(draft.payments.sorted { $0.date > $1.date }) { p in paymentRow(p) }
                        }
                        Divider()
                        addPayment
                    }

                    card(L("ملاحظات", "Notes")) {
                        ZStack(alignment: .topLeading) {
                            if draft.notes.isEmpty {
                                Text(L("الجهة، رقم العقد، تفاصيل إضافية…", "Lender, contract number, more details…"))
                                    .foregroundColor(Theme.muted.opacity(0.7)).padding(.top, 8).padding(.leading, 5)
                            }
                            TextEditor(text: $draft.notes).frame(minHeight: 80).modifier(ClearTextEditorBackground())
                        }
                    }

                    if !isNew {
                        Button(role: .destructive) {
                            menu = MenuRequest(title: L("هل تريد حذف الالتزام؟", "Delete this commitment?"), actions: [
                                MenuAction(title: L("حذف", "Delete"), icon: "trash", destructive: true) {
                                    store.deleteCommitment(draft.id)
                                    onFinish()
                                },
                                MenuAction(title: L("إلغاء", "Cancel"), icon: "xmark") {},
                            ])
                        } label: {
                            Label(L("حذف الالتزام", "Delete commitment"), systemImage: "trash").font(.app(.body, .semibold))
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
                .animation(.spring(response: 0.4, dampingFraction: 0.88), value: dated)
                .animation(.spring(response: 0.4, dampingFraction: 0.88), value: draft.payments.map(\.id))
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(isNew ? L("التزام جديد", "New commitment") : L("تعديل الالتزام", "Edit commitment"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("إلغاء", "Cancel"), action: onFinish) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("حفظ", "Save"), action: save)
                        .disabled(!canSave)
                        .accessibilityIdentifier("button.save")
                }
            }
            .popup(isPresented: $choosingIcon, top: 126) { iconGrid }
            .popup(isPresented: Binding(get: { picking == .due }, set: { if !$0 { picking = nil } })) {
                DayPickerPopup(date: dueBinding, hijri: false) { close() }
            }
            .popup(isPresented: Binding(get: { picking == .payment }, set: { if !$0 { picking = nil } })) {
                DayPickerPopup(date: $payDate, hijri: false) { close() }
            }
            .actionMenu($menu)
        }
    }

    // MARK: Pieces

    /// Paid, left and the share paid, over a progress bar.
    private var summary: some View {
        let c = live
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                figure(L("المسدد", "Paid"), Fmt.money(c.paid), Theme.forest)
                Spacer()
                figure(L("المتبقي", "Left"), Fmt.money(c.remaining), c.isOverdue() ? Theme.burgundy : Theme.navy)
                Spacer()
                figure(L("نسبة السداد", "Paid share"), Fmt.percent(c.progress), Theme.ink)
            }
            ProgressBar(value: c.progress, color: c.isSettled ? Theme.forest : Theme.navy, height: 8)
        }
    }

    private func figure(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.app(.caption)).foregroundColor(Theme.muted)
            Text(value).font(.app(.subheadline, .bold)).foregroundColor(color).lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    private func paymentRow(_ p: Payment) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill").foregroundColor(Theme.forest)
            VStack(alignment: .leading, spacing: 2) {
                Text(Fmt.money(p.amount)).font(.app(.body, .semibold)).foregroundColor(Theme.ink)
                Text(Fmt.dateText(p.date, hasTime: false)).font(.app(.caption)).foregroundColor(Theme.muted)
            }
            Spacer()
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { draft.payments.removeAll { $0.id == p.id } }
            } label: {
                Image(systemName: "trash").font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.burgundy)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Theme.burgundy.opacity(0.1)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("حذف الدفعة", "Remove payment"))
        }
    }

    /// A new payment: the amount, its date (today unless changed), and add.
    private var addPayment: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("إضافة دفعة", "Add a payment")).font(.app(.footnote, .bold)).foregroundColor(Theme.muted)
            HStack(spacing: 8) {
                TextField(L("مبلغ الدفعة", "Payment amount"), text: $payText)
                    .keyboardType(.decimalPad)
                    .font(.app(.body))
                    .accessibilityIdentifier("field.payment")
                Text(L("ر.س", "SAR")).font(.app(.subheadline)).foregroundColor(Theme.muted)
            }
            PickerRow(title: L("تاريخ الدفعة", "Paid on"), value: Fmt.dateText(payDate, hasTime: false), icon: "calendar") { open(.payment) }
            Button(action: addPaymentNow) {
                Label(L("إضافة الدفعة", "Add payment"), systemImage: "plus.circle.fill")
                    .font(.app(.body, .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(Capsule().fill((Fmt.parseAmount(payText) ?? 0) > 0 ? Theme.forest : Theme.forest.opacity(0.4)))
            }
            .buttonStyle(.plain)
            .disabled((Fmt.parseAmount(payText) ?? 0) <= 0)
            .accessibilityIdentifier("button.addPayment")
        }
    }

    private var iconButton: some View {
        Button {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) { choosingIcon = true }
        } label: {
            Image(systemName: draft.displayIcon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Theme.burgundy)
                .frame(width: 42, height: 42)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.burgundy.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("اختر أيقونة", "Choose an icon"))
    }

    private var iconGrid: some View {
        VStack(spacing: 12) {
            Text(L("اختر أيقونة", "Choose an icon")).font(.app(.headline, .bold)).foregroundColor(Theme.ink)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 10) {
                ForEach(Commitment.icons, id: \.self) { name in
                    let on = draft.displayIcon == name
                    Button {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
                            draft.icon = name
                            choosingIcon = false
                        }
                    } label: {
                        Image(systemName: name)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(on ? .white : Theme.burgundy)
                            .frame(width: 50, height: 50)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(on ? Theme.burgundy : Theme.burgundy.opacity(0.1)))
                    }
                    .buttonStyle(.plain)
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

    // MARK: Actions

    private var dueBinding: Binding<Date> {
        Binding(get: { draft.due ?? Fmt.greg.date(byAdding: .month, value: 1, to: Date()) ?? Date() },
                set: { draft.due = $0 })
    }

    private func setDated(_ on: Bool) {
        dated = on
        draft.due = on ? dueBinding.wrappedValue : nil
    }

    private func open(_ p: Picking) {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) { picking = p }
    }

    private func close() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) { picking = nil }
    }

    private func addPaymentNow() {
        guard let amount = Fmt.parseAmount(payText), amount > 0 else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            draft.payments.append(Payment(amount: amount, date: payDate))
        }
        payText = ""
        payDate = Date()
    }

    private func save() {
        draft.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.total = total
        if !dated { draft.due = nil }
        // A payment typed but not added yet still counts.
        if let amount = Fmt.parseAmount(payText), amount > 0 { draft.payments.append(Payment(amount: amount, date: payDate)) }
        store.upsertCommitment(draft)
        onFinish()
    }
}
