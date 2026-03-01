import Foundation
import SwiftData

@Model
final class CachedSnapshotRecord {
    @Attribute(.unique) var key: String
    var updatedAt: Date
    var payload: Data

    init(key: String = "default", updatedAt: Date, payload: Data) {
        self.key = key
        self.updatedAt = updatedAt
        self.payload = payload
    }
}

@Model
final class CachedSessionFileRecord {
    @Attribute(.unique) var path: String
    var modifiedAt: Date
    var payload: Data

    init(path: String, modifiedAt: Date, payload: Data) {
        self.path = path
        self.modifiedAt = modifiedAt
        self.payload = payload
    }
}
