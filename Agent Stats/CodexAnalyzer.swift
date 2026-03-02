import Foundation

actor CodexAnalyzer: SnapshotAnalyzing {
    private enum SessionFormat {
        case codex
        case claude
    }

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

    private let environment: FileSystemEnvironment
    private let scanner: SessionFileScanner
    private let stateDatabaseReader: StateDatabaseReader
    private let metadataReader: CodexMetadataReader
    private let codexParser: SessionSummaryParsing
    private let claudeParser: SessionSummaryParsing

    init(
        environment: FileSystemEnvironment,
        scanner: SessionFileScanner,
        stateDatabaseReader: StateDatabaseReader,
        metadataReader: CodexMetadataReader,
        codexParser: SessionSummaryParsing,
        claudeParser: SessionSummaryParsing
    ) {
        self.environment = environment
        self.scanner = scanner
        self.stateDatabaseReader = stateDatabaseReader
        self.metadataReader = metadataReader
        self.codexParser = codexParser
        self.claudeParser = claudeParser
    }

    init() {
        self.environment = FileSystemEnvironment()
        self.scanner = SessionFileScanner()
        self.stateDatabaseReader = StateDatabaseReader()
        self.metadataReader = CodexMetadataReader()
        self.codexParser = CodexSessionParser()
        self.claudeParser = ClaudeSessionParser()
    }

    func analyze(
        codexURL: URL,
        cachedFileSummaries: [String: SessionFileSummary]
    ) async throws -> CodexAnalysisResult {
        var analysis = MutableAnalysis()
        var refreshedFileSummaries: [SessionFileSummary] = []
        refreshedFileSummaries.reserveCapacity(cachedFileSummaries.count + 64)

        let codexSizeBytes = scanner.directorySize(at: codexURL)

        let sessionsURL = codexURL.appendingPathComponent("sessions", isDirectory: true)
        let archivedSessionsURL = codexURL.appendingPathComponent("archived_sessions", isDirectory: true)

        let sessionFiles = scanner.jsonlFiles(in: sessionsURL, recursive: true)
        let archivedFiles = scanner.jsonlFiles(in: archivedSessionsURL, recursive: false)

        analysis.sessionFileCount = sessionFiles.count
        analysis.archivedSessionFileCount = archivedFiles.count
        analysis.sessionsSizeBytes = sessionFiles.reduce(0) { $0 + scanner.fileSize($1) }
        analysis.archivedSessionsSizeBytes = archivedFiles.reduce(0) { $0 + scanner.fileSize($1) }

        let stateDB = codexURL.appendingPathComponent("state_5.sqlite")
        if environment.exists(stateDB), let dbSnapshot = stateDatabaseReader.read(at: stateDB) {
            analysis.totalThreads = dbSnapshot.totalThreads
            analysis.archivedThreads = dbSnapshot.archivedThreads
            analysis.totalTokensFromThreads = dbSnapshot.totalTokensFromThreads
            analysis.logErrorCount = dbSnapshot.logErrorCount
            analysis.logWarnCount = dbSnapshot.logWarnCount
            analysis.threads = dbSnapshot.threads
        }

        for file in sessionFiles {
            processSessionFile(
                file,
                archived: false,
                format: .codex,
                cachedFileSummaries: cachedFileSummaries,
                into: &analysis,
                refreshedFileSummaries: &refreshedFileSummaries
            )
        }

        for file in archivedFiles {
            processSessionFile(
                file,
                archived: true,
                format: .codex,
                cachedFileSummaries: cachedFileSummaries,
                into: &analysis,
                refreshedFileSummaries: &refreshedFileSummaries
            )
        }

        let claudeProjectsURL = environment.claudeURL.appendingPathComponent("projects", isDirectory: true)
        let claudeSessionFiles = scanner.jsonlFiles(in: claudeProjectsURL, recursive: true)
            .filter { !$0.path.contains("/subagents/") }

        analysis.sessionFileCount += claudeSessionFiles.count
        analysis.sessionsSizeBytes += claudeSessionFiles.reduce(0) { $0 + scanner.fileSize($1) }

        for file in claudeSessionFiles {
            processSessionFile(
                file,
                archived: false,
                format: .claude,
                cachedFileSummaries: cachedFileSummaries,
                into: &analysis,
                refreshedFileSummaries: &refreshedFileSummaries
            )
        }

        let rulesAllowCount = metadataReader.rulesAllowCount(codexURL.appendingPathComponent("rules/default.rules"))
        let installedSkillCount = metadataReader.installedSkillCount(codexURL.appendingPathComponent("skills", isDirectory: true))
        let projectTrustCount = metadataReader.projectTrustCount(codexURL.appendingPathComponent("config.toml"))

        if analysis.logErrorCount == 0, analysis.logWarnCount == 0 {
            let logCounts = metadataReader.logFileCounts(codexURL.appendingPathComponent("log/codex-tui.log"))
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

    private func processSessionFile(
        _ url: URL,
        archived: Bool,
        format: SessionFormat,
        cachedFileSummaries: [String: SessionFileSummary],
        into analysis: inout MutableAnalysis,
        refreshedFileSummaries: inout [SessionFileSummary]
    ) {
        let path = url.path
        let modifiedAt = scanner.modificationDate(for: url) ?? .distantPast
        let currentFileSize = scanner.fileSize(url)

        if let cached = cachedFileSummaries[path],
           cached.archived == archived,
           cached.modifiedAt == modifiedAt,
           cached.fileSizeBytes == currentFileSize {
            applySessionSummary(cached, into: &analysis)
            refreshedFileSummaries.append(cached)
            return
        }

        let parser: SessionSummaryParsing
        switch format {
        case .codex:
            parser = codexParser
        case .claude:
            parser = claudeParser
        }

        let parsed = parser.parse(
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
}
