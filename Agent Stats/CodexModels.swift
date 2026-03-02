import Foundation

nonisolated struct CountStat: Identifiable, Hashable, Codable {
    let key: String
    let count: Int

    var id: String { key }
}

nonisolated struct ThreadSummary: Identifiable, Hashable, Codable {
    let id: String
    let rolloutPath: String?
    let createdAt: Date?
    let updatedAt: Date?
    let source: String
    let modelProvider: String
    let cwd: String
    let title: String
    let sandboxPolicy: String
    let approvalMode: String
    let tokensUsed: Int
    let archived: Bool
    let gitBranch: String
}

nonisolated struct CodexSnapshot: Codable {
    let codexPath: String
    let generatedAt: Date
    let codexSizeBytes: Int64
    let sessionsSizeBytes: Int64
    let archivedSessionsSizeBytes: Int64
    let sessionFileCount: Int
    let archivedSessionFileCount: Int
    let sessionLineCount: Int
    let archivedSessionLineCount: Int

    let totalThreads: Int
    let activeThreads: Int
    let archivedThreads: Int
    let totalTokensFromThreads: Int64
    let totalTokensFromEventFiles: Int64

    let rulesAllowCount: Int
    let installedSkillCount: Int
    let projectTrustCount: Int

    let logErrorCount: Int
    let logWarnCount: Int

    let threads: [ThreadSummary]
    let sessionUsages: [SessionUsage]
    let modelCounts: [CountStat]
    let sourceCounts: [CountStat]
    let eventTypeCounts: [CountStat]
    let toolCounts: [CountStat]
}

nonisolated struct SessionUsage: Identifiable, Hashable, Codable {
    let id: String
    let date: Date
    let model: String
    let provider: String
    let inputTokens: Int64
    let cachedInputTokens: Int64
    let cacheWriteTokens: Int64
    let cacheWrite5mTokens: Int64
    let cacheWrite1hTokens: Int64
    let outputTokens: Int64
    let reasoningOutputTokens: Int64
    let totalTokens: Int64
    let archived: Bool

    nonisolated init(
        id: String,
        date: Date,
        model: String,
        provider: String,
        inputTokens: Int64,
        cachedInputTokens: Int64,
        cacheWriteTokens: Int64 = 0,
        cacheWrite5mTokens: Int64 = 0,
        cacheWrite1hTokens: Int64 = 0,
        outputTokens: Int64,
        reasoningOutputTokens: Int64,
        totalTokens: Int64,
        archived: Bool
    ) {
        self.id = id
        self.date = date
        self.model = model
        self.provider = provider
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.cacheWriteTokens = cacheWriteTokens
        self.cacheWrite5mTokens = cacheWrite5mTokens
        self.cacheWrite1hTokens = cacheWrite1hTokens
        self.outputTokens = outputTokens
        self.reasoningOutputTokens = reasoningOutputTokens
        self.totalTokens = totalTokens
        self.archived = archived
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case date
        case model
        case provider
        case inputTokens
        case cachedInputTokens
        case cacheWriteTokens
        case cacheWrite5mTokens
        case cacheWrite1hTokens
        case outputTokens
        case reasoningOutputTokens
        case totalTokens
        case archived
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        date = try container.decode(Date.self, forKey: .date)
        model = try container.decode(String.self, forKey: .model)
        provider = try container.decodeIfPresent(String.self, forKey: .provider)
            ?? (model.lowercased().hasPrefix("claude-") ? "Claude" : "Codex")
        inputTokens = try container.decodeIfPresent(Int64.self, forKey: .inputTokens) ?? 0
        cachedInputTokens = try container.decodeIfPresent(Int64.self, forKey: .cachedInputTokens) ?? 0
        cacheWriteTokens = try container.decodeIfPresent(Int64.self, forKey: .cacheWriteTokens) ?? 0
        cacheWrite5mTokens = try container.decodeIfPresent(Int64.self, forKey: .cacheWrite5mTokens) ?? 0
        cacheWrite1hTokens = try container.decodeIfPresent(Int64.self, forKey: .cacheWrite1hTokens) ?? 0
        outputTokens = try container.decodeIfPresent(Int64.self, forKey: .outputTokens) ?? 0
        reasoningOutputTokens = try container.decodeIfPresent(Int64.self, forKey: .reasoningOutputTokens) ?? 0
        totalTokens = try container.decodeIfPresent(Int64.self, forKey: .totalTokens) ?? 0
        archived = try container.decodeIfPresent(Bool.self, forKey: .archived) ?? false
    }
}

nonisolated struct ModelPricing: Codable, Hashable, Identifiable {
    let model: String
    let provider: String?
    let inputPerM: Double
    let cachedInputPerM: Double?
    let cacheWritePerM: Double?
    let cacheWrite1hPerM: Double?
    let outputPerM: Double?

    var id: String { model }

    private enum CodingKeys: String, CodingKey {
        case model
        case provider
        case inputPerM
        case cachedInputPerM
        case cacheWritePerM
        case cacheWrite1hPerM
        case outputPerM
    }

    init(
        model: String,
        provider: String?,
        inputPerM: Double,
        cachedInputPerM: Double?,
        cacheWritePerM: Double?,
        cacheWrite1hPerM: Double?,
        outputPerM: Double?
    ) {
        self.model = model
        self.provider = provider
        self.inputPerM = inputPerM
        self.cachedInputPerM = cachedInputPerM
        self.cacheWritePerM = cacheWritePerM
        self.cacheWrite1hPerM = cacheWrite1hPerM
        self.outputPerM = outputPerM
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        model = try container.decode(String.self, forKey: .model)
        provider = try container.decodeIfPresent(String.self, forKey: .provider)
        inputPerM = try container.decode(Double.self, forKey: .inputPerM)
        cachedInputPerM = try container.decodeIfPresent(Double.self, forKey: .cachedInputPerM)
        cacheWritePerM = try container.decodeIfPresent(Double.self, forKey: .cacheWritePerM)
        cacheWrite1hPerM = try container.decodeIfPresent(Double.self, forKey: .cacheWrite1hPerM)
        outputPerM = try container.decodeIfPresent(Double.self, forKey: .outputPerM)
    }
}

nonisolated struct PricingSnapshot: Codable, Hashable {
    let source: String
    let capturedAt: String
    let type: String
    let models: [ModelPricing]
}

nonisolated struct SessionFileSummary: Codable, Hashable {
    let path: String
    let archived: Bool
    let modifiedAt: Date
    let fileSizeBytes: Int64
    let lineCount: Int
    let tokenTotal: Int64
    let modelCounts: [String: Int]
    let sourceCounts: [String: Int]
    let eventTypeCounts: [String: Int]
    let toolCounts: [String: Int]
    let sessionThreadID: String?
    let parentThreadID: String?
    let usage: SessionUsage?

    init(
        path: String,
        archived: Bool,
        modifiedAt: Date,
        fileSizeBytes: Int64,
        lineCount: Int,
        tokenTotal: Int64,
        modelCounts: [String: Int],
        sourceCounts: [String: Int],
        eventTypeCounts: [String: Int],
        toolCounts: [String: Int],
        sessionThreadID: String? = nil,
        parentThreadID: String? = nil,
        usage: SessionUsage?
    ) {
        self.path = path
        self.archived = archived
        self.modifiedAt = modifiedAt
        self.fileSizeBytes = fileSizeBytes
        self.lineCount = lineCount
        self.tokenTotal = tokenTotal
        self.modelCounts = modelCounts
        self.sourceCounts = sourceCounts
        self.eventTypeCounts = eventTypeCounts
        self.toolCounts = toolCounts
        self.sessionThreadID = sessionThreadID
        self.parentThreadID = parentThreadID
        self.usage = usage
    }
}

nonisolated struct CodexAnalysisResult {
    let snapshot: CodexSnapshot
    let fileSummaries: [SessionFileSummary]
}

nonisolated struct CostPoint: Identifiable, Hashable {
    let date: Date
    let cost: Double

    var id: Date { date }
}

nonisolated struct ModelCostRow: Identifiable, Hashable {
    let model: String
    let cost: Double
    let sessions: Int

    var id: String { model }
}

nonisolated struct LiveSessionRow: Identifiable, Hashable {
    let id: String
    let provider: String
    let source: String
    let model: String
    let lastUpdated: Date
    let totalTokens: Int64
    let rawTotalTokens: Int64
    let estimatedCost: Double
    let archived: Bool

    var isActiveNow: Bool {
        guard !archived else { return false }
        return Date().timeIntervalSince(lastUpdated) <= 15 * 60
    }
}

nonisolated struct ProviderLimitStatus: Identifiable, Hashable {
    let provider: String
    let plan: String
    let renewalDate: Date?
    let usageSummary: String
    let source: String
    let lastCheckedAt: Date
    let errorText: String?

    var id: String { provider }
}

nonisolated struct CostSummary {
    let today: Double
    let thisWeek: Double
    let thisMonth: Double
    let allTime: Double
    let modelRows: [ModelCostRow]
    let daily: [CostPoint]
    let unmatchedModels: [String]
}

extension Int64 {
    var byteString: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}

extension Date {
    var friendly: String {
        DateFormatters.friendly.string(from: self)
    }
}

extension Double {
    var currency: String {
        NumberFormatters.currency.string(from: NSNumber(value: self)) ?? "$0.00"
    }
}

extension String {
    var modelDisplayName: String {
        let raw = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return raw }

        let lowered = raw.lowercased()
        if lowered == "multiple" {
            return "Multiple"
        }

        if let claude = formattedClaudeModelName(from: lowered) {
            return claude
        }
        if let codex = formattedCodexModelName(from: lowered) {
            return codex
        }

        return fallbackModelDisplayName(from: lowered)
    }

    private func formattedClaudeModelName(from lowered: String) -> String? {
        guard lowered.hasPrefix("claude-") else { return nil }

        var parts = lowered.split(separator: "-").map(String.init)
        guard parts.count >= 2 else { return "Claude" }

        if let last = parts.last, last.count == 8, Int(last) != nil {
            parts.removeLast()
        }

        guard parts.count >= 2 else { return "Claude" }
        let family = parts[1].capitalized

        var version: String?
        if parts.count >= 4, Int(parts[2]) != nil, Int(parts[3]) != nil {
            version = "\(parts[2]).\(parts[3])"
        } else if parts.count >= 3 {
            version = parts[2]
        }

        if let version, !version.isEmpty {
            return "\(family) \(version)"
        }
        return family
    }

    private func formattedCodexModelName(from lowered: String) -> String? {
        guard lowered.hasPrefix("gpt-"), lowered.contains("-codex") else { return nil }

        var sparkSuffix = ""
        if lowered.hasSuffix("-spark") {
            sparkSuffix = " Spark"
        }

        guard let codexRange = lowered.range(of: "-codex") else {
            return "Codex"
        }
        let versionSlice = lowered[lowered.index(lowered.startIndex, offsetBy: 4) ..< codexRange.lowerBound]
        let versionToken = String(versionSlice)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            .replacingOccurrences(of: "-", with: ".")

        if versionToken.isEmpty {
            return "Codex\(sparkSuffix)"
        }
        return "Codex \(versionToken)\(sparkSuffix)"
    }

    private func fallbackModelDisplayName(from lowered: String) -> String {
        let parts = lowered.split(separator: "-").map(String.init)
        guard !parts.isEmpty else { return self }

        if parts.count > 1, let last = parts.last, last.count == 8, Int(last) != nil {
            return parts.dropLast().map { prettifyToken($0) }.joined(separator: " ")
        }
        return parts.map { prettifyToken($0) }.joined(separator: " ")
    }

    private func prettifyToken(_ token: String) -> String {
        switch token {
        case "gpt":
            return "GPT"
        case "codex":
            return "Codex"
        case "claude":
            return "Claude"
        case "sonnet":
            return "Sonnet"
        case "haiku":
            return "Haiku"
        case "opus":
            return "Opus"
        case "spark":
            return "Spark"
        case "openai":
            return "OpenAI"
        default:
            return token.capitalized
        }
    }
}

private enum DateFormatters {
    static let friendly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

private enum NumberFormatters {
    static let currency: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 2
        return formatter
    }()
}
