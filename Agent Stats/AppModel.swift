import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class AppModel {
    var snapshot: CodexSnapshot?
    var costSummary: CostSummary?
    var isLoading = false
    var statusText = "Ready"
    var errorText: String?
    var codexURL: URL?
    var pricingSnapshot: PricingSnapshot?

    @ObservationIgnored private let analyzer = CodexAnalyzer()
    @ObservationIgnored private let modelContext: ModelContext
    @ObservationIgnored private let jsonDecoder = JSONDecoder()
    @ObservationIgnored private let jsonEncoder = JSONEncoder()

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        pricingSnapshot = loadPricingSnapshot()
        loadPersistedSnapshotIfAvailable()

        codexURL = defaultCodexURLIfPresent()
        if codexURL != nil {
            refresh()
        }
    }

    var codexPathLabel: String {
        guard let codexURL else {
            return "~/.codex (not found)"
        }
        return abbreviateHome(codexURL.path)
    }

    var pricingStatusLabel: String {
        guard let pricingSnapshot else {
            return "Pricing unavailable"
        }
        return "Pricing (\(pricingSnapshot.type)) from \(pricingSnapshot.capturedAt)"
    }

    func refresh() {
        guard !isLoading else { return }

        let defaultURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
        guard FileManager.default.fileExists(atPath: defaultURL.path) else {
            errorText = "No readable ~/.codex folder found."
            return
        }

        let cachedSummaries = loadCachedSessionFileSummaries()

        let targetURL = defaultURL
        codexURL = targetURL
        errorText = nil
        statusText = cachedSummaries.isEmpty
            ? "Analyzing .codex data..."
            : "Refreshing changed .codex files..."
        isLoading = true

        Task {
            do {
                let result = try await analyzer.analyze(
                    codexURL: targetURL,
                    cachedFileSummaries: cachedSummaries
                )

                snapshot = result.snapshot
                recalculateCosts()
                persist(snapshot: result.snapshot, fileSummaries: result.fileSummaries)
                statusText = "Last refresh: \(result.snapshot.generatedAt.friendly)"
                errorText = nil
            } catch {
                statusText = "Failed"
                errorText = "Unable to read \(abbreviateHome(targetURL.path)). \(error.localizedDescription)"
            }

            isLoading = false
        }
    }

    private func defaultCodexURLIfPresent() -> URL? {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return url
    }

    private func abbreviateHome(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    private func loadPersistedSnapshotIfAvailable() {
        let descriptor = FetchDescriptor<CachedSnapshotRecord>(
            predicate: #Predicate { $0.key == "default" }
        )

        guard let record = try? modelContext.fetch(descriptor).first,
              let persisted = try? jsonDecoder.decode(CodexSnapshot.self, from: record.payload) else {
            return
        }

        snapshot = persisted
        recalculateCosts()
        statusText = "Loaded cached data from \(record.updatedAt.friendly)"
    }

    private func loadCachedSessionFileSummaries() -> [String: SessionFileSummary] {
        let descriptor = FetchDescriptor<CachedSessionFileRecord>()
        guard let records = try? modelContext.fetch(descriptor) else {
            return [:]
        }

        var summaries: [String: SessionFileSummary] = [:]
        summaries.reserveCapacity(records.count)

        for record in records {
            if let decoded = try? jsonDecoder.decode(SessionFileSummary.self, from: record.payload) {
                // Force one-time reparse for older cache entries before source-name normalization.
                if decoded.sourceCounts.keys.contains("vscode") {
                    continue
                }
                summaries[decoded.path] = decoded
            }
        }

        return summaries
    }

    private func persist(snapshot: CodexSnapshot, fileSummaries: [SessionFileSummary]) {
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

    private func recalculateCosts() {
        guard let snapshot, let pricingSnapshot else {
            costSummary = nil
            return
        }

        let pricingByModel = Dictionary(
            uniqueKeysWithValues: pricingSnapshot.models.map { ($0.model.lowercased(), $0) }
        )

        let calendar = Calendar.current
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        let weekInterval = calendar.dateInterval(of: .weekOfYear, for: now)
        let monthInterval = calendar.dateInterval(of: .month, for: now)

        var today = 0.0
        var thisWeek = 0.0
        var thisMonth = 0.0
        var allTime = 0.0

        var dailyCosts: [Date: Double] = [:]
        var byModel: [String: (cost: Double, sessions: Int)] = [:]
        var unmatched = Set<String>()

        for usage in snapshot.sessionUsages {
            let modelKey = canonicalModelName(usage.model, availableModels: pricingByModel)
            guard let pricing = pricingByModel[modelKey] else {
                unmatched.insert(usage.model)
                continue
            }

            let usageCost = sessionCost(usage, pricing: pricing)
            let day = calendar.startOfDay(for: usage.date)

            allTime += usageCost
            dailyCosts[day, default: 0] += usageCost

            if day == todayStart {
                today += usageCost
            }
            if let weekInterval, usage.date >= weekInterval.start, usage.date < weekInterval.end {
                thisWeek += usageCost
            }
            if let monthInterval, usage.date >= monthInterval.start, usage.date < monthInterval.end {
                thisMonth += usageCost
            }

            let modelLabel = pricing.model
            var row = byModel[modelLabel, default: (0, 0)]
            row.cost += usageCost
            row.sessions += 1
            byModel[modelLabel] = row
        }

        let modelRows = byModel
            .map { ModelCostRow(model: $0.key, cost: $0.value.cost, sessions: $0.value.sessions) }
            .sorted { lhs, rhs in
                if lhs.cost == rhs.cost { return lhs.model < rhs.model }
                return lhs.cost > rhs.cost
            }

        let daily = dailyCosts
            .map { CostPoint(date: $0.key, cost: $0.value) }
            .sorted { $0.date < $1.date }

        costSummary = CostSummary(
            today: today,
            thisWeek: thisWeek,
            thisMonth: thisMonth,
            allTime: allTime,
            modelRows: modelRows,
            daily: daily,
            unmatchedModels: Array(unmatched).sorted()
        )
    }

    private func canonicalModelName(
        _ model: String,
        availableModels: [String: ModelPricing]
    ) -> String {
        let lowered = model.lowercased()
        if availableModels[lowered] != nil {
            return lowered
        }

        if lowered.hasSuffix("-spark") {
            let base = String(lowered.dropLast("-spark".count))
            if availableModels[base] != nil {
                return base
            }
        }

        return lowered
    }

    private func sessionCost(_ usage: SessionUsage, pricing: ModelPricing) -> Double {
        let inputCost = Double(usage.inputTokens) / 1_000_000.0 * pricing.inputPerM
        let cachedInputCost = Double(usage.cachedInputTokens) / 1_000_000.0 * (pricing.cachedInputPerM ?? 0)
        let outputCost = Double(usage.outputTokens) / 1_000_000.0 * (pricing.outputPerM ?? 0)
        return inputCost + cachedInputCost + outputCost
    }

    private func loadPricingSnapshot() -> PricingSnapshot? {
        guard let url = Bundle.main.url(forResource: "openai_pricing", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }

        return try? JSONDecoder().decode(PricingSnapshot.self, from: data)
    }
}
