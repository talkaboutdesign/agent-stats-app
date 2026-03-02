import Foundation

nonisolated struct LiveSessionService: LiveSessionBuilding {
    func buildLiveSessions(
        fileSummaries: [SessionFileSummary],
        pricingSnapshot: PricingSnapshot?
    ) -> [LiveSessionRow] {
        guard !fileSummaries.isEmpty else {
            return []
        }

        let pricingByModel = Dictionary(
            uniqueKeysWithValues: (pricingSnapshot?.models ?? []).map { ($0.model.lowercased(), $0) }
        )

        struct SourceRow {
            var row: LiveSessionRow
            let threadID: String?
            let parentThreadID: String?
        }

        enum RollupTarget: Hashable {
            case root(Int)
            case orphan(String)
        }

        var rows: [SourceRow] = []
        rows.reserveCapacity(fileSummaries.count)

        for summary in fileSummaries {
            guard let usage = summary.usage else { continue }
            let source = dominantSource(from: summary.sourceCounts, provider: usage.provider)
            let canonicalModel = ModelNameNormalizer.canonicalName(usage.model, availableModels: pricingByModel)
            let cost = pricingByModel[canonicalModel].map { TokenMath.sessionCost(usage, pricing: $0) } ?? 0
            let displayTokens = TokenMath.displayTokenCount(for: usage)
            let threadID = resolvedThreadID(for: summary, usage: usage)

            rows.append(
                SourceRow(
                    row: LiveSessionRow(
                        id: usage.id,
                        provider: usage.provider,
                        source: source,
                        model: usage.model,
                        lastUpdated: summary.modifiedAt,
                        totalTokens: displayTokens,
                        rawTotalTokens: usage.totalTokens,
                        estimatedCost: cost,
                        archived: usage.archived
                    ),
                    threadID: threadID,
                    parentThreadID: summary.parentThreadID
                )
            )
        }

        var indexByThreadID: [String: Int] = [:]
        indexByThreadID.reserveCapacity(rows.count)

        for (index, item) in rows.enumerated() {
            guard let threadID = item.threadID else { continue }
            indexByThreadID[threadID] = index
        }

        var hiddenIndexes = Set<Int>()
        var targetCache: [Int: RollupTarget] = [:]
        var orphanGroups: [String: LiveSessionRow] = [:]

        func resolveRollupTarget(_ index: Int, visiting: inout Set<Int>) -> RollupTarget {
            if let cached = targetCache[index] {
                return cached
            }

            guard let parentThreadID = rows[index].parentThreadID, !parentThreadID.isEmpty else {
                let resolved: RollupTarget = .root(index)
                targetCache[index] = resolved
                return resolved
            }

            if visiting.contains(index) {
                let resolved: RollupTarget = .orphan(parentThreadID)
                targetCache[index] = resolved
                return resolved
            }

            visiting.insert(index)
            defer { visiting.remove(index) }

            guard let parentIndex = indexByThreadID[parentThreadID], parentIndex != index else {
                let resolved: RollupTarget = .orphan(parentThreadID)
                targetCache[index] = resolved
                return resolved
            }

            let resolved = resolveRollupTarget(parentIndex, visiting: &visiting)
            targetCache[index] = resolved
            return resolved
        }

        for childIndex in rows.indices {
            guard rows[childIndex].parentThreadID != nil else { continue }

            var visiting = Set<Int>()
            let target = resolveRollupTarget(childIndex, visiting: &visiting)

            switch target {
            case .root(let rootIndex):
                guard rootIndex != childIndex else { continue }
                rows[rootIndex].row = mergedSessionRow(parent: rows[rootIndex].row, child: rows[childIndex].row)
                hiddenIndexes.insert(childIndex)

            case .orphan(let key):
                let groupKey = key.isEmpty ? (rows[childIndex].threadID ?? rows[childIndex].row.id) : key
                let existing = orphanGroups[groupKey] ?? syntheticMainSessionRow(from: rows[childIndex].row, groupKey: groupKey)
                orphanGroups[groupKey] = mergedSessionRow(parent: existing, child: rows[childIndex].row)
                hiddenIndexes.insert(childIndex)
            }
        }

        var mergedRows: [LiveSessionRow] = rows.enumerated().compactMap { index, sourceRow in
            guard !hiddenIndexes.contains(index) else { return nil }
            return sourceRow.row
        }

        mergedRows.append(contentsOf: orphanGroups.values)

        return mergedRows.sorted { lhs, rhs in
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

    private func resolvedThreadID(for summary: SessionFileSummary, usage: SessionUsage) -> String? {
        if let threadID = summary.sessionThreadID, !threadID.isEmpty {
            return threadID.lowercased()
        }
        if let extracted = uuidFromText(summary.path) {
            return extracted
        }
        if let extracted = uuidFromText(usage.id) {
            return extracted
        }
        return nil
    }

    private func uuidFromText(_ text: String) -> String? {
        let lowered = text.lowercased()
        let pattern = #"[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(lowered.startIndex..., in: lowered)
        guard let match = regex.firstMatch(in: lowered, range: range),
              let swiftRange = Range(match.range, in: lowered) else {
            return nil
        }
        return String(lowered[swiftRange])
    }

    private func mergedSessionRow(parent: LiveSessionRow, child: LiveSessionRow) -> LiveSessionRow {
        let mergedProvider = parent.provider == child.provider ? parent.provider : "Mixed"
        let mergedModel = parent.model == child.model ? parent.model : "Multiple"
        let mergedUpdatedAt = max(parent.lastUpdated, child.lastUpdated)
        let mergedArchived = parent.archived && child.archived

        return LiveSessionRow(
            id: parent.id,
            provider: mergedProvider,
            source: parent.source,
            model: mergedModel,
            lastUpdated: mergedUpdatedAt,
            totalTokens: parent.totalTokens + child.totalTokens,
            rawTotalTokens: parent.rawTotalTokens + child.rawTotalTokens,
            estimatedCost: parent.estimatedCost + child.estimatedCost,
            archived: mergedArchived
        )
    }

    private func syntheticMainSessionRow(from row: LiveSessionRow, groupKey: String) -> LiveSessionRow {
        LiveSessionRow(
            id: "main:\(groupKey)",
            provider: row.provider,
            source: "CLI (Main Session)",
            model: row.model,
            lastUpdated: row.lastUpdated,
            totalTokens: 0,
            rawTotalTokens: 0,
            estimatedCost: 0,
            archived: row.archived
        )
    }
}
