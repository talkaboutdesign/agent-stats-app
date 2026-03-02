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
        let recentSessions = Array(model.liveSessions.prefix(5))
        let liveCount = model.liveSessions.filter(\.isActiveNow).count
        let twoCol = responsiveContentWidth >= 740
        let workModels = topModelNames(from: snapshot.sessionUsages, limit: 5)
        let workColorScale = modelColorScale(for: workModels)
        let hourlyModelPoints = hourlyModelUsage(snapshot, models: workModels)
        let dailyModelPoints = dailyModelActivity(snapshot, models: workModels)
        let activityHeatmap = activityByDay(snapshot.sessionUsages)

        return VStack(spacing: 10) {
            LazyVGrid(columns: flexibleColumns(twoCol ? 4 : 2), spacing: 10) {
                MetricCard(title: "Threads", value: number(snapshot.totalThreads), icon: "bubble.left.and.bubble.right")
                MetricCard(title: "Session Files", value: number(snapshot.sessionFileCount), icon: "doc.on.doc")
                MetricCard(title: "Sessions", value: number(snapshot.sessionUsages.count), icon: "clock")
                MetricCard(title: "Est. Cost", value: (model.costSummary?.allTime ?? 0).currency, icon: "dollarsign")
            }

            if twoCol {
                Grid(alignment: .topLeading, horizontalSpacing: 10, verticalSpacing: 10) {
                    GridRow {
                        dashboardDailyActivityCard(points: dailyModelPoints, colors: workColorScale)
                        ModelHourlyStackedCard(
                            title: "Peak Hours",
                            subtitle: "By model",
                            points: hourlyModelPoints,
                            colors: workColorScale
                        )
                    }
                    GridRow {
                        CostByModelCard(
                            title: "Cost by Model",
                            rows: model.costSummary?.modelRows ?? [],
                            rowLimit: 5
                        )
                        CountListCard(
                            title: "Top Models",
                            rows: snapshot.modelCounts,
                            rowLimit: 5,
                            keyFormatter: { $0.modelDisplayName },
                            icon: "cpu"
                        )
                    }
                    GridRow {
                        LiveSessionCardGrid(
                            title: "Recent Sessions",
                            subtitle: liveCount > 0 ? "\(liveCount) live" : "",
                            rows: recentSessions,
                            maxRows: 5
                        )
                        .gridCellColumns(2)
                    }
                }
            } else {
                VStack(spacing: 10) {
                    dashboardDailyActivityCard(points: dailyModelPoints, colors: workColorScale)
                    ModelHourlyStackedCard(
                        title: "Peak Hours",
                        subtitle: "By model",
                        points: hourlyModelPoints,
                        colors: workColorScale
                    )
                    CostByModelCard(
                        title: "Cost by Model",
                        rows: model.costSummary?.modelRows ?? [],
                        rowLimit: 5
                    )
                    CountListCard(
                        title: "Top Models",
                        rows: snapshot.modelCounts,
                        rowLimit: 5,
                        keyFormatter: { $0.modelDisplayName },
                        icon: "cpu"
                    )
                    LiveSessionCardGrid(
                        title: "Recent Sessions",
                        subtitle: liveCount > 0 ? "\(liveCount) live" : "",
                        rows: recentSessions,
                        maxRows: 5
                    )
                }
            }

            ActivityHeatmapCard(
                title: "Activity Heatmap",
                countsByDay: activityHeatmap
            )
        }
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func dashboardDailyActivityCard(points: [ModelSeriesPoint], colors: [String: Color]) -> some View {
        let seriesOrder = points.reduce(into: [String]()) { order, p in
            if !order.contains(p.model) { order.append(p.model) }
        }
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(title: "Activity", icon: "chart.bar.fill", subtitle: "30d")
            Chart {
                ForEach(points) { point in
                    BarMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value("Sessions", point.value),
                        width: .fixed(6)
                    )
                    .foregroundStyle(by: .value("Model", point.model))
                    .cornerRadius(2)
                }
            }
            .chartForegroundStyleScale(
                domain: seriesOrder,
                range: seriesOrder.map { colors[$0] ?? .gray }
            )
            .chartLegend(.hidden)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 170)
            Spacer(minLength: 0)
        }
        .padding(12)
        .panelCard(insetPadding: 0)
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
                    subtitle: "Codex + Claude daily rollup (sessions, tokens, and estimated cost)",
                    rows: recentRows,
                    maxRows: recentRows.count
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
        let modelByRolloutPath = modelByRolloutPath(snapshot.sessionUsages)
        let displayedThreads = filteredThreads(snapshot.threads)
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

                Group {
                    if displayedThreads.isEmpty {
                        Text("No threads available.")
                            .font(.callout)
                            .foregroundStyle(UITheme.textMuted)
                            .padding(.vertical, 10)
                    } else {
                        if width < 1020 {
                            VStack(spacing: 0) {
                                HStack(spacing: 8) {
                                    threadHeaderCell("Updated")
                                    threadHeaderCell("Model")
                                    threadHeaderCell("Thread Tokens", alignment: .trailing)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 8)

                                Divider().overlay(UITheme.border)

                                ForEach(Array(displayedThreads.enumerated()), id: \.element.id) { index, thread in
                                    let resolvedModel = thread.rolloutPath.flatMap { modelByRolloutPath[$0] }
                                        ?? thread.modelProvider.modelDisplayName
                                    let threadTokens = normalizedTokensByThread[thread.id] ?? Int64(thread.tokensUsed)
                                    let detail = [thread.source, thread.gitBranch]
                                        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                                        .joined(separator: " • ")

                                    HStack(alignment: .top, spacing: 8) {
                                        threadTextCell(thread.updatedAt?.friendly ?? "-")

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(resolvedModel)
                                                .font(.subheadline.weight(.semibold))
                                                .lineLimit(1)
                                                .truncationMode(.tail)
                                            if !detail.isEmpty {
                                                Text(detail)
                                                    .font(.caption)
                                                    .foregroundStyle(UITheme.textMuted)
                                                    .lineLimit(1)
                                                    .truncationMode(.tail)
                                            }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                        threadTextCell(number(threadTokens), alignment: .trailing)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 8)
                                    .background(index.isMultiple(of: 2) ? Color.clear : UITheme.surfaceAlt.opacity(0.28))

                                    if index < displayedThreads.count - 1 {
                                        Divider().overlay(UITheme.border.opacity(0.65))
                                    }
                                }
                            }
                        } else {
                            VStack(spacing: 0) {
                                HStack(spacing: 8) {
                                    threadHeaderCell("Updated")
                                    threadHeaderCell("Source")
                                    threadHeaderCell("Model")
                                    threadHeaderCell("Thread Tokens", alignment: .trailing)
                                    threadHeaderCell("Branch")
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 8)

                                Divider().overlay(UITheme.border)

                                ForEach(Array(displayedThreads.enumerated()), id: \.element.id) { index, thread in
                                    let resolvedModel = thread.rolloutPath.flatMap { modelByRolloutPath[$0] }
                                        ?? thread.modelProvider.modelDisplayName
                                    let threadTokens = normalizedTokensByThread[thread.id] ?? Int64(thread.tokensUsed)

                                    HStack(spacing: 8) {
                                        threadTextCell(thread.updatedAt?.friendly ?? "-")
                                        threadTextCell(thread.source)
                                        threadTextCell(resolvedModel)
                                        threadTextCell(number(threadTokens), alignment: .trailing)
                                        threadTextCell(thread.gitBranch)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 8)
                                    .background(index.isMultiple(of: 2) ? Color.clear : UITheme.surfaceAlt.opacity(0.28))

                                    if index < displayedThreads.count - 1 {
                                        Divider().overlay(UITheme.border.opacity(0.65))
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .panelCard()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
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

    private func modelByRolloutPath(_ usages: [SessionUsage]) -> [String: String] {
        var map: [String: (updatedAt: Date, model: String)] = [:]
        for usage in usages where usage.provider == "Codex" {
            guard usage.id.hasPrefix("codex:") else { continue }
            let path = String(usage.id.dropFirst("codex:".count))
            if let existing = map[path], existing.updatedAt >= usage.date {
                continue
            }
            map[path] = (usage.date, usage.model.modelDisplayName)
        }
        return map.mapValues(\.model)
    }

    private func filteredThreads(_ threads: [ThreadSummary]) -> [ThreadSummary] {
        threads.filter { thread in
            thread.updatedAt != nil
                || !thread.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !thread.modelProvider.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || thread.tokensUsed > 0
                || !thread.gitBranch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
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
            scale[model] = UITheme.modelColor(for: model)
        }
        return scale
    }

    private func dailyModelActivity(_ snapshot: CodexSnapshot, models: [String]) -> [ModelSeriesPoint] {
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

    private func activityByDay(_ usages: [SessionUsage]) -> [Date: Int] {
        let calendar = Calendar.current
        var counts: [Date: Int] = [:]
        for usage in usages {
            let day = calendar.startOfDay(for: usage.date)
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
        case ..<520:
            count = 2
        case ..<900:
            count = 3
        default:
            count = 4
        }
        return flexibleColumns(count)
    }

    private func chartColumns(for width: CGFloat) -> [GridItem] {
        // Stack only on narrower widths; keep side-by-side in normal desktop layouts.
        flexibleColumns(width < 820 ? 1 : 2)
    }

    private func flexibleColumns(_ count: Int, spacing: CGFloat = 10) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: spacing), count: max(1, count))
    }

    private func threadHeaderCell(_ text: String, alignment: Alignment = .leading) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(UITheme.textMuted)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: alignment)
    }

    private func threadTextCell(_ text: String, alignment: Alignment = .leading) -> some View {
        Text(text)
            .font(.subheadline.weight(.medium))
            .lineLimit(1)
            .truncationMode(.tail)
            .minimumScaleFactor(0.85)
            .frame(maxWidth: .infinity, alignment: alignment)
    }

}
