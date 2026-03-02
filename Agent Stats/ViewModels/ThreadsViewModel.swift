import Foundation

struct ThreadsViewModel {
    let displayedThreads: [ThreadSummary]
    let sessionTokenTotal: Int64

    private let normalizedTokensByThread: [String: Int64]
    private let modelByRolloutPathMap: [String: String]

    init(snapshot: CodexSnapshot) {
        normalizedTokensByThread = Self.normalizedTokensByThreadID(snapshot.sessionUsages)
        modelByRolloutPathMap = Self.modelByRolloutPath(snapshot.sessionUsages)
        displayedThreads = Self.filteredThreads(snapshot.threads)
        sessionTokenTotal = snapshot.sessionUsages.reduce(Int64(0)) { $0 + TokenMath.displayTokenCount(for: $1) }
    }

    func resolvedModel(for thread: ThreadSummary) -> String {
        if let rolloutPath = thread.rolloutPath,
           let model = modelByRolloutPathMap[rolloutPath] {
            return model
        }
        return thread.modelProvider.modelDisplayName
    }

    func threadTokens(for thread: ThreadSummary) -> Int64 {
        normalizedTokensByThread[thread.id] ?? Int64(thread.tokensUsed)
    }

    private static func normalizedTokensByThreadID(_ usages: [SessionUsage]) -> [String: Int64] {
        var map: [String: Int64] = [:]
        for usage in usages where usage.provider == "Codex" {
            guard let threadID = codexThreadID(from: usage.id) else { continue }
            map[threadID] = max(map[threadID] ?? 0, TokenMath.displayTokenCount(for: usage))
        }
        return map
    }

    private static func modelByRolloutPath(_ usages: [SessionUsage]) -> [String: String] {
        var map: [String: (updatedAt: Date, model: String)] = [:]
        for usage in usages where usage.provider == "Codex" {
            guard usage.id.hasPrefix("codex:") else { continue }
            let path = String(usage.id.dropFirst("codex:".count))
            if let existing = map[path], existing.updatedAt >= usage.date {
                continue
            }
            map[path] = (usage.date, usage.model.modelDisplayName)
        }
        return map.mapValues(\.model)
    }

    private static func filteredThreads(_ threads: [ThreadSummary]) -> [ThreadSummary] {
        threads.filter { thread in
            thread.updatedAt != nil
                || !thread.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !thread.modelProvider.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || thread.tokensUsed > 0
                || !thread.gitBranch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private static func codexThreadID(from usageID: String) -> String? {
        guard usageID.hasPrefix("codex:") else { return nil }
        let path = String(usageID.dropFirst("codex:".count))
        let basename = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent.lowercased()
        let pattern = #"[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(basename.startIndex..., in: basename)
        guard let match = regex.firstMatch(in: basename, range: range),
              let swiftRange = Range(match.range, in: basename) else {
            return nil
        }
        return String(basename[swiftRange])
    }
}
