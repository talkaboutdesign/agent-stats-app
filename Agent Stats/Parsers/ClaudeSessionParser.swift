import Foundation

nonisolated struct ClaudeSessionParser: SessionSummaryParsing {
    private struct ClaudeUsageAggregate {
        let model: String
        let inputTokens: Int64
        let cacheReadTokens: Int64
        let cacheWriteTokens: Int64
        let cacheWrite5mTokens: Int64
        let cacheWrite1hTokens: Int64
        let outputTokens: Int64
        let totalTokens: Int64
    }

    func parse(
        _ url: URL,
        archived: Bool,
        modifiedAt: Date,
        fileSizeBytes: Int64
    ) -> SessionFileSummary {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return SessionFileSummary(
                path: url.path,
                archived: archived,
                modifiedAt: modifiedAt,
                fileSizeBytes: fileSizeBytes,
                lineCount: 0,
                tokenTotal: 0,
                modelCounts: [:],
                sourceCounts: [:],
                eventTypeCounts: [:],
                toolCounts: [:],
                usage: nil
            )
        }

        var lineCount = 0
        var modelCounts: [String: Int] = [:]
        let sourceCounts: [String: Int] = ["Claude CLI": 1]
        var eventTypeCounts: [String: Int] = [:]
        var toolCounts: [String: Int] = [:]
        var usageByMessageID: [String: ClaudeUsageAggregate] = [:]

        for lineSlice in text.split(separator: "\n", omittingEmptySubsequences: false) {
            lineCount += 1
            let line = String(lineSlice)
            guard let data = line.data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            if let eventType = root["type"] as? String {
                eventTypeCounts[eventType, default: 0] += 1
            }

            if let message = root["message"] as? [String: Any] {
                parseClaudeMessage(
                    message,
                    eventTimestamp: root["timestamp"] as? String,
                    toolCounts: &toolCounts,
                    usageByMessageID: &usageByMessageID
                )
                continue
            }

            guard let dataObject = root["data"] as? [String: Any],
                  let nestedMessageObject = dataObject["message"] as? [String: Any],
                  let nestedMessage = nestedMessageObject["message"] as? [String: Any] else {
                continue
            }

            parseClaudeMessage(
                nestedMessage,
                eventTimestamp: nestedMessageObject["timestamp"] as? String,
                toolCounts: &toolCounts,
                usageByMessageID: &usageByMessageID
            )
        }

        var totalInput: Int64 = 0
        var totalCacheRead: Int64 = 0
        var totalCacheWrite: Int64 = 0
        var totalCacheWrite5m: Int64 = 0
        var totalCacheWrite1h: Int64 = 0
        var totalOutput: Int64 = 0
        var totalTokens: Int64 = 0
        var tokensByModel: [String: Int64] = [:]

        for aggregate in usageByMessageID.values {
            totalInput += aggregate.inputTokens
            totalCacheRead += aggregate.cacheReadTokens
            totalCacheWrite += aggregate.cacheWriteTokens
            totalCacheWrite5m += aggregate.cacheWrite5mTokens
            totalCacheWrite1h += aggregate.cacheWrite1hTokens
            totalOutput += aggregate.outputTokens
            totalTokens += aggregate.totalTokens

            if !aggregate.model.isEmpty {
                modelCounts[aggregate.model, default: 0] += 1
                tokensByModel[aggregate.model, default: 0] += aggregate.totalTokens
            }
        }

        let dominantModel = tokensByModel.max(by: { $0.value < $1.value })?.key ?? "<unknown>"
        let usageDate = modifiedAt
        let usage: SessionUsage? = totalTokens > 0
            ? SessionUsage(
                id: "claude:\(url.path)",
                date: usageDate,
                model: dominantModel,
                provider: "Claude",
                inputTokens: totalInput,
                cachedInputTokens: totalCacheRead,
                cacheWriteTokens: totalCacheWrite,
                cacheWrite5mTokens: totalCacheWrite5m,
                cacheWrite1hTokens: totalCacheWrite1h,
                outputTokens: totalOutput,
                reasoningOutputTokens: 0,
                totalTokens: totalTokens,
                archived: archived
            )
            : nil

        return SessionFileSummary(
            path: url.path,
            archived: archived,
            modifiedAt: modifiedAt,
            fileSizeBytes: fileSizeBytes,
            lineCount: lineCount,
            tokenTotal: totalTokens,
            modelCounts: modelCounts,
            sourceCounts: sourceCounts,
            eventTypeCounts: eventTypeCounts,
            toolCounts: toolCounts,
            usage: usage
        )
    }

    private func parseClaudeMessage(
        _ message: [String: Any],
        eventTimestamp: String?,
        toolCounts: inout [String: Int],
        usageByMessageID: inout [String: ClaudeUsageAggregate]
    ) {
        let model = (message["model"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if let content = message["content"] as? [[String: Any]] {
            for item in content {
                guard let itemType = item["type"] as? String, itemType == "tool_use" else {
                    continue
                }
                if let toolName = item["name"] as? String, !toolName.isEmpty {
                    toolCounts[toolName, default: 0] += 1
                }
            }
        }

        guard let usage = message["usage"] as? [String: Any] else {
            return
        }

        let inputTokens = int64Value(usage["input_tokens"]) ?? 0
        let cacheReadTokens = int64Value(usage["cache_read_input_tokens"]) ?? 0
        let cacheWriteTokens = int64Value(usage["cache_creation_input_tokens"]) ?? 0
        let outputTokens = int64Value(usage["output_tokens"]) ?? 0

        let cacheCreation = usage["cache_creation"] as? [String: Any]
        let cacheWrite5mTokens = int64Value(cacheCreation?["ephemeral_5m_input_tokens"]) ?? 0
        let cacheWrite1hTokens = int64Value(cacheCreation?["ephemeral_1h_input_tokens"]) ?? 0
        let totalTokens = inputTokens + cacheReadTokens + cacheWriteTokens + outputTokens

        guard totalTokens > 0 else {
            return
        }

        let messageID = (message["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackID = "\(eventTimestamp ?? "unknown")|\(model)|\(inputTokens)|\(cacheReadTokens)|\(cacheWriteTokens)|\(outputTokens)"
        let key = (messageID?.isEmpty == false ? messageID! : fallbackID)

        let candidate = ClaudeUsageAggregate(
            model: model.isEmpty ? "<unknown>" : model,
            inputTokens: inputTokens,
            cacheReadTokens: cacheReadTokens,
            cacheWriteTokens: cacheWriteTokens,
            cacheWrite5mTokens: cacheWrite5mTokens,
            cacheWrite1hTokens: cacheWrite1hTokens,
            outputTokens: outputTokens,
            totalTokens: totalTokens
        )

        if let existing = usageByMessageID[key] {
            if existing.totalTokens > candidate.totalTokens {
                return
            }
            if existing.totalTokens == candidate.totalTokens,
               existing.model != "<unknown>",
               candidate.model == "<unknown>" {
                return
            }
        }
        usageByMessageID[key] = candidate
    }

    private func int64Value(_ value: Any?) -> Int64? {
        switch value {
        case let int as Int:
            return Int64(int)
        case let int64 as Int64:
            return int64
        case let number as NSNumber:
            return number.int64Value
        case let string as String:
            return Int64(string)
        default:
            return nil
        }
    }
}
