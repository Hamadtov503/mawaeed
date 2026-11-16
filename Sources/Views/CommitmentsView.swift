import SwiftUI

/// التزاماتي: search, a centred plus, then «التزاماتك الحالية» and «التزاماتك المسددة» (each only once
/// it has something in it). Laid out like the appointments and tasks pages; a right-to-left swipe goes home.
struct CommitmentsView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    @State private var query = ""

    private func matches(_ c: Commitment) -> Bool {
        query.isEmpty || c.title.localizedCaseInsensitiveContains(query) || c.notes.localizedCaseInsensitiveContains(query)
    }

    var body: some View {
        let open = store.openCommitments.filter(matches)
        let settled = store.settledCommitments.filter(matches)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(L("التزاماتي", "Commitments")).font(.app(size: 26, .bold)).foregroundColor(Theme.ink).padding(.top, 2)
                SearchField(prompt: L("ابحث في التزاماتك", "Search your commitments"), text: $query)
                AddButton(label: L("التزام جديد", "New commitment"), hint: L("اضغط على علامة + لإضافة التزام لمتابعة سداده", "Tap + to add a commitment and follow its payments"),
                          id: "addCommitment") { router.newCommitment() }

                if !open.isEmpty {
                    BandHeader(title: L("التزاماتك الحالية", "Your current commitments"), count: open.count, color: Theme.burgundy)
                    ForEach(open) { CommitmentCard(item: $0) }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                if !settled.isEmpty {
                    BandHeader(title: L("التزاماتك المسددة", "Your paid-off commitments"), count: settled.count, color: Theme.slate)
                    ForEach(settled) { CommitmentCard(item: $0) }
                        .transition(.opacity)
                }
                if open.isEmpty && settled.isEmpty && !query.isEmpty {
                    Text(L("لا توجد نتائج لـ«\(query)»", "No results for “\(query)”")).font(.app(.subheadline)).foregroundColor(Theme.muted)
                        .frame(maxWidth: .infinity).padding(.top, 8)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 28)
            .frame(maxWidth: 650)
            .frame(maxWidth: .infinity)
            .animation(Router.soft, value: open.map(\.id))
            .animation(Router.soft, value: settled.map(\.id))
        }
        .background(Theme.background.ignoresSafeArea())
        .swipeBackHome()
    }
}

/// A commitment card, built like an appointment card: icon tile, the title with a pill on the same
/// line (the share paid), the amount left and when it is due, then a thin progress bar.
struct CommitmentCard: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    let item: Commitment

    private var tint: Color {
        item.isSettled ? Theme.forest : (item.isOverdue() ? Theme.burgundy : Theme.navy)
    }

    var body: some View {
        HStack(spacing: 12) {
            Tile(icon: item.displayIcon, color: item.isSettled ? Theme.muted : Theme.burgundy, size: 42)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.title.isEmpty ? L("بدون عنوان", "Untitled") : item.title)
                        .font(.app(.headline))
                        .foregroundColor(item.isSettled ? Theme.muted : Theme.ink)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(item.isSettled ? L("مسدد", "Paid off") : Fmt.percent(item.progress))
                        .font(.app(.footnote, .semibold))
                        .foregroundColor(tint)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(tint.opacity(0.12)))
                        .lineLimit(1)
                        .fixedSize()
                }
                Text(item.isSettled
                     ? L("سُدِّد \(Fmt.money(item.total))", "Paid \(Fmt.money(item.total))")
                     : Fmt.joined([L("المتبقي \(Fmt.money(item.remaining))", "\(Fmt.money(item.remaining)) left"), item.dueText]))
                    .font(.app(.subheadline))
                    .foregroundColor(item.isOverdue() ? Theme.burgundy : Theme.muted)
                    .lineLimit(1)
                ProgressBar(value: item.progress, color: tint)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 12)
        .contentShape(Rectangle())
        // A tap rather than a Button, so a sideways swipe over the card doesn't open it.
        .onTapGesture { router.editingCommitment = item }
        .onLongPress {
            let c = item
            router.menu = MenuRequest(title: c.title, actions: [
                MenuAction(title: L("تعديل", "Edit"), icon: "pencil") { router.editingCommitment = c },
                MenuAction(title: L("حذف", "Delete"), icon: "trash", destructive: true) { withAnimation(Router.soft) { store.deleteCommitment(c.id) } },
            ])
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("commitment.\(item.title)")
    }
}

/// A thin rounded bar: the paid share of the total.
struct ProgressBar: View {
    let value: Double
    var color: Color = Theme.forest
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.sand)
                Capsule().fill(color)
                    .frame(width: max(value > 0 ? height : 0, g.size.width * CGFloat(min(1, max(0, value)))))
            }
        }
        .frame(height: height)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: value)
        .accessibilityHidden(true)
    }
}
