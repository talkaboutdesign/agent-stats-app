import Foundation

nonisolated protocol SnapshotAnalyzing {
    func analyze(
        codexURL: URL,
        cachedFileSummaries: [String: SessionFileSummary]
    ) async throws -> CodexAnalysisResult
}

nonisolated protocol SnapshotStoring {
    func loadPersistedSnapshot() -> (snapshot: CodexSnapshot, updatedAt: Date)?
    func loadCachedSessionFileSummaries() -> [String: SessionFileSummary]
    func persist(snapshot: CodexSnapshot, fileSummaries: [SessionFileSummary])
}

nonisolated protocol PricingLoading {
    func loadPricingSnapshots() -> [PricingSnapshot]
    func mergedPricingSnapshot(_ snapshots: [PricingSnapshot]) -> PricingSnapshot?
}

nonisolated protocol ProviderLimitFetching {
    func fetchProviderLimits() async -> [ProviderLimitStatus]
}

nonisolated protocol CostCalculating {
    func calculateCostSummary(
        snapshot: CodexSnapshot,
        pricingSnapshot: PricingSnapshot?
    ) -> CostSummary?
}

nonisolated protocol LiveSessionBuilding {
    func buildLiveSessions(
        fileSummaries: [SessionFileSummary],
        pricingSnapshot: PricingSnapshot?
    ) -> [LiveSessionRow]
}
