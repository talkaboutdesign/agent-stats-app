import Foundation

nonisolated struct CommandResult {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

nonisolated protocol CommandRunning {
    func run(
        _ executable: String,
        arguments: [String],
        timeout: TimeInterval
    ) -> CommandResult?
}

nonisolated struct ProcessCommandRunner: CommandRunning {
    func run(
        _ executable: String,
        arguments: [String],
        timeout: TimeInterval
    ) -> CommandResult? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return nil
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        if process.isRunning {
            process.terminate()
            return nil
        }

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""
        return CommandResult(stdout: stdout, stderr: stderr, exitCode: process.terminationStatus)
    }
}
