import SwiftUI

/// Pick a ready-made template, then fill in the details.
struct AddFlowView: View {
    @Binding var isPresented: Bool
    var section: MainSection? = nil
    @EnvironmentObject var store: Store

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if section == nil || section == .finance {
                        NavigationLink(destination: ItemEditor(item: Item.purchaseInvoice(), isNew: true, isPushed: true,
                                                               onFinish: { isPresented = false })) {
                            SettingsTile(title: "فاتورة شراء", subtitle: "احفظ الفاتورة واربطها بجهاز أو سيارة", icon: "doc.text.fill", tint: MainSection.finance.color)
                        }.buttonStyle(.plain)
                    }
                    ForEach(Template.groups.filter { !templates($0.templates).isEmpty }) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(group.title)
                                .font(.headline)
                                .padding(.horizontal, 4)
                            LazyVGrid(columns: columns, spacing: 10) {
                                ForEach(templates(group.templates)) { t in
                                    NavigationLink(destination: ItemEditor(item: t.makeItem(), isNew: true, isPushed: true,
                                                                           onFinish: { isPresented = false })) {
                                        TemplateCard(template: t)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("وش تبي تسجّل؟")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إلغاء") { isPresented = false }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func templates(_ items: [Template]) -> [Template] {
        guard let section = section else { return items }
        return items.filter { section.includes($0.makeItem()) }
    }
}

struct TemplateCard: View {
    let template: Template

    var body: some View {
        VStack(spacing: 8) {
            Tile(icon: template.icon, color: template.category.color, size: 46)
            Text(template.name)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .frame(height: 32)
                .foregroundColor(Theme.ink)
        }
        .frame(maxWidth: .infinity)
        .card(padding: 10)
    }
}


