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
        let dashboardVM = DashboardViewModel(snapshot: snapshot, liveSessions: model.liveSessions)
        let twoCol = responsiveContentWidth >= 740
        let workColorScale = modelColorScale(for: dashboardVM.topModels)

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
                        dashboardDailyActivityCard(points: dashboardVM.dailyModelPoints, colors: workColorScale)
                        ModelHourlyStackedCard(
                            title: "Peak Hours",
                            subtitle: "By model",
                            points: dashboardVM.hourlyModelPoints,
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
                            subtitle: dashboardVM.liveCount > 0 ? "\(dashboardVM.liveCount) live" : "",
                            rows: dashboardVM.recentSessions,
                            maxRows: 5
                        )
                        .gridCellColumns(2)
                    }
                }
            } else {
                VStack(spacing: 10) {
                    dashboardDailyActivityCard(points: dashboardVM.dailyModelPoints, colors: workColorScale)
                    ModelHourlyStackedCard(
                        title: "Peak Hours",
                        subtitle: "By model",
                        points: dashboardVM.hourlyModelPoints,
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
                        subtitle: dashboardVM.liveCount > 0 ? "\(dashboardVM.liveCount) live" : "",
                        rows: dashboardVM.recentSessions,
                        maxRows: 5
                    )
                }
            }

            ActivityHeatmapCard(
                title: "Activity Heatmap",
                countsByDay: dashboardVM.activityHeatmap
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
        let pricingVM = PricingViewModel(
            liveSessions: model.liveSessions,
            cutoff: sessionHistoryRange.cutoff()
        )
        let pairedChartCardMinHeight: CGFloat = BentoCardHeight.large
        let trendColors = modelColorScale(for: pricingVM.trendModels)

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
                    MetricCard(title: "Sessions", value: number(pricingVM.recentRows.count), icon: "clock")
                        .frame(minHeight: BentoCardHeight.small)
                    MetricCard(title: "Est. Cost", value: pricingVM.rangeCost.currency, icon: "dollarsign.circle")
                        .frame(minHeight: BentoCardHeight.small)
                    MetricCard(title: "Tokens", value: number(pricingVM.rangeTokens), icon: "number")
                        .frame(minHeight: BentoCardHeight.small)
                    MetricCard(title: "Live Now", value: number(pricingVM.liveNow), icon: "waveform.path.ecg")
                        .frame(minHeight: BentoCardHeight.small)
                }

                let chartColumns = chartColumns(for: width)
                LazyVGrid(columns: chartColumns, spacing: 10) {
                    CostByModelCard(
                        title: "Cost by Model",
                        rows: pricingVM.rangeModelRows,
                        rowLimit: 10,
                        minHeight: pairedChartCardMinHeight
                    )

                    ModelMultiLineChartCard(
                        title: "Model Cost Trend",
                        subtitle: sessionHistoryRange.rawValue,
                        points: pricingVM.modelCostTrends,
                        colors: trendColors,
                        minHeight: pairedChartCardMinHeight
                    )
                }

                ModelMultiLineChartCard(
                    title: "Model Usage Trend",
                    subtitle: sessionHistoryRange.rawValue,
                    points: pricingVM.modelUsageTrends,
                    colors: trendColors,
                    minHeight: BentoCardHeight.medium
                )

                SessionPricingList(
                    title: "Session History (\(sessionHistoryRange.title))",
                    subtitle: "Codex + Claude daily rollup (sessions, tokens, and estimated cost)",
                    rows: pricingVM.recentRows,
                    maxRows: pricingVM.recentRows.count
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
        let threadsVM = ThreadsViewModel(snapshot: snapshot)
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
                MetricCard(title: "Session Tokens", value: number(threadsVM.sessionTokenTotal), icon: "number")
                    .frame(minHeight: BentoCardHeight.small)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Recent Threads")
                    .font(.headline)

                Group {
                    if threadsVM.displayedThreads.isEmpty {
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

                                ForEach(Array(threadsVM.displayedThreads.enumerated()), id: \.element.id) { index, thread in
                                    let resolvedModel = threadsVM.resolvedModel(for: thread)
                                    let threadTokens = threadsVM.threadTokens(for: thread)
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

                                    if index < threadsVM.displayedThreads.count - 1 {
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

                                ForEach(Array(threadsVM.displayedThreads.enumerated()), id: \.element.id) { index, thread in
                                    let resolvedModel = threadsVM.resolvedModel(for: thread)
                                    let threadTokens = threadsVM.threadTokens(for: thread)

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

                                    if index < threadsVM.displayedThreads.count - 1 {
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

    private func modelColorScale(for models: [String]) -> [String: Color] {
        var scale: [String: Color] = [:]
        for model in models {
            scale[model] = UITheme.modelColor(for: model)
        }
        return scale
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
