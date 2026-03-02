import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class AppModel {
    var snapshot: CodexSnapshot?
    var costSummary: CostSummary?
    var liveSessions: [LiveSessionRow] = []
    var providerLimits: [ProviderLimitStatus] = []
    var isLoading = false
    var statusText = "Ready"
    var errorText: String?
    var codexURL: URL?
    var pricingSnapshot: PricingSnapshot?
    var pricingSnapshots: [PricingSnapshot] = []

    @ObservationIgnored private let analyzer: SnapshotAnalyzing
    @ObservationIgnored private let snapshotStore: SnapshotStoring
    @ObservationIgnored private let pricingLoader: PricingLoading
    @ObservationIgnored private let providerLimitFetcher: ProviderLimitFetching
    @ObservationIgnored private let costCalculator: CostCalculating
    @ObservationIgnored private let liveSessionBuilder: LiveSessionBuilding
    @ObservationIgnored private let environment: FileSystemEnvironment

    @ObservationIgnored private var sessionFileSummaries: [SessionFileSummary] = []
    @ObservationIgnored private var liveRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var providerLimitTask: Task<Void, Never>?

    init(
        snapshotStore: SnapshotStoring,
        analyzer: SnapshotAnalyzing,
        pricingLoader: PricingLoading,
        providerLimitFetcher: ProviderLimitFetching,
        costCalculator: CostCalculating,
        liveSessionBuilder: LiveSessionBuilding,
        environment: FileSystemEnvironment
    ) {
        self.snapshotStore = snapshotStore
        self.analyzer = analyzer
        self.pricingLoader = pricingLoader
        self.providerLimitFetcher = providerLimitFetcher
        self.costCalculator = costCalculator
        self.liveSessionBuilder = liveSessionBuilder
        self.environment = environment

        pricingSnapshots = pricingLoader.loadPricingSnapshots()
        pricingSnapshot = pricingLoader.mergedPricingSnapshot(pricingSnapshots)

        if let persisted = snapshotStore.loadPersistedSnapshot() {
            snapshot = persisted.snapshot
            statusText = "Loaded cached data from \(persisted.updatedAt.friendly)"
        }

        codexURL = environment.codexExists() ? environment.codexURL : nil
        sessionFileSummaries = Array(snapshotStore.loadCachedSessionFileSummaries().values)
        recalculateDerivedState()
        refreshProviderLimits()
        startLiveRefreshLoop()

        if codexURL != nil || environment.claudeExists() {
            refresh()
        }
    }

    convenience init(snapshotStore: SnapshotStoring) {
        self.init(
            snapshotStore: snapshotStore,
            analyzer: CodexAnalyzer(),
            pricingLoader: BundlePricingLoader(),
            providerLimitFetcher: CLIProviderLimitFetcher(),
            costCalculator: CostService(),
            liveSessionBuilder: LiveSessionService(),
            environment: FileSystemEnvironment()
        )
    }

    convenience init(modelContext: ModelContext) {
        let store = SwiftDataSnapshotStore(modelContext: modelContext)
        self.init(snapshotStore: store)
    }

    deinit {
        liveRefreshTask?.cancel()
        refreshTask?.cancel()
        providerLimitTask?.cancel()
    }

    var codexPathLabel: String {
        guard let codexURL else {
            return "~/.codex (not found)"
        }
        return environment.abbreviateHome(codexURL.path)
    }

    var pricingStatusLabel: String {
        guard !pricingSnapshots.isEmpty else {
            return "Pricing unavailable"
        }
        let parts = pricingSnapshots.map { snapshot in
            let name = snapshot.source.contains("claude") ? "Claude" : "OpenAI"
            return "\(name) \(snapshot.capturedAt)"
        }
        return parts.joined(separator: " • ")
    }

    func refresh() {
        guard !isLoading else { return }

        let defaultURL = environment.codexURL
        let codexExists = environment.codexExists()
        let claudeAvailable = environment.claudeExists()

        guard codexExists || claudeAvailable else {
            errorText = "No readable ~/.codex or ~/.claude folder found."
            return
        }

        let cachedSummaries = snapshotStore.loadCachedSessionFileSummaries()

        codexURL = defaultURL
        errorText = nil
        statusText = cachedSummaries.isEmpty
            ? "Analyzing .codex + .claude data..."
            : "Refreshing changed .codex/.claude files..."
        isLoading = true

        refreshTask?.cancel()
        refreshTask = Task {
            do {
                let result = try await analyzer.analyze(
                    codexURL: defaultURL,
                    cachedFileSummaries: cachedSummaries
                )

                if Task.isCancelled {
                    isLoading = false
                    return
                }

                snapshot = result.snapshot
                sessionFileSummaries = result.fileSummaries
                recalculateDerivedState()
                refreshProviderLimits()
                snapshotStore.persist(snapshot: result.snapshot, fileSummaries: result.fileSummaries)
                statusText = "Last refresh: \(result.snapshot.generatedAt.friendly)"
                errorText = nil
            } catch {
                statusText = "Failed"
                errorText = "Unable to read \(environment.abbreviateHome(defaultURL.path)). \(error.localizedDescription)"
            }

            isLoading = false
        }
    }

    private func recalculateDerivedState() {
        if let snapshot {
            costSummary = costCalculator.calculateCostSummary(
                snapshot: snapshot,
                pricingSnapshot: pricingSnapshot
            )
        } else {
            costSummary = nil
        }

        liveSessions = liveSessionBuilder.buildLiveSessions(
            fileSummaries: sessionFileSummaries,
            pricingSnapshot: pricingSnapshot
        )
    }

    private func startLiveRefreshLoop() {
        liveRefreshTask?.cancel()
        liveRefreshTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                self.maybeAutoRefresh()
            }
        }
    }

    private func maybeAutoRefresh() {
        guard !isLoading else { return }
        refresh()
    }

    private func refreshProviderLimits() {
        providerLimitTask?.cancel()
        providerLimitTask = Task {
            let merged = await providerLimitFetcher.fetchProviderLimits()
            if Task.isCancelled { return }
            self.providerLimits = merged
        }
    }
}
