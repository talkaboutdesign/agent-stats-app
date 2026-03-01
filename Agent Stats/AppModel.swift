import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    var snapshot: CodexSnapshot?
    var isLoading = false
    var statusText = "Ready"
    var errorText: String?
    var codexURL: URL?

    @ObservationIgnored private let analyzer = CodexAnalyzer()

    init() {
        codexURL = defaultCodexURLIfPresent()
        if codexURL != nil {
            refresh()
        }
    }

    var codexPathLabel: String {
        guard let codexURL else {
            return "No .codex folder selected"
        }
        return abbreviateHome(codexURL.path)
    }

    func chooseCodexFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose your .codex folder"
        panel.message = "Select the ~/.codex directory"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use Folder"
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser

        if panel.runModal() == .OK, let selectedURL = panel.url {
            codexURL = selectedURL
            refresh()
        }
    }

    func refresh() {
        guard !isLoading else { return }

        guard let targetURL = codexURL ?? defaultCodexURLIfPresent() else {
            errorText = "No readable .codex folder found. Select ~/.codex using \"Choose .codex Folder\"."
            return
        }

        codexURL = targetURL
        errorText = nil
        statusText = "Analyzing .codex data..."
        isLoading = true

        Task {
            do {
                let result = try await analyzer.analyze(codexURL: targetURL)
                snapshot = result
                statusText = "Last refresh: \(result.generatedAt.friendly)"
                errorText = nil
            } catch {
                statusText = "Failed"
                errorText = "Unable to read \(abbreviateHome(targetURL.path)). \(error.localizedDescription)"
            }

            isLoading = false
        }
    }

    private func defaultCodexURLIfPresent() -> URL? {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return url
    }

    private func abbreviateHome(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
