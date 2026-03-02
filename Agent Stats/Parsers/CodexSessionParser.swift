import Foundation

nonisolated struct CodexSessionParser: SessionSummaryParsing {
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
        var maxTokenTotalForFile: Int64 = 0
        var bestUsageInputTokens: Int64 = 0
        var bestUsageCachedInputTokens: Int64 = 0
        var bestUsageOutputTokens: Int64 = 0
        var bestUsageReasoningOutputTokens: Int64 = 0
        var bestUsageModel = ""
        var lastSeenModel = ""
        var sessionThreadID: String?
        var parentThreadID: String?
        var modelCounts: [String: Int] = [:]
        var sourceCounts: [String: Int] = [:]
        var eventTypeCounts: [String: Int] = [:]
        var toolCounts: [String: Int] = [:]

        for lineSlice in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(lineSlice)
            lineCount += 1

            guard let data = line.data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = root["type"] as? String else {
                continue
            }

            if type == "session_meta", let payload = root["payload"] as? [String: Any] {
                if sessionThreadID == nil, let threadID = payload["id"] as? String {
                    sessionThreadID = threadID.lowercased()
                }

                if let source = payload["source"] {
                    sourceCounts[sourceDisplayName(source), default: 0] += 1
                    if parentThreadID == nil {
                        parentThreadID = subagentParentThreadID(from: source)
                    }
                }
                if let modelProvider = payload["model_provider"] as? String {
                    modelCounts[modelProvider, default: 0] += 1
                }
                continue
            }

            guard let payload = root["payload"] as? [String: Any] else {
                continue
            }

            switch type {
            case "turn_context":
                if let model = payload["model"] as? String {
                    modelCounts[model, default: 0] += 1
                    lastSeenModel = model
                }

            case "event_msg":
                if let eventType = payload["type"] as? String {
                    eventTypeCounts[eventType, default: 0] += 1

                    if eventType == "token_count",
                       let info = payload["info"] as? [String: Any],
                       let totalTokenUsage = info["total_token_usage"] as? [String: Any],
                       let totalTokens = int64Value(totalTokenUsage["total_tokens"]) {
                        if totalTokens > maxTokenTotalForFile {
                            maxTokenTotalForFile = totalTokens
                            bestUsageInputTokens = int64Value(totalTokenUsage["input_tokens"]) ?? 0
                            bestUsageCachedInputTokens = int64Value(totalTokenUsage["cached_input_tokens"]) ?? 0
                            bestUsageOutputTokens = int64Value(totalTokenUsage["output_tokens"]) ?? 0
                            bestUsageReasoningOutputTokens = int64Value(totalTokenUsage["reasoning_output_tokens"]) ?? 0
                            bestUsageModel = lastSeenModel
                        }
                    }
                }

            case "response_item":
                guard let payloadType = payload["type"] as? String else {
                    break
                }

                if payloadType == "function_call" || payloadType == "custom_tool_call",
                   let toolName = payload["name"] as? String,
                   !toolName.isEmpty {
                    toolCounts[toolName, default: 0] += 1
                }

            default:
                break
            }
        }

        let usage: SessionUsage?
        if maxTokenTotalForFile > 0 {
            let usageModel = bestUsageModel.isEmpty ? "<unknown>" : bestUsageModel
            let usageDate = modifiedAt
            usage = SessionUsage(
                id: "codex:\(url.path)",
                date: usageDate,
                model: usageModel,
                provider: "Codex",
                inputTokens: bestUsageInputTokens,
                cachedInputTokens: bestUsageCachedInputTokens,
                outputTokens: bestUsageOutputTokens,
                reasoningOutputTokens: bestUsageReasoningOutputTokens,
                totalTokens: maxTokenTotalForFile,
                archived: archived
            )
        } else {
            usage = nil
        }

        return SessionFileSummary(
            path: url.path,
            archived: archived,
            modifiedAt: modifiedAt,
            fileSizeBytes: fileSizeBytes,
            lineCount: lineCount,
            tokenTotal: maxTokenTotalForFile,
            modelCounts: modelCounts,
            sourceCounts: sourceCounts,
            eventTypeCounts: eventTypeCounts,
            toolCounts: toolCounts,
            sessionThreadID: sessionThreadID,
            parentThreadID: parentThreadID,
            usage: usage
        )
    }

    private func sourceDisplayName(_ source: Any) -> String {
        if let source = source as? String {
            switch source.lowercased() {
            case "vscode":
                return "Cursor / VS Code"
            case "exec":
                return "Exec"
            case "cli":
                return "CLI"
            default:
                return source
            }
        }

        if let dict = source as? [String: Any],
           let subagent = dict["subagent"] as? [String: Any],
           let threadSpawn = subagent["thread_spawn"] as? [String: Any] {
            let role = (threadSpawn["agent_role"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let nickname = (threadSpawn["agent_nickname"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

            if let role, !role.isEmpty, let nickname, !nickname.isEmpty {
                return "CLI (Subagent \(role): \(nickname))"
            }
            if let role, !role.isEmpty {
                return "CLI (Subagent \(role))"
            }
            return "CLI (Subagent)"
        }

        return jsonString(source)
    }

    private func subagentParentThreadID(from source: Any) -> String? {
        guard let dict = source as? [String: Any],
              let subagent = dict["subagent"] as? [String: Any],
              let threadSpawn = subagent["thread_spawn"] as? [String: Any],
              let parentThreadID = threadSpawn["parent_thread_id"] as? String else {
            return nil
        }
        return parentThreadID.lowercased()
    }

    private func jsonString(_ object: Any) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let value = String(data: data, encoding: .utf8) else {
            return String(describing: object)
        }
        return value
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
