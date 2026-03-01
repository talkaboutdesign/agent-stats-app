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

    @ObservationIgnored private let analyzer = CodexAnalyzer()
    @ObservationIgnored private let modelContext: ModelContext
    @ObservationIgnored private let jsonDecoder = JSONDecoder()
    @ObservationIgnored private let jsonEncoder = JSONEncoder()
    @ObservationIgnored private var sessionFileSummaries: [SessionFileSummary] = []
    @ObservationIgnored private var liveRefreshTask: Task<Void, Never>?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        pricingSnapshots = loadPricingSnapshots()
        pricingSnapshot = mergedPricingSnapshot(pricingSnapshots)
        loadPersistedSnapshotIfAvailable()

        codexURL = defaultCodexURLIfPresent()
        sessionFileSummaries = Array(loadCachedSessionFileSummaries().values)
        recalculateLiveSessions()
        refreshProviderLimits()
        startLiveRefreshLoop()

        if codexURL != nil || claudeExists() {
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

        let defaultURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
        let codexExists = FileManager.default.fileExists(atPath: defaultURL.path)
        let claudeAvailable = claudeExists()

        guard codexExists || claudeAvailable else {
            errorText = "No readable ~/.codex or ~/.claude folder found."
            return
        }

        let cachedSummaries = loadCachedSessionFileSummaries()

        let targetURL = defaultURL
        codexURL = targetURL
        errorText = nil
        statusText = cachedSummaries.isEmpty
            ? "Analyzing .codex + .claude data..."
            : "Refreshing changed .codex/.claude files..."
        isLoading = true

        Task {
            do {
                let result = try await analyzer.analyze(
                    codexURL: targetURL,
                    cachedFileSummaries: cachedSummaries
                )

                snapshot = result.snapshot
                sessionFileSummaries = result.fileSummaries
                recalculateCosts()
                refreshProviderLimits()
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

    private func claudeExists() -> Bool {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude", isDirectory: true)
        return FileManager.default.fileExists(atPath: url.path)
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

        recalculateLiveSessions()
    }

    private func recalculateLiveSessions() {
        guard !sessionFileSummaries.isEmpty else {
            liveSessions = []
            return
        }

        let pricingByModel = Dictionary(
            uniqueKeysWithValues: (pricingSnapshot?.models ?? []).map { ($0.model.lowercased(), $0) }
        )

        var rows: [LiveSessionRow] = []
        rows.reserveCapacity(sessionFileSummaries.count)

        for summary in sessionFileSummaries {
            guard let usage = summary.usage else { continue }
            let source = dominantSource(from: summary.sourceCounts, provider: usage.provider)
            let canonicalModel = canonicalModelName(usage.model, availableModels: pricingByModel)
            let cost = pricingByModel[canonicalModel].map { sessionCost(usage, pricing: $0) } ?? 0
            let displayTokens = displayTokenCount(usage)

            rows.append(
                LiveSessionRow(
                    id: usage.id,
                    provider: usage.provider,
                    source: source,
                    model: usage.model,
                    lastUpdated: summary.modifiedAt,
                    totalTokens: displayTokens,
                    rawTotalTokens: usage.totalTokens,
                    estimatedCost: cost,
                    archived: usage.archived
                )
            )
        }

        liveSessions = rows.sorted { lhs, rhs in
            if lhs.lastUpdated == rhs.lastUpdated {
                return lhs.id > rhs.id
            }
            return lhs.lastUpdated > rhs.lastUpdated
        }
    }

    private func dominantSource(from sourceCounts: [String: Int], provider: String) -> String {
        guard let best = sourceCounts.max(by: { lhs, rhs in
            if lhs.value == rhs.value {
                return lhs.key > rhs.key
            }
            return lhs.value < rhs.value
        })?.key else {
            return provider
        }
        return best
    }

    private func canonicalModelName(
        _ model: String,
        availableModels: [String: ModelPricing]
    ) -> String {
        let lowered = model.lowercased()
        if availableModels[lowered] != nil {
            return lowered
        }

        if let strippedDate = stripClaudeDateSuffix(lowered), availableModels[strippedDate] != nil {
            return strippedDate
        }

        if lowered.hasSuffix("-spark") {
            let base = String(lowered.dropLast("-spark".count))
            if availableModels[base] != nil {
                return base
            }
        }

        return lowered
    }

    private func displayTokenCount(_ usage: SessionUsage) -> Int64 {
        let uncachedInput = usage.provider == "Codex"
            ? max(usage.inputTokens - usage.cachedInputTokens, 0)
            : usage.inputTokens
        return max(uncachedInput + usage.outputTokens, 0)
    }

    private func sessionCost(_ usage: SessionUsage, pricing: ModelPricing) -> Double {
        let includesCachedInInput = usage.provider == "Codex"
        let rawInputTokens = Double(usage.inputTokens)
        let cachedInputTokens = Double(usage.cachedInputTokens)
        let billableInputTokens = includesCachedInInput
            ? max(rawInputTokens - cachedInputTokens, 0)
            : rawInputTokens

        let inputCost = billableInputTokens / 1_000_000.0 * pricing.inputPerM
        let cachedInputCost = cachedInputTokens / 1_000_000.0 * (pricing.cachedInputPerM ?? 0)
        let write5mTokens = usage.cacheWrite5mTokens > 0
            ? usage.cacheWrite5mTokens
            : max(usage.cacheWriteTokens - usage.cacheWrite1hTokens, 0)
        let write1hTokens = usage.cacheWrite1hTokens
        let cacheWrite5mCost = Double(write5mTokens) / 1_000_000.0 * (pricing.cacheWritePerM ?? 0)
        let cacheWrite1hCost = Double(write1hTokens) / 1_000_000.0 * (pricing.cacheWrite1hPerM ?? pricing.cacheWritePerM ?? 0)
        let outputCost = Double(usage.outputTokens) / 1_000_000.0 * (pricing.outputPerM ?? 0)
        return inputCost + cachedInputCost + cacheWrite5mCost + cacheWrite1hCost + outputCost
    }

    private func refreshProviderLimits() {
        Task.detached(priority: .utility) {
            let codex = Self.codexLimitStatusFromCLIAndAuth()
            let claude = Self.claudeLimitStatusFromCLI()
            let merged = [codex, claude].compactMap { $0 }
            await MainActor.run {
                self.providerLimits = merged.sorted { $0.provider < $1.provider }
            }
        }
    }

    nonisolated private static func codexLimitStatusFromCLIAndAuth() -> ProviderLimitStatus? {
        let loginStatus = runCommand("codex", arguments: ["login", "status"], timeout: 4)
        let loginSummary = loginStatus.map { squashWhitespace($0.stdout) } ?? ""

        let home = FileManager.default.homeDirectoryForCurrentUser
        let authURL = home.appendingPathComponent(".codex/auth.json")
        guard let data = try? Data(contentsOf: authURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = object["tokens"] as? [String: Any],
              let idToken = tokens["id_token"] as? String,
              let claims = decodeJWTClaims(idToken),
              let auth = claims["https://api.openai.com/auth"] as? [String: Any] else {
            return ProviderLimitStatus(
                provider: "Codex",
                plan: "Unknown",
                renewalDate: nil,
                usageSummary: loginSummary.isEmpty ? "Usage limits unavailable" : loginSummary,
                source: "codex login status",
                lastCheckedAt: Date(),
                errorText: nil
            )
        }

        let plan = (auth["chatgpt_plan_type"] as? String)?
            .replacingOccurrences(of: "_", with: " ")
            .capitalized ?? "ChatGPT"
        let renewalDate = parseISO8601Date(auth["chatgpt_subscription_active_until"] as? String)
        let lastChecked = parseISO8601Date(auth["chatgpt_subscription_last_checked"] as? String) ?? Date()
        let usageSummary = loginSummary.isEmpty
            ? "Live quota usage is not exposed by non-interactive Codex CLI."
            : loginSummary

        return ProviderLimitStatus(
            provider: "Codex",
            plan: plan,
            renewalDate: renewalDate,
            usageSummary: usageSummary,
            source: loginSummary.isEmpty ? "local auth" : "codex login status + local auth",
            lastCheckedAt: lastChecked,
            errorText: nil
        )
    }

    nonisolated private static func claudeLimitStatusFromCLI() -> ProviderLimitStatus? {
        if let statusOutput = runCommand(
            "claude",
            arguments: ["-p", "/status", "--output-format", "text", "--verbose"],
            timeout: 6
        ), statusOutput.exitCode == 0 {
            let message = squashWhitespace(statusOutput.stdout)
            let lowered = message.lowercased()
            if !message.isEmpty, !lowered.contains("unknown skill: status") {
                return ProviderLimitStatus(
                    provider: "Claude",
                    plan: "Subscription",
                    renewalDate: nil,
                    usageSummary: message,
                    source: "claude /status",
                    lastCheckedAt: Date(),
                    errorText: nil
                )
            }
        }

        if let accountOutput = runCommand(
            "claude",
            arguments: ["-p", "/account", "--output-format", "text", "--verbose"],
            timeout: 6
        ), accountOutput.exitCode == 0 {
            let message = squashWhitespace(accountOutput.stdout)
            let lowered = message.lowercased()

            if !message.isEmpty, !lowered.contains("unknown skill: account") {
                return ProviderLimitStatus(
                    provider: "Claude",
                    plan: "Subscription",
                    renewalDate: nil,
                    usageSummary: message,
                    source: "claude /account",
                    lastCheckedAt: Date(),
                    errorText: nil
                )
            }
        }

        guard let output = runCommand("claude", arguments: ["auth", "status"], timeout: 4),
              output.exitCode == 0 else {
            return ProviderLimitStatus(
                provider: "Claude",
                plan: "Unknown",
                renewalDate: nil,
                usageSummary: "Usage limits unavailable",
                source: "claude auth status",
                lastCheckedAt: Date(),
                errorText: nil
            )
        }

        let outputText = squashWhitespace(output.stdout)
        guard let data = output.stdout.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ProviderLimitStatus(
                provider: "Claude",
                plan: "Unknown",
                renewalDate: nil,
                usageSummary: outputText.isEmpty ? "Usage limits unavailable" : outputText,
                source: "claude auth status",
                lastCheckedAt: Date(),
                errorText: nil
            )
        }

        let subscriptionType = (object["subscriptionType"] as? String)?
            .replacingOccurrences(of: "_", with: " ")
            .capitalized ?? "Unknown"
        let orgName = object["orgName"] as? String
        let authMethod = object["authMethod"] as? String

        var summaryParts: [String] = []
        if let orgName, !orgName.isEmpty {
            summaryParts.append(orgName)
        }
        if let authMethod, !authMethod.isEmpty {
            summaryParts.append(authMethod)
        }
        if summaryParts.isEmpty {
            summaryParts.append("Subscription")
        }

        return ProviderLimitStatus(
            provider: "Claude",
            plan: subscriptionType,
            renewalDate: nil,
            usageSummary: outputText.isEmpty ? "No renewal/remaining quota field from CLI auth status." : outputText,
            source: summaryParts.joined(separator: " • "),
            lastCheckedAt: Date(),
            errorText: nil
        )
    }

    nonisolated private static func runCommand(
        _ executable: String,
        arguments: [String],
        timeout: TimeInterval
    ) -> (stdout: String, stderr: String, exitCode: Int32)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return nil
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        if process.isRunning {
            process.terminate()
            return nil
        }

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""
        return (stdout, stderr, process.terminationStatus)
    }

    nonisolated private static func decodeJWTClaims(_ token: String) -> [String: Any]? {
        let segments = token.split(separator: ".")
        guard segments.count >= 2 else { return nil }

        let payload = String(segments[1])
        let padded = payload + String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let payloadData = Data(base64Encoded: padded.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")),
            let object = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else {
            return nil
        }
        return object
    }

    nonisolated private static func parseISO8601Date(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }
        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        return basic.date(from: value)
    }

    nonisolated private static func squashWhitespace(_ text: String) -> String {
        let parts = text.split(whereSeparator: \.isWhitespace)
        return parts.joined(separator: " ")
    }

    private func loadPricingSnapshots() -> [PricingSnapshot] {
        let names = ["openai_pricing", "claude_pricing"]
        var snapshots: [PricingSnapshot] = []

        for name in names {
            guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let snapshot = try? JSONDecoder().decode(PricingSnapshot.self, from: data) else {
                continue
            }
            snapshots.append(snapshot)
        }

        return snapshots
    }

    private func mergedPricingSnapshot(_ snapshots: [PricingSnapshot]) -> PricingSnapshot? {
        guard !snapshots.isEmpty else { return nil }

        let mergedModels = snapshots.flatMap(\.models)
        let mergedSource = snapshots.map(\.source).joined(separator: " + ")
        let capturedAt = snapshots.map(\.capturedAt).joined(separator: " / ")

        return PricingSnapshot(
            source: mergedSource,
            capturedAt: capturedAt,
            type: "standard",
            models: mergedModels
        )
    }

    private func stripClaudeDateSuffix(_ model: String) -> String? {
        let pattern = #"-\d{8}$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(model.startIndex..., in: model)
        guard let match = regex.firstMatch(in: model, range: range) else {
            return nil
        }
        guard let swiftRange = Range(match.range, in: model) else {
            return nil
        }
        return String(model[..<swiftRange.lowerBound])
    }

}
