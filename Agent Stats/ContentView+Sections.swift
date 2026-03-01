import Charts
import SwiftUI

private enum BentoCardHeight {
    static let small: CGFloat = 96
    static let medium: CGFloat = 236
    static let large: CGFloat = 332
    static let xLarge: CGFloat = 420
    static let chartPair: CGFloat = medium
    static let heatmap: CGFloat = medium
}

extension ContentView {
    func dashboardView(_ snapshot: CodexSnapshot) -> some View {
        let liveRows = model.liveSessions.filter(\.isActiveNow)
        let codexActive = liveRows.filter { $0.provider == "Codex" }.count
        let claudeActive = liveRows.filter { $0.provider == "Claude" }.count
        let width = responsiveContentWidth
        let workModels = topModelNames(from: snapshot.sessionUsages, limit: 5)
        let workColorScale = modelColorScale(for: workModels)
        let hourlyModelPoints = hourlyModelUsage(snapshot, models: workModels)
        let activityHeatmap = activityByDay(snapshot.sessionUsages, days: 30)

        return VStack(spacing: 14) {
            let pairedChartCardHeight = BentoCardHeight.chartPair
            let columns = metricColumns(for: width)
            LazyVGrid(columns: columns, spacing: 10) {
                MetricCard(title: "Threads", value: number(snapshot.totalThreads), icon: "bubble.left.and.bubble.right")
                    .frame(minHeight: BentoCardHeight.small)
                MetricCard(title: "Session Files", value: number(snapshot.sessionFileCount), icon: "doc.on.doc")
                    .frame(minHeight: BentoCardHeight.small)
                MetricCard(title: "Sessions", value: number(snapshot.sessionUsages.count), icon: "clock")
                    .frame(minHeight: BentoCardHeight.small)
                MetricCard(title: "Est. Cost", value: (model.costSummary?.allTime ?? 0).currency, icon: "dollarsign")
                    .frame(minHeight: BentoCardHeight.small)
            }

            let chartColumns = chartColumns(for: width)
            LazyVGrid(columns: chartColumns, spacing: 10) {
                VStack(alignment: .leading, spacing: 10) {
                    CardHeader(title: "Activity", icon: "chart.bar.fill", subtitle: "30d")
                    Chart(overviewDailyActivity()) { point in
                        BarMark(
                            x: .value("Day", point.date, unit: .day),
                            y: .value("Count", point.cost)
                        )
                        .foregroundStyle(UITheme.accentB.gradient)
                        .cornerRadius(3)
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .frame(height: 170)
                    Spacer(minLength: 0)
                }
                .padding(12)
                .panelCard(insetPadding: 0)
                .frame(maxWidth: .infinity, minHeight: pairedChartCardHeight, maxHeight: pairedChartCardHeight)

                ModelHourlyStackedCard(
                    title: "When You Work",
                    subtitle: "By model",
                    points: hourlyModelPoints,
                    colors: workColorScale,
                    minHeight: pairedChartCardHeight
                )
                .frame(maxWidth: .infinity, minHeight: pairedChartCardHeight, maxHeight: pairedChartCardHeight)
            }

            ActivityHeatmapCard(
                title: "Activity Heatmap",
                subtitle: "Last 30 days",
                countsByDay: activityHeatmap,
                days: 30,
                minHeight: heatmapCardHeight(for: width)
            )

            let listColumns = listColumns(for: width)
            LazyVGrid(columns: listColumns, spacing: 10) {
                CostByModelCard(
                    title: "Cost by Model",
                    rows: model.costSummary?.modelRows ?? [],
                    rowLimit: 5,
                    minHeight: BentoCardHeight.medium
                )
                CountListCard(
                    title: "Top Models",
                    rows: snapshot.modelCounts,
                    rowLimit: 5,
                    keyFormatter: { $0.modelDisplayName },
                    icon: "cpu",
                    minHeight: BentoCardHeight.medium
                )
                CountListCard(
                    title: "Top Tools",
                    rows: snapshot.toolCounts,
                    rowLimit: 5,
                    icon: "wrench.and.screwdriver",
                    minHeight: BentoCardHeight.medium
                )
            }

            if !liveRows.isEmpty {
                let liveMetricColumns = liveMetricColumns(for: width)
                LazyVGrid(columns: liveMetricColumns, spacing: 10) {
                    MetricCard(title: "Live Now", value: number(liveRows.count), icon: "waveform.path.ecg")
                        .frame(minHeight: BentoCardHeight.small)
                    if codexActive > 0 {
                        MetricCard(title: "Codex Active", value: number(codexActive), icon: "bolt.horizontal.circle")
                            .frame(minHeight: BentoCardHeight.small)
                    }
                    if claudeActive > 0 {
                        MetricCard(title: "Claude Active", value: number(claudeActive), icon: "sparkles")
                            .frame(minHeight: BentoCardHeight.small)
                    }
                }

                LiveSessionCardGrid(
                    title: "Live Sessions",
                    subtitle: "Recent activity",
                    rows: liveRows,
                    maxRows: max(1, liveRows.count),
                    minHeight: BentoCardHeight.large
                )
            }
        }
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    func pricingView() -> some View {
        guard let costSummary = model.costSummary else {
            return AnyView(
                ContentUnavailableView(
                    "Costs Not Loaded",
                    systemImage: "dollarsign.slash",
                    description: Text("Could not decode bundled cost data.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            )
        }

        let width = responsiveContentWidth
        let cutoff = sessionHistoryRange.cutoff()
        let recentRows = model.liveSessions.filter { $0.lastUpdated >= cutoff }
        let rangeModelRows = modelRows(from: recentRows)
        let rangeCost = recentRows.reduce(0.0) { $0 + $1.estimatedCost }
        let rangeTokens = recentRows.reduce(Int64(0)) { $0 + $1.totalTokens }
        let liveNow = recentRows.filter(\.isActiveNow).count
        let pairedChartCardMinHeight: CGFloat = BentoCardHeight.large
        let trendModels = Array(rangeModelRows.prefix(5).map(\.model))
        let trendColors = modelColorScale(for: trendModels)
        let modelCostTrends = modelCostTrendPoints(from: recentRows, models: trendModels, cutoff: cutoff)
        let modelUsageTrends = modelUsageTrendPoints(from: recentRows, models: trendModels, cutoff: cutoff)

        return AnyView(
            VStack(spacing: 14) {
                Picker("Session History", selection: $sessionHistoryRange) {
                    ForEach(SessionHistoryRange.allCases) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 260, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)

                let columns = metricColumns(for: width)
                LazyVGrid(columns: columns, spacing: 10) {
                    MetricCard(title: "Sessions", value: number(recentRows.count), icon: "clock")
                        .frame(minHeight: BentoCardHeight.small)
                    MetricCard(title: "Est. Cost", value: rangeCost.currency, icon: "dollarsign.circle")
                        .frame(minHeight: BentoCardHeight.small)
                    MetricCard(title: "Tokens", value: number(rangeTokens), icon: "number")
                        .frame(minHeight: BentoCardHeight.small)
                    MetricCard(title: "Live Now", value: number(liveNow), icon: "waveform.path.ecg")
                        .frame(minHeight: BentoCardHeight.small)
                }

                let chartColumns = chartColumns(for: width)
                LazyVGrid(columns: chartColumns, spacing: 10) {
                    CostByModelCard(
                        title: "Cost by Model",
                        rows: rangeModelRows,
                        rowLimit: 10,
                        minHeight: pairedChartCardMinHeight
                    )

                    ModelMultiLineChartCard(
                        title: "Model Cost Trend",
                        subtitle: sessionHistoryRange.rawValue,
                        points: modelCostTrends,
                        colors: trendColors,
                        minHeight: pairedChartCardMinHeight
                    )
                }

                ModelMultiLineChartCard(
                    title: "Model Usage Trend",
                    subtitle: sessionHistoryRange.rawValue,
                    points: modelUsageTrends,
                    colors: trendColors,
                    minHeight: BentoCardHeight.medium
                )

                SessionPricingList(
                    title: "Session History (\(sessionHistoryRange.title))",
                    subtitle: "Codex + Claude sessions with per-session estimate",
                    rows: recentRows,
                    maxRows: recentRows.count,
                    minHeight: BentoCardHeight.xLarge
                )

                if !costSummary.unmatchedModels.isEmpty {
                    Text("No cost snapshot match for: \(costSummary.unmatchedModels.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        )
    }

    func threadsView(_ snapshot: CodexSnapshot) -> some View {
        let normalizedTokensByThread = normalizedTokensByThreadID(snapshot.sessionUsages)
        let sessionTokenTotal = snapshot.sessionUsages.reduce(Int64(0)) { $0 + displayTokens(for: $1) }
        let width = responsiveContentWidth

        return VStack(spacing: 14) {
            let columns = metricColumns(for: width)
            LazyVGrid(columns: columns, spacing: 10) {
                MetricCard(title: "Total Threads", value: number(snapshot.totalThreads), icon: "text.bubble")
                    .frame(minHeight: BentoCardHeight.small)
                MetricCard(title: "Active Threads", value: number(snapshot.activeThreads), icon: "bolt")
                    .frame(minHeight: BentoCardHeight.small)
                MetricCard(title: "Archived Threads", value: number(snapshot.archivedThreads), icon: "archivebox")
                    .frame(minHeight: BentoCardHeight.small)
                MetricCard(title: "Session Tokens", value: number(sessionTokenTotal), icon: "number")
                    .frame(minHeight: BentoCardHeight.small)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Recent Threads")
                    .font(.headline)

                Table(snapshot.threads) {
                    TableColumn("Updated") { thread in
                        Text(thread.updatedAt?.friendly ?? "-")
                    }
                    .width(min: 150, max: 190)

                    TableColumn("Source") { thread in
                        Text(thread.source)
                            .lineLimit(1)
                    }
                    .width(min: 100, max: 230)

                    TableColumn("Model") { thread in
                        Text(thread.modelProvider)
                            .lineLimit(1)
                    }
                    .width(min: 120, max: 220)

                    TableColumn("Thread Tokens") { thread in
                        Text(number(normalizedTokensByThread[thread.id] ?? Int64(thread.tokensUsed)))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .monospacedDigit()
                    }
                    .width(min: 90, max: 120)

                    TableColumn("Branch") { thread in
                        Text(thread.gitBranch)
                            .lineLimit(1)
                    }
                    .width(min: 90, max: 170)

                    TableColumn("CWD") { thread in
                        Text(thread.cwd)
                            .lineLimit(1)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .panelCard()
            .frame(minHeight: BentoCardHeight.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    func number(_ value: Int) -> String {
        NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
    }

    func number(_ value: Int64) -> String {
        NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
    }

    private func overviewDailyActivity() -> [CostPoint] {
        guard let daily = model.costSummary?.daily else {
            return []
        }
        return Array(daily.suffix(30))
    }

    private func displayTokens(for usage: SessionUsage) -> Int64 {
        let uncachedInput = usage.provider == "Codex"
            ? max(usage.inputTokens - usage.cachedInputTokens, 0)
            : usage.inputTokens
        return max(uncachedInput + usage.outputTokens, 0)
    }

    private func normalizedTokensByThreadID(_ usages: [SessionUsage]) -> [String: Int64] {
        var map: [String: Int64] = [:]
        for usage in usages where usage.provider == "Codex" {
            guard let threadID = codexThreadID(from: usage.id) else { continue }
            map[threadID] = max(map[threadID] ?? 0, displayTokens(for: usage))
        }
        return map
    }

    private func codexThreadID(from usageID: String) -> String? {
        guard usageID.hasPrefix("codex:") else { return nil }
        let path = String(usageID.dropFirst("codex:".count))
        let basename = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent.lowercased()
        let pattern = #"[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(basename.startIndex..., in: basename)
        guard let match = regex.firstMatch(in: basename, range: range),
              let swiftRange = Range(match.range, in: basename) else {
            return nil
        }
        return String(basename[swiftRange])
    }

    private func modelRows(from sessions: [LiveSessionRow]) -> [ModelCostRow] {
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

    private func topModelNames(from usages: [SessionUsage], limit: Int) -> [String] {
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

    private func modelColorScale(for models: [String]) -> [String: Color] {
        var scale: [String: Color] = [:]
        for model in models {
            scale[model] = colorForModel(model)
        }
        return scale
    }

    private func colorForModel(_ model: String) -> Color {
        let palette: [Color] = [
            UITheme.accentC,
            UITheme.accentB,
            UITheme.accentA,
            Color(red: 0.43, green: 0.77, blue: 0.50),
            Color(red: 0.95, green: 0.62, blue: 0.32),
            Color(red: 0.82, green: 0.56, blue: 0.95),
            Color(red: 0.95, green: 0.45, blue: 0.58),
            Color(red: 0.53, green: 0.82, blue: 0.90),
        ]
        let seed = model.unicodeScalars.reduce(0) { (($0 * 33) + Int($1.value)) % 10_007 }
        return palette[seed % palette.count]
    }

    private func hourlyModelUsage(_ snapshot: CodexSnapshot, models: [String]) -> [ModelHourlyUsagePoint] {
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

    private func activityByDay(_ usages: [SessionUsage], days: Int) -> [Date: Int] {
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -(max(days, 1) - 1), to: end) ?? end
        var counts: [Date: Int] = [:]

        for usage in usages {
            let day = calendar.startOfDay(for: usage.date)
            guard day >= start, day <= end else { continue }
            counts[day, default: 0] += 1
        }

        return counts
    }

    private func dayBuckets(from cutoff: Date, to endDate: Date = Date()) -> [Date] {
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

    private func modelCostTrendPoints(
        from sessions: [LiveSessionRow],
        models: [String],
        cutoff: Date
    ) -> [ModelSeriesPoint] {
        trendPoints(
            from: sessions,
            models: models,
            cutoff: cutoff
        ) { row in row.estimatedCost }
    }

    private func modelUsageTrendPoints(
        from sessions: [LiveSessionRow],
        models: [String],
        cutoff: Date
    ) -> [ModelSeriesPoint] {
        trendPoints(
            from: sessions,
            models: models,
            cutoff: cutoff
        ) { _ in 1 }
    }

    private func trendPoints(
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

    private var responsiveContentWidth: CGFloat {
        detailAvailableWidth > 0 ? detailAvailableWidth : 1024
    }

    private func metricColumns(for width: CGFloat) -> [GridItem] {
        let count: Int
        switch width {
        case ..<760:
            count = 1
        case ..<1100:
            count = 2
        case ..<1420:
            count = 3
        default:
            count = 4
        }
        return flexibleColumns(count)
    }

    private func chartColumns(for width: CGFloat) -> [GridItem] {
        flexibleColumns(width < 1020 ? 1 : 2)
    }

    private func listColumns(for width: CGFloat) -> [GridItem] {
        let count: Int
        switch width {
        case ..<860:
            count = 1
        case ..<1340:
            count = 2
        default:
            count = 3
        }
        return flexibleColumns(count)
    }

    private func liveMetricColumns(for width: CGFloat) -> [GridItem] {
        let count: Int
        switch width {
        case ..<860:
            count = 1
        case ..<1220:
            count = 2
        default:
            count = 3
        }
        return flexibleColumns(count)
    }

    private func flexibleColumns(_ count: Int, spacing: CGFloat = 10) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: spacing), count: max(1, count))
    }

    private func heatmapCardHeight(for width: CGFloat) -> CGFloat {
        BentoCardHeight.heatmap
    }

}
