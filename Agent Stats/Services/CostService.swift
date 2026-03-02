import Foundation

nonisolated struct CostService: CostCalculating {
    func calculateCostSummary(
        snapshot: CodexSnapshot,
        pricingSnapshot: PricingSnapshot?
    ) -> CostSummary? {
        guard let pricingSnapshot else {
            return nil
        }

        let pricingByModel = Dictionary(
            uniqueKeysWithValues: pricingSnapshot.models.map { ($0.model.lowercased(), $0) }
        )

        let calendar = Calendar.current
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        let weekInterval = calendar.dateInterval(of: .weekOfYear, for: now)
        let monthInterval = calendar.dateInterval(of: .month, for: now)

        var today = 0.0
        var thisWeek = 0.0
        var thisMonth = 0.0
        var allTime = 0.0

        var dailyCosts: [Date: Double] = [:]
        var byModel: [String: (cost: Double, sessions: Int)] = [:]
        var unmatched = Set<String>()

        for usage in snapshot.sessionUsages {
            let modelKey = ModelNameNormalizer.canonicalName(usage.model, availableModels: pricingByModel)
            guard let pricing = pricingByModel[modelKey] else {
                unmatched.insert(usage.model)
                continue
            }

            let usageCost = TokenMath.sessionCost(usage, pricing: pricing)
            let day = calendar.startOfDay(for: usage.date)

            allTime += usageCost
            dailyCosts[day, default: 0] += usageCost

            if day == todayStart {
                today += usageCost
            }
            if let weekInterval, usage.date >= weekInterval.start, usage.date < weekInterval.end {
                thisWeek += usageCost
            }
            if let monthInterval, usage.date >= monthInterval.start, usage.date < monthInterval.end {
                thisMonth += usageCost
            }

            let modelLabel = pricing.model
            var row = byModel[modelLabel, default: (0, 0)]
            row.cost += usageCost
            row.sessions += 1
            byModel[modelLabel] = row
        }

        let modelRows = byModel
            .map { ModelCostRow(model: $0.key, cost: $0.value.cost, sessions: $0.value.sessions) }
            .sorted { lhs, rhs in
                if lhs.cost == rhs.cost { return lhs.model < rhs.model }
                return lhs.cost > rhs.cost
            }

        let daily = dailyCosts
            .map { CostPoint(date: $0.key, cost: $0.value) }
            .sorted { $0.date < $1.date }

        return CostSummary(
            today: today,
            thisWeek: thisWeek,
            thisMonth: thisMonth,
            allTime: allTime,
            modelRows: modelRows,
            daily: daily,
            unmatchedModels: Array(unmatched).sorted()
        )
    }
}
