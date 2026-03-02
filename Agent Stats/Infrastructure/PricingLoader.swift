import Foundation

nonisolated struct BundlePricingLoader: PricingLoading {
    private let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func loadPricingSnapshots() -> [PricingSnapshot] {
        let names = ["openai_pricing", "claude_pricing"]
        var snapshots: [PricingSnapshot] = []

        for name in names {
            guard let url = bundle.url(forResource: name, withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let snapshot = try? JSONDecoder().decode(PricingSnapshot.self, from: data) else {
                continue
            }
            snapshots.append(snapshot)
        }

        return snapshots
    }

    func mergedPricingSnapshot(_ snapshots: [PricingSnapshot]) -> PricingSnapshot? {
        guard !snapshots.isEmpty else { return nil }

        let mergedModels = snapshots.flatMap(\.models)
        let mergedSource = snapshots.map(\.source).joined(separator: " + ")
        let capturedAt = snapshots.map(\.capturedAt).joined(separator: " / ")

        return PricingSnapshot(
            source: mergedSource,
            capturedAt: capturedAt,
            type: "standard",
            models: mergedModels
        )
    }
}
