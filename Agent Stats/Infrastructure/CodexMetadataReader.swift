import Foundation

nonisolated struct CodexMetadataReader {
    func rulesAllowCount(_ rulesURL: URL) -> Int {
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

    func installedSkillCount(_ skillsURL: URL) -> Int {
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

    func projectTrustCount(_ configURL: URL) -> Int {
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

    func logFileCounts(_ logURL: URL) -> (errors: Int, warnings: Int) {
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
}
