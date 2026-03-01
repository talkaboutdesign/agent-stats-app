import Foundation

struct CountStat: Identifiable, Hashable, Codable {
    let key: String
    let count: Int

    var id: String { key }
}

struct ThreadSummary: Identifiable, Hashable, Codable {
    let id: String
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

struct CodexSnapshot: Codable {
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

struct SessionUsage: Identifiable, Hashable, Codable {
    let id: String
    let date: Date
    let model: String
    let inputTokens: Int64
    let cachedInputTokens: Int64
    let outputTokens: Int64
    let reasoningOutputTokens: Int64
    let totalTokens: Int64
    let archived: Bool
}

struct ModelPricing: Codable, Hashable, Identifiable {
    let model: String
    let inputPerM: Double
    let cachedInputPerM: Double?
    let outputPerM: Double?

    var id: String { model }
}

struct PricingSnapshot: Codable, Hashable {
    let source: String
    let capturedAt: String
    let type: String
    let models: [ModelPricing]
}

struct SessionFileSummary: Codable, Hashable {
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
    let usage: SessionUsage?
}

struct CodexAnalysisResult {
    let snapshot: CodexSnapshot
    let fileSummaries: [SessionFileSummary]
}

struct CostPoint: Identifiable, Hashable {
    let date: Date
    let cost: Double

    var id: Date { date }
}

struct ModelCostRow: Identifiable, Hashable {
    let model: String
    let cost: Double
    let sessions: Int

    var id: String { model }
}

struct CostSummary {
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
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }
}

extension Double {
    var currency: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: self)) ?? "$0.00"
    }
}
