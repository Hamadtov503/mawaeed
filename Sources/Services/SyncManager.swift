import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The file both phones read and write in the shared iCloud Drive folder.
struct SyncFile: Codable {
    var version = 3
    var updatedAt = Date()
    var device = UIDevice.current.name
    var deviceID: String? = SyncManager.deviceID
    var items: [Appointment]
    var tasks: [TaskItem]? = nil
    var deleted: [String: Date]? = nil
}

/// Two-way sync through a folder in iCloud Drive that the user picks once on each phone.
/// It needs no CloudKit, so it also works for side-loaded builds: iCloud Drive carries the file
/// between phones (same Apple ID, or a shared folder for different ones).
final class SyncManager: ObservableObject {
    static let shared = SyncManager()
    static let fileName = "مواعيدي.json"

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
            lastError = L("ما قدرت أحفظ المجلد: \(error.localizedDescription)", "Couldn't save the folder: \(error.localizedDescription)")
        }
    }

    func turnOff() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        folderName = nil
        lastError = nil
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

    /// Pull every 30 seconds while the app is open, so the other phone's changes show up quickly.
    func startAutoSync() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.sync() }
        sync()
    }

    func stopAutoSync() {
        timer?.invalidate()
        timer = nil
    }

    /// Read the shared file, merge it with this phone's appointments, and write the result back.
    func sync() {
        guard let folder = resolveFolder() else { return }
        if isSyncing { pending = true; return }
        isSyncing = true

        queue.async {
            let ok = folder.startAccessingSecurityScopedResource()
            let file = folder.appendingPathComponent(Self.fileName)
            let placeholder = folder.appendingPathComponent(".\(Self.fileName).icloud")
            var remote: SyncFile?
            var readError: Error?
            let fm = FileManager.default

            if fm.fileExists(atPath: file.path) || fm.fileExists(atPath: placeholder.path) {
                try? fm.startDownloadingUbiquitousItem(at: file)
                var coordError: NSError?
                NSFileCoordinator().coordinate(readingItemAt: file, options: [], error: &coordError) { u in
                    do { remote = try Store.decoder.decode(SyncFile.self, from: Data(contentsOf: u)) } catch { readError = error }
                }
                if let e = coordError { readError = e }
            }

            DispatchQueue.main.async {
                // A file that exists but can't be read yet (still downloading) must not be overwritten.
                if remote == nil, readError != nil {
                    if ok { folder.stopAccessingSecurityScopedResource() }
                    self.finish(nil, error: L("الملف لسا ينزل من iCloud — بحاول مرة ثانية.", "The file is still downloading from iCloud — will retry."))
                    return
                }
                let merged = Store.shared.merge(remote: remote?.items ?? [], remoteTasks: remote?.tasks ?? [],
                                                remoteDeleted: remote?.deleted ?? [:])
                let needsWrite: Bool = {
                    guard let r = remote else { return true }
                    let remoteItems = r.items.filter { $0.isAppointment && $0.legacyCategory == nil }
                    if (r.deleted ?? [:]) != merged.deleted || remoteItems.count != merged.items.count || r.items.count != remoteItems.count { return true }
                    let remoteTasks = r.tasks ?? []
                    if remoteTasks.count != merged.tasks.count { return true }
                    let tasksByID = Dictionary(remoteTasks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                    if merged.tasks.contains(where: { m in tasksByID[m.id].map { !$0.sameContent(as: m) } ?? true }) { return true }
                    let byID = Dictionary(remoteItems.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                    return merged.items.contains { m in byID[m.id].map { !$0.sameContent(as: m) } ?? true }
                }()
                let snapshot = SyncFile(items: merged.items.map { var a = $0; a.calendarEventID = nil; return a },
                                        tasks: merged.tasks, deleted: merged.deleted)
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
                    if ok { folder.stopAccessingSecurityScopedResource() }
                    DispatchQueue.main.async {
                        self.finish(writeError == nil ? Date() : nil,
                                    error: writeError.map { L("فشلت المزامنة: \($0.localizedDescription)", "Sync failed: \($0.localizedDescription)") })
                    }
                }
            }
        }
    }

    private func finish(_ syncedAt: Date?, error: String?) {
        isSyncing = false
        if let t = syncedAt {
            lastSync = t
            lastError = nil
            UserDefaults.standard.set(t, forKey: lastKey)
        } else if let e = error {
            lastError = e
        }
        if pending {
            pending = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.sync() }
        }
    }

    /// Reads a backup file (or the sync file, or an older items.json).
    func readBackup(at url: URL) throws -> (items: [Appointment], tasks: [TaskItem]) {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        var data = Data()
        var readError: Error?
        var coordError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordError) { u in
            do { data = try Data(contentsOf: u) } catch { readError = error }
        }
        if let e = coordError ?? readError { throw e }
        if let f = try? Store.decoder.decode(SyncFile.self, from: data) { return (f.items, f.tasks ?? []) }
        return (try Store.decoder.decode([Appointment].self, from: data), [])
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
