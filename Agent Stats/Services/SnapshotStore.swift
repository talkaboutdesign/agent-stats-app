import Foundation
import SwiftData

@MainActor
final class SwiftDataSnapshotStore: SnapshotStoring {
    private let modelContext: ModelContext
    private let jsonDecoder = JSONDecoder()
    private let jsonEncoder = JSONEncoder()

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func loadPersistedSnapshot() -> (snapshot: CodexSnapshot, updatedAt: Date)? {
        let descriptor = FetchDescriptor<CachedSnapshotRecord>(
            predicate: #Predicate { $0.key == "default" }
        )

        guard let record = try? modelContext.fetch(descriptor).first,
              let persisted = try? jsonDecoder.decode(CodexSnapshot.self, from: record.payload) else {
            return nil
        }

        return (snapshot: persisted, updatedAt: record.updatedAt)
    }

    func loadCachedSessionFileSummaries() -> [String: SessionFileSummary] {
        let descriptor = FetchDescriptor<CachedSessionFileRecord>()
        guard let records = try? modelContext.fetch(descriptor) else {
            return [:]
        }

        var summaries: [String: SessionFileSummary] = [:]
        summaries.reserveCapacity(records.count)

        for record in records {
            if let decoded = try? jsonDecoder.decode(SessionFileSummary.self, from: record.payload) {
                // Force one-time reparse for older cache entries before source-name normalization.
                if decoded.sourceCounts.keys.contains("vscode")
                    || decoded.sourceCounts.keys.contains(where: { $0.contains("\"subagent\"") }) {
                    continue
                }
                summaries[decoded.path] = decoded
            }
        }

        return summaries
    }

    func persist(snapshot: CodexSnapshot, fileSummaries: [SessionFileSummary]) {
        do {
            let snapshotPayload = try jsonEncoder.encode(snapshot)
            let snapshotDescriptor = FetchDescriptor<CachedSnapshotRecord>(
                predicate: #Predicate { $0.key == "default" }
            )

            if let existingSnapshot = try modelContext.fetch(snapshotDescriptor).first {
                existingSnapshot.updatedAt = snapshot.generatedAt
                existingSnapshot.payload = snapshotPayload
            } else {
                modelContext.insert(
                    CachedSnapshotRecord(
                        key: "default",
                        updatedAt: snapshot.generatedAt,
                        payload: snapshotPayload
                    )
                )
            }

            let fileDescriptor = FetchDescriptor<CachedSessionFileRecord>()
            let existingFiles = try modelContext.fetch(fileDescriptor)
            var existingByPath = Dictionary(uniqueKeysWithValues: existingFiles.map { ($0.path, $0) })
            let currentPaths = Set(fileSummaries.map(\.path))

            for summary in fileSummaries {
                guard let payload = try? jsonEncoder.encode(summary) else {
                    continue
                }

                if let existing = existingByPath.removeValue(forKey: summary.path) {
                    existing.modifiedAt = summary.modifiedAt
                    existing.payload = payload
                } else {
                    modelContext.insert(
                        CachedSessionFileRecord(
                            path: summary.path,
                            modifiedAt: summary.modifiedAt,
                            payload: payload
                        )
                    )
                }
            }

            for stale in existingByPath.values where !currentPaths.contains(stale.path) {
                modelContext.delete(stale)
            }

            try modelContext.save()
        } catch {
            // Keep UI responsive even if persistence fails.
        }
    }
}
