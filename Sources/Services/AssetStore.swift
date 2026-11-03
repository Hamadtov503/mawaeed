import Foundation
import Combine

final class AssetStore: ObservableObject {
    static let shared = AssetStore()
    @Published private(set) var state = AssetState()
    @Published var errorMessage: String?

    private let file: URL
    private var canWrite = true
    private init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        file = directory.appendingPathComponent("assets.json")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: file.path) {
                state = try Store.decoder.decode(AssetState.self, from: Data(contentsOf: file))
            }
        } catch {
            canWrite = false
            errorMessage = "تعذّر فتح ملفات الممتلكات. احتفظ بنسختك الاحتياطية وحاول مرة أخرى."
        }
    }

    var records: [Asset] { state.records.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
    func asset(_ id: UUID?) -> Asset? { state.records.first { $0.id == id } }

    @discardableResult
    private func persist(_ next: AssetState) -> Bool {
        guard canWrite else {
            errorMessage = "ملف الممتلكات غير قابل للقراءة. لم تتم الكتابة فوقه؛ استرجع نسخة احتياطية سليمة."
            return false
        }
        do {
            try Store.encoder.encode(next).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            state = next
            return true
        } catch {
            errorMessage = "تعذّر حفظ التغيير. تأكد من مساحة الجهاز وحاول مرة أخرى."
            return false
        }
    }

    @discardableResult
    func save(_ asset: Asset) -> Bool {
        var next = state
        var record = asset
        record.updatedAt = Date()
        if let index = next.records.firstIndex(where: { $0.id == asset.id }) { next.records[index] = record }
        else { next.records.append(record) }
        guard persist(next) else { return false }
        SyncManager.shared.sync()
        return true
    }

    @discardableResult
    func delete(_ id: UUID) -> Bool {
        var next = state
        next.records.removeAll { $0.id == id }
        next.deleted[id.uuidString] = Date()
        guard persist(next) else { return false }
        // Keep appointments and their history; only remove their association.
        for item in Store.shared.items where item.assetID == id {
            var copy = item; copy.assetID = nil; Store.shared.upsert(copy)
        }
        SyncManager.shared.sync()
        return true
    }

    @discardableResult
    func merge(_ remote: AssetState) -> Bool {
        let next = state.merging(remote)
        return next == state || persist(next)
    }

    @discardableResult
    func restore(_ incoming: AssetState?, replace: Bool) -> Bool {
        guard let incoming = incoming else { return true } // An older backup has no asset data.
        var next = replace ? AssetState() : state
        let now = Date()
        next.deleted = state.deleted
        if replace {
            for record in state.records where !incoming.records.contains(where: { $0.id == record.id }) {
                next.deleted[record.id.uuidString] = now
            }
        }
        var restored = incoming
        for index in restored.records.indices { restored.records[index].updatedAt = now }
        let wasWritable = canWrite
        if replace { canWrite = true }
        let result = persist(next.merging(restored))
        if !result { canWrite = wasWritable }
        return result
    }
}

