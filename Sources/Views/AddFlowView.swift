import SwiftUI

/// Pick a ready-made template, then fill in the details.
struct AddFlowView: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var store: Store

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(Template.groups) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(group.title)
                                .font(.headline)
                                .padding(.horizontal, 4)
                            LazyVGrid(columns: columns, spacing: 10) {
                                ForEach(group.templates) { t in
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
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
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
}

struct TemplateCard: View {
    let template: Template

    var body: some View {
        VStack(spacing: 8) {
            IconBadge(icon: template.icon, color: template.category.color, size: 44)
            Text(template.name)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .frame(height: 32)
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
    }
}
