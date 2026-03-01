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
        var modelCounts: [String: Int] = [:]
        var sourceCounts: [String: Int] = [:]
        var eventTypeCounts: [String: Int] = [:]
        var toolCounts: [String: Int] = [:]
    }

    func analyze(codexURL: URL) async throws -> CodexSnapshot {
        var analysis = MutableAnalysis()

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
            parseSessionJSONL(file, archived: false, into: &analysis)
        }

        for file in archivedFiles {
            parseSessionJSONL(file, archived: true, into: &analysis)
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

        return CodexSnapshot(
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
            modelCounts: topCounts(analysis.modelCounts, limit: 20),
            sourceCounts: topCounts(analysis.sourceCounts, limit: 20),
            eventTypeCounts: topCounts(analysis.eventTypeCounts, limit: 20),
            toolCounts: topCounts(analysis.toolCounts, limit: 30)
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

    private func parseSessionJSONL(_ url: URL, archived: Bool, into analysis: inout MutableAnalysis) {
        guard let reader = FileLineReader(url: url) else {
            return
        }

        var maxTokenTotalForFile: Int64 = 0

        for line in reader {
            if archived {
                analysis.archivedSessionLineCount += 1
            } else {
                analysis.sessionLineCount += 1
            }

            guard let data = line.data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = root["type"] as? String else {
                continue
            }

            if type == "session_meta", let payload = root["payload"] as? [String: Any] {
                if let source = payload["source"] as? String {
                    analysis.sourceCounts[source, default: 0] += 1
                } else if let source = payload["source"] {
                    analysis.sourceCounts[jsonString(source), default: 0] += 1
                }
                if let modelProvider = payload["model_provider"] as? String {
                    analysis.modelCounts[modelProvider, default: 0] += 1
                }
                continue
            }

            guard let payload = root["payload"] as? [String: Any] else {
                continue
            }

            switch type {
            case "turn_context":
                if let model = payload["model"] as? String {
                    analysis.modelCounts[model, default: 0] += 1
                }

            case "event_msg":
                if let eventType = payload["type"] as? String {
                    analysis.eventTypeCounts[eventType, default: 0] += 1

                    if eventType == "token_count",
                       let info = payload["info"] as? [String: Any],
                       let totalTokenUsage = info["total_token_usage"] as? [String: Any],
                       let totalTokens = int64Value(totalTokenUsage["total_tokens"]) {
                        maxTokenTotalForFile = max(maxTokenTotalForFile, totalTokens)
                    }
                }

            case "response_item":
                guard let payloadType = payload["type"] as? String else {
                    break
                }

                if payloadType == "function_call" || payloadType == "custom_tool_call",
                   let toolName = payload["name"] as? String,
                   !toolName.isEmpty {
                    analysis.toolCounts[toolName, default: 0] += 1
                }

            default:
                break
            }
        }

        analysis.totalTokensFromEventFiles += maxTokenTotalForFile
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
        guard let reader = FileLineReader(url: logURL) else {
            return (0, 0)
        }

        var errors = 0
        var warnings = 0

        for line in reader {
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

    private func normalizedSource(_ source: String) -> String {
        guard !source.isEmpty else {
            return "<unknown>"
        }

        guard let data = source.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return source
        }
        return jsonString(object)
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
}

private final class FileLineReader: Sequence, IteratorProtocol {
    private let delimiter = Data([0x0A])
    private let handle: FileHandle
    private var buffer = Data()
    private var isEOF = false

    init?(url: URL) {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        self.handle = handle
    }

    deinit {
        try? handle.close()
    }

    func makeIterator() -> FileLineReader {
        self
    }

    func next() -> String? {
        while true {
            if let range = buffer.range(of: delimiter) {
                let lineData = buffer.subdata(in: 0..<range.lowerBound)
                buffer.removeSubrange(0..<range.upperBound)
                return String(decoding: lineData, as: UTF8.self)
            }

            if isEOF {
                if buffer.isEmpty {
                    return nil
                }
                let line = String(decoding: buffer, as: UTF8.self)
                buffer.removeAll(keepingCapacity: false)
                return line
            }

            do {
                let chunk = try handle.read(upToCount: 64 * 1024)
                if let chunk, !chunk.isEmpty {
                    buffer.append(chunk)
                } else {
                    isEOF = true
                }
            } catch {
                isEOF = true
            }
        }
    }
}
