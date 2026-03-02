import Foundation

nonisolated struct CLIProviderLimitFetcher: ProviderLimitFetching {
    private let environment: FileSystemEnvironment
    private let commandRunner: CommandRunning

    init(
        environment: FileSystemEnvironment = FileSystemEnvironment(),
        commandRunner: CommandRunning = ProcessCommandRunner()
    ) {
        self.environment = environment
        self.commandRunner = commandRunner
    }

    func fetchProviderLimits() async -> [ProviderLimitStatus] {
        let codex = codexLimitStatusFromCLIAndAuth()
        let claude = claudeLimitStatusFromCLI()
        return [codex, claude]
            .compactMap { $0 }
            .sorted { $0.provider < $1.provider }
    }

    private func codexLimitStatusFromCLIAndAuth() -> ProviderLimitStatus? {
        let loginStatus = commandRunner.run("codex", arguments: ["login", "status"], timeout: 4)
        let loginSummary = loginStatus.map { squashWhitespace($0.stdout) } ?? ""

        let authURL = environment.codexURL.appendingPathComponent("auth.json")
        guard let data = try? Data(contentsOf: authURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = object["tokens"] as? [String: Any],
              let idToken = tokens["id_token"] as? String,
              let claims = decodeJWTClaims(idToken),
              let auth = claims["https://api.openai.com/auth"] as? [String: Any] else {
            return ProviderLimitStatus(
                provider: "Codex",
                plan: "Unknown",
                renewalDate: nil,
                usageSummary: loginSummary.isEmpty ? "Usage limits unavailable" : loginSummary,
                source: "codex login status",
                lastCheckedAt: Date(),
                errorText: nil
            )
        }

        let plan = (auth["chatgpt_plan_type"] as? String)?
            .replacingOccurrences(of: "_", with: " ")
            .capitalized ?? "ChatGPT"
        let renewalDate = parseISO8601Date(auth["chatgpt_subscription_active_until"] as? String)
        let lastChecked = parseISO8601Date(auth["chatgpt_subscription_last_checked"] as? String) ?? Date()
        let usageSummary = loginSummary.isEmpty
            ? "Live quota usage is not exposed by non-interactive Codex CLI."
            : loginSummary

        return ProviderLimitStatus(
            provider: "Codex",
            plan: plan,
            renewalDate: renewalDate,
            usageSummary: usageSummary,
            source: loginSummary.isEmpty ? "local auth" : "codex login status + local auth",
            lastCheckedAt: lastChecked,
            errorText: nil
        )
    }

    private func claudeLimitStatusFromCLI() -> ProviderLimitStatus? {
        if let statusOutput = commandRunner.run(
            "claude",
            arguments: ["-p", "/status", "--output-format", "text", "--verbose"],
            timeout: 6
        ), statusOutput.exitCode == 0 {
            let message = squashWhitespace(statusOutput.stdout)
            let lowered = message.lowercased()
            if !message.isEmpty, !lowered.contains("unknown skill: status") {
                return ProviderLimitStatus(
                    provider: "Claude",
                    plan: "Subscription",
                    renewalDate: nil,
                    usageSummary: message,
                    source: "claude /status",
                    lastCheckedAt: Date(),
                    errorText: nil
                )
            }
        }

        if let accountOutput = commandRunner.run(
            "claude",
            arguments: ["-p", "/account", "--output-format", "text", "--verbose"],
            timeout: 6
        ), accountOutput.exitCode == 0 {
            let message = squashWhitespace(accountOutput.stdout)
            let lowered = message.lowercased()

            if !message.isEmpty, !lowered.contains("unknown skill: account") {
                return ProviderLimitStatus(
                    provider: "Claude",
                    plan: "Subscription",
                    renewalDate: nil,
                    usageSummary: message,
                    source: "claude /account",
                    lastCheckedAt: Date(),
                    errorText: nil
                )
            }
        }

        guard let output = commandRunner.run("claude", arguments: ["auth", "status"], timeout: 4),
              output.exitCode == 0 else {
            return ProviderLimitStatus(
                provider: "Claude",
                plan: "Unknown",
                renewalDate: nil,
                usageSummary: "Usage limits unavailable",
                source: "claude auth status",
                lastCheckedAt: Date(),
                errorText: nil
            )
        }

        let outputText = squashWhitespace(output.stdout)
        guard let data = output.stdout.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ProviderLimitStatus(
                provider: "Claude",
                plan: "Unknown",
                renewalDate: nil,
                usageSummary: outputText.isEmpty ? "Usage limits unavailable" : outputText,
                source: "claude auth status",
                lastCheckedAt: Date(),
                errorText: nil
            )
        }

        let subscriptionType = (object["subscriptionType"] as? String)?
            .replacingOccurrences(of: "_", with: " ")
            .capitalized ?? "Unknown"
        let orgName = object["orgName"] as? String
        let authMethod = object["authMethod"] as? String

        var summaryParts: [String] = []
        if let orgName, !orgName.isEmpty {
            summaryParts.append(orgName)
        }
        if let authMethod, !authMethod.isEmpty {
            summaryParts.append(authMethod)
        }
        if summaryParts.isEmpty {
            summaryParts.append("Subscription")
        }

        return ProviderLimitStatus(
            provider: "Claude",
            plan: subscriptionType,
            renewalDate: nil,
            usageSummary: outputText.isEmpty ? "No renewal/remaining quota field from CLI auth status." : outputText,
            source: summaryParts.joined(separator: " • "),
            lastCheckedAt: Date(),
            errorText: nil
        )
    }

    private func decodeJWTClaims(_ token: String) -> [String: Any]? {
        let segments = token.split(separator: ".")
        guard segments.count >= 2 else { return nil }

        let payload = String(segments[1])
        let padded = payload + String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let payloadData = Data(base64Encoded: padded.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")),
            let object = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else {
            return nil
        }
        return object
    }

    private func parseISO8601Date(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }
        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        return basic.date(from: value)
    }

    private func squashWhitespace(_ text: String) -> String {
        let parts = text.split(whereSeparator: \.isWhitespace)
        return parts.joined(separator: " ")
    }
}
