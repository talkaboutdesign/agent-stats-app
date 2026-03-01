import Charts
import SwiftUI

extension ContentView {
    func dashboardView(_ snapshot: CodexSnapshot) -> some View {
        let liveRows = model.liveSessions.filter(\.isActiveNow)
        let codexActive = liveRows.filter { $0.provider == "Codex" }.count
        let claudeActive = liveRows.filter { $0.provider == "Claude" }.count

        return VStack(spacing: 14) {
            let columns = [GridItem(.adaptive(minimum: 175, maximum: 320), spacing: 10)]
            LazyVGrid(columns: columns, spacing: 10) {
                MetricCard(title: "Threads", value: number(snapshot.totalThreads), icon: "bubble.left.and.bubble.right")
                MetricCard(title: "Session Files", value: number(snapshot.sessionFileCount), icon: "doc.on.doc")
                MetricCard(title: "Sessions", value: number(snapshot.sessionUsages.count), icon: "clock")
                MetricCard(title: "Est. Cost", value: (model.costSummary?.allTime ?? 0).currency, icon: "dollarsign")
            }

            let chartColumns = [GridItem(.adaptive(minimum: 300), spacing: 10)]
            LazyVGrid(columns: chartColumns, spacing: 10) {
                VStack(alignment: .leading, spacing: 10) {
                    cardTitle("Activity", subtitle: "30d", icon: "chart.bar.fill")
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
                    .frame(height: 118)
                }
                .panelCard()

                VStack(alignment: .leading, spacing: 10) {
                    cardTitle("When You Work", subtitle: "", icon: "clock.fill")
                    Chart(hourlyWorkDistribution(snapshot)) { point in
                        BarMark(
                            x: .value("Hour", point.date, unit: .hour),
                            y: .value("Count", point.cost)
                        )
                        .foregroundStyle(UITheme.accentA.gradient)
                        .cornerRadius(3)
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .frame(height: 118)
                }
                .panelCard()
            }

            let listColumns = [GridItem(.adaptive(minimum: 240), spacing: 10)]
            LazyVGrid(columns: listColumns, spacing: 10) {
                CountListCard(title: "Cost by Model", rows: modelRowsAsCounts(), rowLimit: 5)
                CountListCard(title: "Top Models", rows: snapshot.modelCounts, rowLimit: 5)
                CountListCard(title: "Top Tools", rows: snapshot.toolCounts, rowLimit: 5)
            }

            if !liveRows.isEmpty {
                let liveMetricColumns = [GridItem(.adaptive(minimum: 185, maximum: 320), spacing: 10)]
                LazyVGrid(columns: liveMetricColumns, spacing: 10) {
                    MetricCard(title: "Live Now", value: number(liveRows.count), icon: "waveform.path.ecg")
                    if codexActive > 0 {
                        MetricCard(title: "Codex Active", value: number(codexActive), icon: "bolt.horizontal.circle")
                    }
                    if claudeActive > 0 {
                        MetricCard(title: "Claude Active", value: number(claudeActive), icon: "sparkles")
                    }
                }

                SessionPricingList(
                    title: "Live Sessions",
                    subtitle: "Recent activity with estimated cost",
                    rows: liveRows,
                    maxRows: max(1, liveRows.count)
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

        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? .distantPast
        let recentRows = model.liveSessions.filter { $0.lastUpdated >= cutoff }

        return AnyView(
            VStack(spacing: 14) {
                let columns = [GridItem(.adaptive(minimum: 185, maximum: 320), spacing: 10)]
                LazyVGrid(columns: columns, spacing: 10) {
                    MetricCard(title: "Today", value: costSummary.today.currency, icon: "dollarsign.circle")
                    MetricCard(title: "This Week", value: costSummary.thisWeek.currency, icon: "calendar")
                    MetricCard(title: "This Month", value: costSummary.thisMonth.currency, icon: "calendar.badge.clock")
                    MetricCard(title: "All Time", value: costSummary.allTime.currency, icon: "chart.line.uptrend.xyaxis")
                }

                let chartColumns = [GridItem(.adaptive(minimum: 300), spacing: 10)]
                LazyVGrid(columns: chartColumns, spacing: 10) {
                    VStack(alignment: .leading, spacing: 10) {
                        cardTitle("Cost by Model", subtitle: "Top 10", icon: "dollarsign")
                        Chart(Array(costSummary.modelRows.prefix(10))) { row in
                            BarMark(
                                x: .value("Cost", row.cost),
                                y: .value("Model", row.model)
                            )
                            .foregroundStyle(UITheme.accentC.gradient)
                            .cornerRadius(4)
                        }
                        .frame(height: 190)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .panelCard()

                    VStack(alignment: .leading, spacing: 10) {
                        cardTitle("Daily Cost", subtitle: "All days", icon: "chart.bar.fill")
                        Chart(costSummary.daily) { point in
                            AreaMark(
                                x: .value("Day", point.date, unit: .day),
                                y: .value("Cost", point.cost)
                            )
                            .foregroundStyle(UITheme.accentB.opacity(0.25))

                            LineMark(
                                x: .value("Day", point.date, unit: .day),
                                y: .value("Cost", point.cost)
                            )
                            .lineStyle(.init(lineWidth: 2.0))
                            .foregroundStyle(UITheme.accentB)
                        }
                        .chartXAxis(.hidden)
                        .chartYAxis(.hidden)
                        .frame(height: 190)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .panelCard()
                }

                SessionPricingList(
                    title: "Session History (Last 30 Days)",
                    subtitle: "Codex + Claude sessions with per-session estimate",
                    rows: recentRows,
                    maxRows: max(1, recentRows.count)
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

        return VStack(spacing: 14) {
            let columns = [GridItem(.adaptive(minimum: 185, maximum: 320), spacing: 10)]
            LazyVGrid(columns: columns, spacing: 10) {
                MetricCard(title: "Total Threads", value: number(snapshot.totalThreads), icon: "text.bubble")
                MetricCard(title: "Active Threads", value: number(snapshot.activeThreads), icon: "bolt")
                MetricCard(title: "Archived Threads", value: number(snapshot.archivedThreads), icon: "archivebox")
                MetricCard(title: "Session Tokens", value: number(sessionTokenTotal), icon: "number")
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    func number(_ value: Int) -> String {
        NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
    }

    func number(_ value: Int64) -> String {
        NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
    }

    private func modelRowsAsCounts() -> [CountStat] {
        guard let rows = model.costSummary?.modelRows else {
            return []
        }
        return rows.map { CountStat(key: $0.model, count: Int($0.cost.rounded())) }
    }

    private func overviewDailyActivity() -> [CostPoint] {
        guard let daily = model.costSummary?.daily else {
            return []
        }
        return Array(daily.suffix(30))
    }

    private func hourlyWorkDistribution(_ snapshot: CodexSnapshot) -> [CostPoint] {
        var buckets = Array(repeating: 0.0, count: 24)
        let calendar = Calendar.current

        for usage in snapshot.sessionUsages {
            let hour = calendar.component(.hour, from: usage.date)
            guard hour >= 0, hour < 24 else { continue }
            buckets[hour] += 1
        }

        let startOfToday = calendar.startOfDay(for: Date())
        return buckets.enumerated().map { index, count in
            let date = calendar.date(byAdding: .hour, value: index, to: startOfToday) ?? startOfToday
            return CostPoint(date: date, cost: count)
        }
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

    @ViewBuilder
    private func cardTitle(_ title: String, subtitle: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(UITheme.accentB)
            Text(title)
                .font(.headline)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(UITheme.textMuted)
            }
            Spacer()
        }
    }
}
