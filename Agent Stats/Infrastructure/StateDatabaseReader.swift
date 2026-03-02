import Foundation
import SQLite3

nonisolated struct StateDatabaseSnapshot {
    var totalThreads: Int
    var archivedThreads: Int
    var totalTokensFromThreads: Int64
    var logErrorCount: Int
    var logWarnCount: Int
    var threads: [ThreadSummary]
}

nonisolated struct StateDatabaseReader {
    func read(at dbURL: URL) -> StateDatabaseSnapshot? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            return nil
        }
        defer { sqlite3_close(db) }

        var snapshot = StateDatabaseSnapshot(
            totalThreads: 0,
            archivedThreads: 0,
            totalTokensFromThreads: 0,
            logErrorCount: 0,
            logWarnCount: 0,
            threads: []
        )

        if let values = queryIntRow(
            db: db,
            sql: "SELECT COUNT(*), SUM(COALESCE(tokens_used,0)), SUM(CASE WHEN archived = 1 THEN 1 ELSE 0 END) FROM threads",
            columnCount: 3
        ) {
            snapshot.totalThreads = Int(values[0])
            snapshot.totalTokensFromThreads = values[1]
            snapshot.archivedThreads = Int(values[2])
        }

        if let values = queryIntRow(
            db: db,
            sql: "SELECT SUM(CASE WHEN level = 'ERROR' THEN 1 ELSE 0 END), SUM(CASE WHEN level = 'WARN' THEN 1 ELSE 0 END) FROM logs",
            columnCount: 2
        ) {
            snapshot.logErrorCount = Int(values[0])
            snapshot.logWarnCount = Int(values[1])
        }

        let sql = """
        SELECT
            id,
            COALESCE(rollout_path,''),
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
            return snapshot
        }
        defer { sqlite3_finalize(stmt) }

        while sqlite3_step(stmt) == SQLITE_ROW {
            let thread = ThreadSummary(
                id: stringValue(stmt, 0),
                rolloutPath: stringValue(stmt, 1),
                createdAt: dateFromEpochSeconds(sqlite3_column_int64(stmt, 2)),
                updatedAt: dateFromEpochSeconds(sqlite3_column_int64(stmt, 3)),
                source: normalizedSource(stringValue(stmt, 4)),
                modelProvider: stringValue(stmt, 5),
                cwd: stringValue(stmt, 6),
                title: stringValue(stmt, 7),
                sandboxPolicy: stringValue(stmt, 8),
                approvalMode: stringValue(stmt, 9),
                tokensUsed: Int(sqlite3_column_int64(stmt, 10)),
                archived: sqlite3_column_int64(stmt, 11) != 0,
                gitBranch: stringValue(stmt, 12)
            )
            snapshot.threads.append(thread)
        }

        return snapshot
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

    private func dateFromEpochSeconds(_ value: Int64) -> Date? {
        guard value > 0 else {
            return nil
        }
        return Date(timeIntervalSince1970: TimeInterval(value))
    }

    private func normalizedSource(_ source: String) -> String {
        guard !source.isEmpty else {
            return "<unknown>"
        }

        guard let data = source.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return sourceDisplayName(source as Any)
        }
        return sourceDisplayName(object)
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

    private func jsonString(_ object: Any) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let value = String(data: data, encoding: .utf8) else {
            return String(describing: object)
        }
        return value
    }
}
