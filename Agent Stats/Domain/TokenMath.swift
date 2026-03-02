import Foundation

nonisolated enum TokenMath {
    static func displayTokenCount(for usage: SessionUsage) -> Int64 {
        let uncachedInput = usage.provider == "Codex"
            ? max(usage.inputTokens - usage.cachedInputTokens, 0)
            : usage.inputTokens
        return max(uncachedInput + usage.outputTokens, 0)
    }

    static func sessionCost(_ usage: SessionUsage, pricing: ModelPricing) -> Double {
        let includesCachedInInput = usage.provider == "Codex"
        let rawInputTokens = Double(usage.inputTokens)
        let cachedInputTokens = Double(usage.cachedInputTokens)
        let billableInputTokens = includesCachedInInput
            ? max(rawInputTokens - cachedInputTokens, 0)
            : rawInputTokens

        let inputCost = billableInputTokens / 1_000_000.0 * pricing.inputPerM
        let cachedInputCost = cachedInputTokens / 1_000_000.0 * (pricing.cachedInputPerM ?? 0)
        let write5mTokens = usage.cacheWrite5mTokens > 0
            ? usage.cacheWrite5mTokens
            : max(usage.cacheWriteTokens - usage.cacheWrite1hTokens, 0)
        let write1hTokens = usage.cacheWrite1hTokens
        let cacheWrite5mCost = Double(write5mTokens) / 1_000_000.0 * (pricing.cacheWritePerM ?? 0)
        let cacheWrite1hCost = Double(write1hTokens) / 1_000_000.0 * (pricing.cacheWrite1hPerM ?? pricing.cacheWritePerM ?? 0)
        let outputCost = Double(usage.outputTokens) / 1_000_000.0 * (pricing.outputPerM ?? 0)
        return inputCost + cachedInputCost + cacheWrite5mCost + cacheWrite1hCost + outputCost
    }
}
