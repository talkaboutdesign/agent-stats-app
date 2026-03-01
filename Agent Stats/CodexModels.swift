import Foundation

struct CountStat: Identifiable, Hashable {
    let key: String
    let count: Int

    var id: String { key }
}

struct ThreadSummary: Identifiable, Hashable {
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

struct CodexSnapshot {
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
    let modelCounts: [CountStat]
    let sourceCounts: [CountStat]
    let eventTypeCounts: [CountStat]
    let toolCounts: [CountStat]
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
