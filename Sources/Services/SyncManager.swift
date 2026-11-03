import Foundation
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct Backup: Codable {
    var version = 1
    var exportedAt = Date()
    var items: [Item]
    var photos: [String: Data]
    var assets: AssetState? = nil

    static func make(items: [Item]) -> Backup {
        var photos: [String: Data] = [:]
        for name in Set(items.flatMap { $0.photos }) {
            if let d = PhotoStore.data(name) { photos[name] = d }
        }
        return Backup(items: items, photos: photos, assets: AssetStore.shared.state)
    }

    func encoded() throws -> Data { try Store.encoder.encode(self) }

    static func decode(_ data: Data) throws -> Backup {
        if let b = try? Store.decoder.decode(Backup.self, from: data) { return b }
        if let f = try? Store.decoder.decode(SyncFile.self, from: data) { return Backup(items: f.items, photos: [:], assets: f.assets) }
        // Also accept a bare items.json.
        return Backup(items: try Store.decoder.decode([Item].self, from: data), photos: [:])
    }
}

/// The file both phones read and write in the shared iCloud Drive folder.
struct SyncFile: Codable {
    var version = 2
    var updatedAt = Date()
    var device = UIDevice.current.name
    var deviceID: String? = SyncManager.deviceID
    var items: [Item]
    var deleted: [String: Date]
    var assets: AssetState? = nil
}

/// Two-way sync through a folder in iCloud Drive that the user picks once on each phone.
/// Works without CloudKit, so it also works for side-loaded builds: iCloud Drive itself
/// carries the file between devices (same Apple ID, or a shared folder for different ones).
final class SyncManager: ObservableObject {
    static let shared = SyncManager()
    static let fileName = "مواعيدي.json"
    static let photosFolder = "صور مواعيدي"
    /// Stable per-install id (device names are generic on recent iOS).
    static let deviceID: String = {
        if let id = UserDefaults.standard.string(forKey: "syncDeviceID") { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: "syncDeviceID")
        return id
    }()

    @Published private(set) var folderName: String?
    @Published private(set) var lastSync: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var isSyncing = false
    @Published private(set) var otherDevice: String?

    private let bookmarkKey = "backupFolderBookmark"
    private let lastKey = "lastSyncDate"
    private let queue = DispatchQueue(label: "sync", qos: .utility)
    private var pending = false
    private var timer: Timer?

    private init() {
        lastSync = UserDefaults.standard.object(forKey: lastKey) as? Date
        folderName = resolveFolder()?.lastPathComponent
    }

    var isOn: Bool { folderName != nil }

    func setFolder(_ url: URL) {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(data, forKey: bookmarkKey)
            folderName = url.lastPathComponent
            lastError = nil
            sync()
        } catch {
            lastError = "ما قدرت أحفظ المجلد: \(error.localizedDescription)"
        }
    }

    func turnOff() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        folderName = nil
        otherDevice = nil
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

    /// Pull while the app is open, so changes from the other phone show up quickly.
    func startAutoSync() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.sync() }
        sync()
    }

    func stopAutoSync() {
        timer?.invalidate()
        timer = nil
    }

    /// Read the shared file, merge it with this phone's data, then write the result back.
    func sync(done: ((Bool) -> Void)? = nil) {
        guard let folder = resolveFolder() else { done?(false); return }
        if isSyncing { pending = true; done?(false); return }
        isSyncing = true

        queue.async {
            let ok = folder.startAccessingSecurityScopedResource()
            let file = folder.appendingPathComponent(Self.fileName)
            var remote: SyncFile?
            var readError: Error?
            let fm = FileManager.default

            if fm.fileExists(atPath: file.path) || self.isPlaceholder(for: file) {
                try? fm.startDownloadingUbiquitousItem(at: file)
                var coordError: NSError?
                NSFileCoordinator().coordinate(readingItemAt: file, options: [], error: &coordError) { u in
                    do {
                        let data = try Data(contentsOf: u)
                        remote = try Store.decoder.decode(SyncFile.self, from: data)
                    } catch { readError = error }
                }
                if let e = coordError { readError = e }
            }

            DispatchQueue.main.async {
                // A file that exists but can't be read yet (still downloading) must not be overwritten.
                if remote == nil, readError != nil {
                    if ok { folder.stopAccessingSecurityScopedResource() }
                    self.finish(success: false, error: "الملف ما انقرأ (يمكن لسا ينزل من iCloud) — بحاول مرة ثانية.", done: done)
                    return
                }
                let store = Store.shared
                let assets = AssetStore.shared
                if let incoming = remote?.assets, !assets.merge(incoming) {
                    if ok { folder.stopAccessingSecurityScopedResource() }
                    self.finish(success: false, error: "تعذّر حفظ الممتلكات؛ لم تتم كتابة ملف المزامنة.", done: done)
                    return
                }
                let merged = store.merge(remoteItems: remote?.items ?? [], remoteDeleted: remote?.deleted ?? [:])
                if let r = remote, let rid = r.deviceID, rid != Self.deviceID { self.otherDevice = "\(r.device) ثاني" }
                let needsWrite: Bool = {
                    guard let r = remote else { return true }
                    if r.assets != assets.state { return true }
                    if r.deleted != merged.deleted || r.items.count != merged.items.count { return true }
                    let remoteByID = Dictionary(r.items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                    return merged.items.contains { m in
                        guard let x = remoteByID[m.id] else { return true }
                        return !x.sameContent(as: m)
                    }
                }()
                let photoNames = Set(merged.items.flatMap { $0.photos })
                let snapshot = SyncFile(items: merged.items, deleted: merged.deleted, assets: assets.state)

                self.queue.async {
                    var writeError: Error?
                    if needsWrite {
                        do {
                            let data = try Store.encoder.encode(snapshot)
                            var coordError: NSError?
                            NSFileCoordinator().coordinate(writingItemAt: file, options: .forReplacing, error: &coordError) { u in
                                do { try data.write(to: u, options: .atomic) } catch { writeError = error }
                            }
                            if let e = coordError { writeError = e }
                        } catch { writeError = error }
                    }
                    self.syncPhotos(names: photoNames, folder: folder)
                    if ok { folder.stopAccessingSecurityScopedResource() }
                    DispatchQueue.main.async {
                        self.finish(success: writeError == nil,
                                    error: writeError.map { "فشلت المزامنة: \($0.localizedDescription)" }, done: done)
                    }
                }
            }
        }
    }

    private func isPlaceholder(for file: URL) -> Bool {
        let placeholder = file.deletingLastPathComponent().appendingPathComponent(".\(file.lastPathComponent).icloud")
        return FileManager.default.fileExists(atPath: placeholder.path)
    }

    /// Photos live as separate files next to the sync file, so the JSON stays small.
    private func syncPhotos(names: Set<String>, folder: URL) {
        let fm = FileManager.default
        let dir = folder.appendingPathComponent(Self.photosFolder)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        for name in names {
            let remote = dir.appendingPathComponent(name)
            let local = PhotoStore.url(name)
            let haveLocal = fm.fileExists(atPath: local.path)
            let haveRemote = fm.fileExists(atPath: remote.path)
            if haveLocal && !haveRemote && !isPlaceholder(for: remote) {
                NSFileCoordinator().coordinate(writingItemAt: remote, options: .forReplacing, error: nil) { u in
                    try? fm.copyItem(at: local, to: u)
                }
            } else if !haveLocal && (haveRemote || isPlaceholder(for: remote)) {
                try? fm.startDownloadingUbiquitousItem(at: remote)
                NSFileCoordinator().coordinate(readingItemAt: remote, options: [], error: nil) { u in
                    if let d = try? Data(contentsOf: u) { PhotoStore.write(d, name: name) }
                }
            }
        }
    }

    private func finish(success: Bool, error: String?, done: ((Bool) -> Void)?) {
        isSyncing = false
        if success {
            let now = Date()
            lastSync = now
            lastError = nil
            UserDefaults.standard.set(now, forKey: lastKey)
            Store.shared.objectWillChange.send()
        } else if let e = error {
            lastError = e
        }
        done?(success)
        if pending {
            pending = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.sync() }
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


