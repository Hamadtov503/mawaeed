import Foundation

enum AssetKind: String, Codable, CaseIterable, Identifiable {
    case vehicle, device
    var id: String { rawValue }
    var title: String { self == .vehicle ? "سيارة" : "جهاز" }
    var icon: String { self == .vehicle ? "car.fill" : "desktopcomputer" }
}

struct Asset: Codable, Equatable, Identifiable {
    var id = UUID()
    var name = ""
    var kind: AssetKind = .vehicle
    var model = ""
    var identifier = ""
    var notes = ""
    var updatedAt = Date()
}

/// Optional in old backup/sync envelopes so existing files continue to decode.
struct AssetState: Codable, Equatable {
    var records: [Asset] = []
    var deleted: [String: Date] = [:]

    func merging(_ remote: AssetState) -> AssetState {
        var tombstones = deleted
        for (id, date) in remote.deleted { tombstones[id] = max(date, tombstones[id] ?? .distantPast) }
        var recordsByID: [UUID: Asset] = [:]
        for record in records + remote.records {
            if let current = recordsByID[record.id], current.updatedAt >= record.updatedAt { continue }
            recordsByID[record.id] = record
        }
        for (id, date) in tombstones {
            if let uuid = UUID(uuidString: id), let record = recordsByID[uuid], record.updatedAt <= date {
                recordsByID[uuid] = nil
            }
        }
        return AssetState(records: recordsByID.values.sorted { $0.id.uuidString < $1.id.uuidString }, deleted: tombstones)
    }
}

