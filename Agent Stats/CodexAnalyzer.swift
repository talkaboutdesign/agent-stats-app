import Foundation
import SQLite3

actor CodexAnalyzer {
    private struct MutableAnalysis {
        var sessionsSizeBytes: Int64 = 0
        var archivedSessionsSizeBytes: Int64 = 0
        var sessionFileCount = 0
        var archivedSessionFileCount = 0
        var sessionLineCount = 0
        var archivedSessionLineCount = 0

        var totalThreads = 0
        var archivedThreads = 0
        var totalTokensFromThreads: Int64 = 0
        var totalTokensFromEventFiles: Int64 = 0

        var logErrorCount = 0
        var logWarnCount = 0

        var threads: [ThreadSummary] = []
        var sessionUsages: [SessionUsage] = []
        var modelCounts: [String: Int] = [:]
        var sourceCounts: [String: Int] = [:]
        var eventTypeCounts: [String: Int] = [:]
        var toolCounts: [String: Int] = [:]
    }

    func analyze(
        codexURL: URL,
        cachedFileSummaries: [String: SessionFileSummary]
    ) async throws -> CodexAnalysisResult {
        var analysis = MutableAnalysis()
        var refreshedFileSummaries: [SessionFileSummary] = []
        refreshedFileSummaries.reserveCapacity(cachedFileSummaries.count + 64)

        let codexSizeBytes = directorySize(at: codexURL)

        let sessionsURL = codexURL.appendingPathComponent("sessions", isDirectory: true)
        let archivedSessionsURL = codexURL.appendingPathComponent("archived_sessions", isDirectory: true)

        let sessionFiles = jsonlFiles(in: sessionsURL, recursive: true)
        let archivedFiles = jsonlFiles(in: archivedSessionsURL, recursive: false)

        analysis.sessionFileCount = sessionFiles.count
        analysis.archivedSessionFileCount = archivedFiles.count
        analysis.sessionsSizeBytes = sessionFiles.reduce(0) { $0 + fileSize($1) }
        analysis.archivedSessionsSizeBytes = archivedFiles.reduce(0) { $0 + fileSize($1) }

        let stateDB = codexURL.appendingPathComponent("state_5.sqlite")
        if FileManager.default.fileExists(atPath: stateDB.path) {
            parseStateDatabase(stateDB, into: &analysis)
        }

        for file in sessionFiles {
            processSessionFile(
                file,
                archived: false,
                cachedFileSummaries: cachedFileSummaries,
                into: &analysis,
                refreshedFileSummaries: &refreshedFileSummaries
            )
        }

        for file in archivedFiles {
            processSessionFile(
                file,
                archived: true,
                cachedFileSummaries: cachedFileSummaries,
                into: &analysis,
                refreshedFileSummaries: &refreshedFileSummaries
            )
        }

        let rulesAllowCount = parseRulesAllowCount(codexURL.appendingPathComponent("rules/default.rules"))
        let installedSkillCount = parseInstalledSkillCount(codexURL.appendingPathComponent("skills", isDirectory: true))
        let projectTrustCount = parseProjectTrustCount(codexURL.appendingPathComponent("config.toml"))

        if analysis.logErrorCount == 0, analysis.logWarnCount == 0 {
            let logCounts = parseLogFileCounts(codexURL.appendingPathComponent("log/codex-tui.log"))
            analysis.logErrorCount = logCounts.errors
            analysis.logWarnCount = logCounts.warnings
        }

        let sortedThreads = analysis.threads.sorted {
            ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast)
        }

        let snapshot = CodexSnapshot(
            codexPath: codexURL.path,
            generatedAt: Date(),
            codexSizeBytes: codexSizeBytes,
            sessionsSizeBytes: analysis.sessionsSizeBytes,
            archivedSessionsSizeBytes: analysis.archivedSessionsSizeBytes,
            sessionFileCount: analysis.sessionFileCount,
            archivedSessionFileCount: analysis.archivedSessionFileCount,
            sessionLineCount: analysis.sessionLineCount,
            archivedSessionLineCount: analysis.archivedSessionLineCount,
            totalThreads: analysis.totalThreads,
            activeThreads: max(analysis.totalThreads - analysis.archivedThreads, 0),
            archivedThreads: analysis.archivedThreads,
            totalTokensFromThreads: analysis.totalTokensFromThreads,
            totalTokensFromEventFiles: analysis.totalTokensFromEventFiles,
            rulesAllowCount: rulesAllowCount,
            installedSkillCount: installedSkillCount,
            projectTrustCount: projectTrustCount,
            logErrorCount: analysis.logErrorCount,
            logWarnCount: analysis.logWarnCount,
            threads: Array(sortedThreads.prefix(250)),
            sessionUsages: analysis.sessionUsages,
            modelCounts: topCounts(analysis.modelCounts, limit: 20),
            sourceCounts: topCounts(analysis.sourceCounts, limit: 20),
            eventTypeCounts: topCounts(analysis.eventTypeCounts, limit: 20),
            toolCounts: topCounts(analysis.toolCounts, limit: 30)
        )

        return CodexAnalysisResult(
            snapshot: snapshot,
            fileSummaries: refreshedFileSummaries
        )
    }

    private func parseStateDatabase(_ dbURL: URL, into analysis: inout MutableAnalysis) {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            return
        }
        defer { sqlite3_close(db) }

        if let values = queryIntRow(
            db: db,
            sql: "SELECT COUNT(*), SUM(COALESCE(tokens_used,0)), SUM(CASE WHEN archived = 1 THEN 1 ELSE 0 END) FROM threads",
            columnCount: 3
        ) {
            analysis.totalThreads = Int(values[0])
            analysis.totalTokensFromThreads = values[1]
            analysis.archivedThreads = Int(values[2])
        }

        if let values = queryIntRow(
            db: db,
            sql: "SELECT SUM(CASE WHEN level = 'ERROR' THEN 1 ELSE 0 END), SUM(CASE WHEN level = 'WARN' THEN 1 ELSE 0 END) FROM logs",
            columnCount: 2
        ) {
            analysis.logErrorCount = Int(values[0])
            analysis.logWarnCount = Int(values[1])
        }

        let sql = """
        SELECT
            id,
            created_at,
            updated_at,
            COALESCE(source,''),
            COALESCE(model_provider,''),
            COALESCE(cwd,''),
            COALESCE(title,''),
            COALESCE(sandbox_policy,''),
            COALESCE(approval_mode,''),
            COALESCE(tokens_used, 0),
            COALESCE(archived, 0),
            COALESCE(git_branch, '')
        FROM threads
        ORDER BY updated_at DESC
        LIMIT 500
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            return
        }
        defer { sqlite3_finalize(stmt) }

        while sqlite3_step(stmt) == SQLITE_ROW {
            let thread = ThreadSummary(
                id: stringValue(stmt, 0),
                createdAt: dateFromEpochSeconds(sqlite3_column_int64(stmt, 1)),
                updatedAt: dateFromEpochSeconds(sqlite3_column_int64(stmt, 2)),
                source: normalizedSource(stringValue(stmt, 3)),
                modelProvider: stringValue(stmt, 4),
                cwd: stringValue(stmt, 5),
                title: stringValue(stmt, 6),
                sandboxPolicy: stringValue(stmt, 7),
                approvalMode: stringValue(stmt, 8),
                tokensUsed: Int(sqlite3_column_int64(stmt, 9)),
                archived: sqlite3_column_int64(stmt, 10) != 0,
                gitBranch: stringValue(stmt, 11)
            )
            analysis.threads.append(thread)
        }
    }

    private func processSessionFile(
        _ url: URL,
        archived: Bool,
        cachedFileSummaries: [String: SessionFileSummary],
        into analysis: inout MutableAnalysis,
        refreshedFileSummaries: inout [SessionFileSummary]
    ) {
        let path = url.path
        let modifiedAt = modificationDate(for: url) ?? .distantPast
        let currentFileSize = fileSize(url)

        if let cached = cachedFileSummaries[path],
           cached.archived == archived,
           cached.modifiedAt == modifiedAt,
           cached.fileSizeBytes == currentFileSize {
            applySessionSummary(cached, into: &analysis)
            refreshedFileSummaries.append(cached)
            return
        }

        let parsed = parseSessionJSONL(
            url,
            archived: archived,
            modifiedAt: modifiedAt,
            fileSizeBytes: currentFileSize
        )
        applySessionSummary(parsed, into: &analysis)
        refreshedFileSummaries.append(parsed)
    }

    private func applySessionSummary(_ summary: SessionFileSummary, into analysis: inout MutableAnalysis) {
        if summary.archived {
            analysis.archivedSessionLineCount += summary.lineCount
        } else {
            analysis.sessionLineCount += summary.lineCount
        }

        analysis.totalTokensFromEventFiles += summary.tokenTotal
        merge(summary.modelCounts, into: &analysis.modelCounts)
        merge(summary.sourceCounts, into: &analysis.sourceCounts)
        merge(summary.eventTypeCounts, into: &analysis.eventTypeCounts)
        merge(summary.toolCounts, into: &analysis.toolCounts)

        if let usage = summary.usage {
            analysis.sessionUsages.append(usage)
        }
    }

    private func merge(_ incoming: [String: Int], into target: inout [String: Int]) {
        for (key, value) in incoming {
            target[key, default: 0] += value
        }
    }

    private func parseSessionJSONL(
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
        var sessionDate: Date?
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

            if sessionDate == nil, let timestamp = root["timestamp"] as? String {
                sessionDate = parseISO8601(timestamp)
            }

            if type == "session_meta", let payload = root["payload"] as? [String: Any] {
                if sessionDate == nil, let timestamp = payload["timestamp"] as? String {
                    sessionDate = parseISO8601(timestamp)
                }

                if let source = payload["source"] as? String {
                    sourceCounts[sourceDisplayName(source), default: 0] += 1
                } else if let source = payload["source"] {
                    sourceCounts[jsonString(source), default: 0] += 1
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
            let usageDate = sessionDate ?? modifiedAt
            usage = SessionUsage(
                id: url.lastPathComponent,
                date: usageDate,
                model: usageModel,
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
            usage: usage
        )
    }

    private func parseRulesAllowCount(_ rulesURL: URL) -> Int {
        guard let text = try? String(contentsOf: rulesURL, encoding: .utf8) else {
            return 0
        }

        var count = 0
        text.enumerateLines { line, _ in
            if line.contains("decision=\"allow\"") || line.contains("decision='allow'") {
                count += 1
            }
        }
        return count
    }

    private func parseInstalledSkillCount(_ skillsURL: URL) -> Int {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: skillsURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var count = 0
        for entry in entries {
            let values = try? entry.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true else { continue }
            if entry.lastPathComponent == ".system" { continue }
            count += 1
        }
        return count
    }

    private func parseProjectTrustCount(_ configURL: URL) -> Int {
        guard let text = try? String(contentsOf: configURL, encoding: .utf8) else {
            return 0
        }

        var count = 0
        text.enumerateLines { line, _ in
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("[projects.\"") {
                count += 1
            }
        }
        return count
    }

    private func parseLogFileCounts(_ logURL: URL) -> (errors: Int, warnings: Int) {
        guard let text = try? String(contentsOf: logURL, encoding: .utf8) else {
            return (0, 0)
        }

        var errors = 0
        var warnings = 0

        for lineSlice in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(lineSlice)
            if line.contains(" ERROR ") || line.hasSuffix(" ERROR") {
                errors += 1
            }
            if line.contains(" WARN ") || line.hasSuffix(" WARN") {
                warnings += 1
            }
        }

        return (errors, warnings)
    }

    private func topCounts(_ map: [String: Int], limit: Int) -> [CountStat] {
        map
            .map { CountStat(key: $0.key, count: $0.value) }
            .sorted { lhs, rhs in
                if lhs.count == rhs.count { return lhs.key < rhs.key }
                return lhs.count > rhs.count
            }
            .prefix(limit)
            .map { $0 }
    }

    private func jsonlFiles(in folderURL: URL, recursive: Bool) -> [URL] {
        guard FileManager.default.fileExists(atPath: folderURL.path) else {
            return []
        }

        if recursive {
            guard let enumerator = FileManager.default.enumerator(
                at: folderURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                return []
            }

            var results: [URL] = []
            for case let url as URL in enumerator {
                if url.pathExtension == "jsonl" {
                    results.append(url)
                }
            }
            return results
        }

        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return entries.filter { $0.pathExtension == "jsonl" }
    }

    private func directorySize(at url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true,
                  let fileSize = values.fileSize else {
                continue
            }
            total += Int64(fileSize)
        }
        return total
    }

    private func fileSize(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

    private func modificationDate(for url: URL) -> Date? {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate
    }

    private func parseISO8601(_ string: String) -> Date? {
        if let value = iso8601FullFormatter.date(from: string) {
            return value
        }
        return iso8601Formatter.date(from: string)
    }

    private func normalizedSource(_ source: String) -> String {
        guard !source.isEmpty else {
            return "<unknown>"
        }

        guard let data = source.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return sourceDisplayName(source)
        }
        return sourceDisplayName(jsonString(object))
    }

    private func sourceDisplayName(_ source: String) -> String {
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

    private func dateFromEpochSeconds(_ value: Int64) -> Date? {
        guard value > 0 else {
            return nil
        }
        return Date(timeIntervalSince1970: TimeInterval(value))
    }

    private func queryIntRow(db: OpaquePointer, sql: String, columnCount: Int32) -> [Int64]? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            return nil
        }

        defer { sqlite3_finalize(stmt) }

        guard sqlite3_step(stmt) == SQLITE_ROW else {
            return nil
        }

        var values: [Int64] = []
        values.reserveCapacity(Int(columnCount))
        for index in 0..<columnCount {
            values.append(sqlite3_column_int64(stmt, index))
        }
        return values
    }

    private func stringValue(_ statement: OpaquePointer?, _ index: Int32) -> String {
        guard let pointer = sqlite3_column_text(statement, index) else {
            return ""
        }
        return String(cString: pointer)
    }

    private let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private let iso8601FullFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
