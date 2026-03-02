import Foundation

nonisolated struct FileSystemEnvironment {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    var homeURL: URL {
        fileManager.homeDirectoryForCurrentUser
    }

    var codexURL: URL {
        homeURL.appendingPathComponent(".codex", isDirectory: true)
    }

    var claudeURL: URL {
        homeURL.appendingPathComponent(".claude", isDirectory: true)
    }

    func exists(_ url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    func codexExists() -> Bool {
        exists(codexURL)
    }

    func claudeExists() -> Bool {
        exists(claudeURL)
    }

    func abbreviateHome(_ path: String) -> String {
        let homePath = homeURL.path
        if path.hasPrefix(homePath) {
            return "~" + path.dropFirst(homePath.count)
        }
        return path
    }
}
