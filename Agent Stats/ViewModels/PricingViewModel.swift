import Foundation

struct PricingViewModel {
    let recentRows: [LiveSessionRow]
    let rangeModelRows: [ModelCostRow]
    let rangeCost: Double
    let rangeTokens: Int64
    let liveNow: Int
    let trendModels: [String]
    let modelCostTrends: [ModelSeriesPoint]
    let modelUsageTrends: [ModelSeriesPoint]

    init(liveSessions: [LiveSessionRow], cutoff: Date) {
        recentRows = liveSessions.filter { $0.lastUpdated >= cutoff }
        rangeModelRows = Self.modelRows(from: recentRows)
        rangeCost = recentRows.reduce(0.0) { $0 + $1.estimatedCost }
        rangeTokens = recentRows.reduce(Int64(0)) { $0 + $1.totalTokens }
        liveNow = recentRows.filter(\.isActiveNow).count

        trendModels = Array(rangeModelRows.prefix(5).map(\.model))
        modelCostTrends = Self.trendPoints(from: recentRows, models: trendModels, cutoff: cutoff) { $0.estimatedCost }
        modelUsageTrends = Self.trendPoints(from: recentRows, models: trendModels, cutoff: cutoff) { _ in 1 }
    }

    private static func modelRows(from sessions: [LiveSessionRow]) -> [ModelCostRow] {
        var grouped: [String: (cost: Double, sessions: Int)] = [:]

        for row in sessions {
            let modelName = row.model.modelDisplayName
            var aggregate = grouped[modelName] ?? (cost: 0, sessions: 0)
            aggregate.cost += row.estimatedCost
            aggregate.sessions += 1
            grouped[modelName] = aggregate
        }

        return grouped.map { model, aggregate in
            ModelCostRow(model: model, cost: aggregate.cost, sessions: aggregate.sessions)
        }
        .sorted { lhs, rhs in
            if lhs.cost == rhs.cost {
                return lhs.model < rhs.model
            }
            return lhs.cost > rhs.cost
        }
    }

    private static func dayBuckets(from cutoff: Date, to endDate: Date = Date()) -> [Date] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: cutoff)
        let end = calendar.startOfDay(for: endDate)
        guard start <= end else { return [] }

        var dates: [Date] = []
        var current = start
        while current <= end {
            dates.append(current)
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return dates
    }

    private static func trendPoints(
        from sessions: [LiveSessionRow],
        models: [String],
        cutoff: Date,
        valueForRow: (LiveSessionRow) -> Double
    ) -> [ModelSeriesPoint] {
        guard !models.isEmpty else { return [] }

        let calendar = Calendar.current
        let buckets = dayBuckets(from: cutoff)
        let modelSet = Set(models)
        var grouped: [String: [Date: Double]] = [:]

        for row in sessions {
            let modelName = row.model.modelDisplayName
            guard modelSet.contains(modelName) else { continue }
            let day = calendar.startOfDay(for: row.lastUpdated)
            grouped[modelName, default: [:]][day, default: 0] += valueForRow(row)
        }

        var points: [ModelSeriesPoint] = []
        for model in models {
            for day in buckets {
                points.append(
                    ModelSeriesPoint(
                        date: day,
                        model: model,
                        value: grouped[model]?[day] ?? 0
                    )
                )
            }
        }
        return points
    }
}
