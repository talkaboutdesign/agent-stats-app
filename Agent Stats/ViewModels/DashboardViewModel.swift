import Foundation

struct DashboardViewModel {
    let recentSessions: [LiveSessionRow]
    let liveCount: Int
    let topModels: [String]
    let dailyModelPoints: [ModelSeriesPoint]
    let hourlyModelPoints: [ModelHourlyUsagePoint]
    let activityHeatmap: [Date: Int]

    init(snapshot: CodexSnapshot, liveSessions: [LiveSessionRow], maxModels: Int = 5, maxRecentSessions: Int = 5) {
        recentSessions = Array(liveSessions.prefix(maxRecentSessions))
        liveCount = liveSessions.filter(\.isActiveNow).count

        topModels = Self.topModelNames(from: snapshot.sessionUsages, limit: maxModels)
        dailyModelPoints = Self.dailyModelActivity(snapshot, models: topModels)
        hourlyModelPoints = Self.hourlyModelUsage(snapshot, models: topModels)
        activityHeatmap = Self.activityByDay(snapshot.sessionUsages)
    }

    private static func topModelNames(from usages: [SessionUsage], limit: Int) -> [String] {
        var counts: [String: Int] = [:]
        for usage in usages {
            counts[usage.model.modelDisplayName, default: 0] += 1
        }

        return counts.sorted { lhs, rhs in
            if lhs.value == rhs.value {
                return lhs.key < rhs.key
            }
            return lhs.value > rhs.value
        }
        .prefix(limit)
        .map(\.key)
    }

    private static func dailyModelActivity(_ snapshot: CodexSnapshot, models: [String]) -> [ModelSeriesPoint] {
        guard !models.isEmpty else { return [] }
        let calendar = Calendar.current
        let modelSet = Set(models)
        let end = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -29, to: end) ?? end
        var buckets: [String: [Date: Double]] = [:]

        for usage in snapshot.sessionUsages {
            let modelName = usage.model.modelDisplayName
            guard modelSet.contains(modelName) else { continue }
            let day = calendar.startOfDay(for: usage.date)
            guard day >= start, day <= end else { continue }
            buckets[modelName, default: [:]][day, default: 0] += 1
        }

        var points: [ModelSeriesPoint] = []
        var cursor = start
        while cursor <= end {
            for model in models {
                points.append(ModelSeriesPoint(date: cursor, model: model, value: buckets[model]?[cursor] ?? 0))
            }
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? end.addingTimeInterval(1)
        }
        return points
    }

    private static func hourlyModelUsage(_ snapshot: CodexSnapshot, models: [String]) -> [ModelHourlyUsagePoint] {
        guard !models.isEmpty else { return [] }
        let modelSet = Set(models)
        var bucketByModelHour: [String: [Int: Double]] = [:]

        for usage in snapshot.sessionUsages {
            let modelName = usage.model.modelDisplayName
            guard modelSet.contains(modelName) else { continue }
            let hour = Calendar.current.component(.hour, from: usage.date)
            bucketByModelHour[modelName, default: [:]][hour, default: 0] += 1
        }

        var points: [ModelHourlyUsagePoint] = []
        for model in models {
            for hour in 0..<24 {
                let count = bucketByModelHour[model]?[hour] ?? 0
                points.append(ModelHourlyUsagePoint(hour: hour, model: model, count: count))
            }
        }
        return points
    }

    private static func activityByDay(_ usages: [SessionUsage]) -> [Date: Int] {
        let calendar = Calendar.current
        var counts: [Date: Int] = [:]
        for usage in usages {
            let day = calendar.startOfDay(for: usage.date)
            counts[day, default: 0] += 1
        }
        return counts
    }
}
