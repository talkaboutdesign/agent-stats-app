import Foundation

nonisolated enum ModelNameNormalizer {
    static func canonicalName(
        _ model: String,
        availableModels: [String: ModelPricing]
    ) -> String {
        let lowered = model.lowercased()
        if availableModels[lowered] != nil {
            return lowered
        }

        if let strippedDate = stripClaudeDateSuffix(lowered), availableModels[strippedDate] != nil {
            return strippedDate
        }

        if lowered.hasSuffix("-spark") {
            let base = String(lowered.dropLast("-spark".count))
            if availableModels[base] != nil {
                return base
            }
        }

        return lowered
    }

    private static func stripClaudeDateSuffix(_ model: String) -> String? {
        let pattern = #"-\d{8}$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(model.startIndex..., in: model)
        guard let match = regex.firstMatch(in: model, range: range),
              let swiftRange = Range(match.range, in: model) else {
            return nil
        }
        return String(model[..<swiftRange.lowerBound])
    }
}
