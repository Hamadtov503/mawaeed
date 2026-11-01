import SwiftUI
import UIKit
import PhotosUI

struct IconBadge: View {
    let icon: String
    let color: Color
    var size: CGFloat = 40

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(color.opacity(0.15))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: icon)
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundColor(color)
            )
    }
}

struct ItemRow: View {
    let item: Item

    var body: some View {
        let u = item.urgency()
        HStack(spacing: 12) {
            IconBadge(icon: item.displayIcon, color: item.category.color)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.title.isEmpty ? "بدون عنوان" : item.title)
                        .font(.body.weight(.semibold))
                        .strikethrough(item.isDone)
                        .foregroundColor(item.isDone ? .secondary : .primary)
                        .lineLimit(1)
                    if item.isRecurring {
                        Image(systemName: "repeat").font(.caption2).foregroundColor(.secondary)
                    }
                    if !item.photos.isEmpty {
                        Image(systemName: "paperclip").font(.caption2).foregroundColor(.secondary)
                    }
                }
                Text(Fmt.dateText(item.date, hasTime: item.hasTime))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 4)
            if item.isDone {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
            } else {
                Text(Fmt.countdown(to: item.date, hasTime: item.hasTime))
                    .font(.caption.weight(.bold))
                    .foregroundColor(u.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(u.color.opacity(0.12)))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.vertical, 2)
    }
}

/// A list row that opens the item and supports swipe-to-complete / delete.
struct ItemLink: View {
    @EnvironmentObject var store: Store
    let item: Item

    var body: some View {
        NavigationLink(destination: ItemDetailView(itemID: item.id)) {
            ItemRow(item: item)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if item.isDone {
                Button { store.reopen(item.id) } label: { Label("إرجاع", systemImage: "arrow.uturn.backward") }
                    .tint(.gray)
            } else {
                Button { withAnimation { store.complete(item.id) } } label: {
                    Label(item.isRecurring ? "تجديد" : "تم", systemImage: item.isRecurring ? "arrow.clockwise" : "checkmark")
                }
                .tint(.green)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) { withAnimation { store.delete(item.id) } } label: {
                Label("حذف", systemImage: "trash")
            }
        }
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundColor(.brand.opacity(0.7))
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - UIKit bridges

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.presentationMode) private var presentationMode

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        p.delegate = context.coordinator
        return p
    }

    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ p: CameraPicker) { parent = p }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { parent.onImage(img) }
            parent.presentationMode.wrappedValue.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}

struct LibraryPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.presentationMode) private var presentationMode

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 5
        let p = PHPickerViewController(configuration: config)
        p.delegate = context.coordinator
        return p
    }

    func updateUIViewController(_ vc: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: LibraryPicker
        init(_ p: LibraryPicker) { parent = p }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            for r in results where r.itemProvider.canLoadObject(ofClass: UIImage.self) {
                r.itemProvider.loadObject(ofClass: UIImage.self) { obj, _ in
                    if let img = obj as? UIImage {
                        DispatchQueue.main.async { self.parent.onImage(img) }
                    }
                }
            }
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}

struct PhotoRef: Identifiable {
    let id: String
}

struct PhotoViewer: View {
    let name: String
    @Environment(\.presentationMode) private var presentationMode
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            if let img = PhotoStore.image(name) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { v in scale = max(1, min(5, lastScale * v)) }
                            .onEnded { _ in lastScale = scale }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation { scale = scale > 1 ? 1 : 2.5; lastScale = scale }
                    }
            }
            Button {
                presentationMode.wrappedValue.dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.white.opacity(0.85))
                    .padding()
            }
        }
    }
}

struct PhotoThumb: View {
    let name: String
    var size: CGFloat = 84

    var body: some View {
        Group {
            if let img = PhotoStore.image(name) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                Color.gray.opacity(0.2).overlay(Image(systemName: "photo").foregroundColor(.secondary))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
