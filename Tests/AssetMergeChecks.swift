import Foundation

@main
enum AssetMergeChecks {
    static func main() throws {
        let first = Date(timeIntervalSince1970: 1000)
        let second = Date(timeIntervalSince1970: 2000)
        var car = Asset(); car.name = "الكامري"; car.updatedAt = first
        var edited = car; edited.name = "كامري 2025"; edited.updatedAt = second
        let local = AssetState(records: [car])
        let remote = AssetState(records: [edited])
        precondition(local.merging(remote).records == [edited], "Newest edit must win")
        precondition(local.merging(remote) == remote.merging(local), "Merge must be order independent")
        let deleted = AssetState(deleted: [car.id.uuidString: second])
        precondition(local.merging(deleted).records.isEmpty, "Deletion must beat old edits")
        precondition(remote.merging(deleted).records.isEmpty, "Deletion must win ties")
        var recreated = edited; recreated.updatedAt = second.addingTimeInterval(1)
        precondition(deleted.merging(AssetState(records: [recreated])).records.count == 1, "Explicit restoration beats deletion")
        let combined = local.merging(remote)
        precondition(combined.merging(remote) == combined, "Repeated sync must be idempotent")
        let encoded = try JSONEncoder().encode(combined)
        let decoded = try JSONDecoder().decode(AssetState.self, from: encoded)
        precondition(decoded == combined, "Asset state must round trip")
        print("Asset merge checks passed")
    }
}

