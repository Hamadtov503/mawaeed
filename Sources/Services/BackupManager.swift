import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct Backup: Codable {
    var version = 1
    var exportedAt = Date()
    var items: [Item]
    var photos: [String: Data]

    static func make(items: [Item]) -> Backup {
        var photos: [String: Data] = [:]
        for name in Set(items.flatMap { $0.photos }) {
            if let d = PhotoStore.data(name) { photos[name] = d }
        }
        return Backup(items: items, photos: photos)
    }

    func encoded() throws -> Data { try Store.encoder.encode(self) }

    static func decode(_ data: Data) throws -> Backup {
        if let b = try? Store.decoder.decode(Backup.self, from: data) { return b }
        // Also accept a bare items.json.
        return Backup(items: try Store.decoder.decode([Item].self, from: data), photos: [:])
    }
}

/// Automatic backup into a folder the user picks once in the Files app (e.g. iCloud Drive).
/// This needs no special iCloud entitlement, so it also works for side-loaded builds.
final class BackupManager: ObservableObject {
    static let shared = BackupManager()
    static let fileName = "مواعيدي - نسخة احتياطية.json"

    @Published private(set) var folderName: String?
    @Published private(set) var lastBackup: Date?
    @Published private(set) var lastError: String?

    private let bookmarkKey = "backupFolderBookmark"
    private let lastKey = "lastBackupDate"
    private let queue = DispatchQueue(label: "backup", qos: .utility)

    private init() {
        lastBackup = UserDefaults.standard.object(forKey: lastKey) as? Date
        folderName = resolveFolder()?.lastPathComponent
    }

    var hasFolder: Bool { folderName != nil }

    func setFolder(_ url: URL) {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(data, forKey: bookmarkKey)
            folderName = url.lastPathComponent
            lastError = nil
            backupNow(items: Store.shared.items)
        } catch {
            lastError = "ما قدرت أحفظ المجلد: \(error.localizedDescription)"
        }
    }

    func clearFolder() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        folderName = nil
    }

    private func resolveFolder() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else {
            return nil
        }
        if stale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(fresh, forKey: bookmarkKey)
        }
        return url
    }

    func autoBackup(items: [Item]) {
        guard hasFolder else { return }
        backupNow(items: items)
    }

    func backupNow(items: [Item], done: ((Bool) -> Void)? = nil) {
        guard let folder = resolveFolder() else { done?(false); return }
        let backup = Backup.make(items: items)
        queue.async {
            var success = false
            var message: String?
            let ok = folder.startAccessingSecurityScopedResource()
            defer { if ok { folder.stopAccessingSecurityScopedResource() } }
            do {
                let data = try backup.encoded()
                let target = folder.appendingPathComponent(Self.fileName)
                var coordError: NSError?
                var writeError: Error?
                NSFileCoordinator().coordinate(writingItemAt: target, options: .forReplacing, error: &coordError) { url in
                    do { try data.write(to: url, options: .atomic) } catch { writeError = error }
                }
                if let e = coordError ?? writeError { throw e }
                success = true
            } catch {
                message = "فشل النسخ الاحتياطي: \(error.localizedDescription)"
            }
            DispatchQueue.main.async {
                if success {
                    let now = Date()
                    self.lastBackup = now
                    self.lastError = nil
                    UserDefaults.standard.set(now, forKey: self.lastKey)
                } else {
                    self.lastError = message ?? "تعذّر الوصول للمجلد، اختره مرة ثانية."
                }
                done?(success)
            }
        }
    }

    func readBackup(at url: URL) throws -> Backup {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        var data: Data?
        var readError: Error?
        var coordError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordError) { u in
            do { data = try Data(contentsOf: u) } catch { readError = error }
        }
        if let e = coordError ?? readError { throw e }
        return try Backup.decode(data ?? Data())
    }
}

/// Lets `.fileExporter` save a backup anywhere in Files.
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
