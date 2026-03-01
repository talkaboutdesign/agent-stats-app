import Charts
import SwiftData
import SwiftUI

private enum SidebarItem: String, CaseIterable, Identifiable {
    case overview = "Readout"
    case activity = "Live"
    case sessions = "Sessions"
    case costs = "Costs"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .overview: return "eyeglasses"
        case .activity: return "waveform.path.ecg"
        case .sessions: return "clock.fill"
        case .costs: return "dollarsign.circle"
        }
    }

}

private enum UITheme {
    static let page = Color(red: 0.08, green: 0.09, blue: 0.14)
    static let pageAlt = Color(red: 0.11, green: 0.13, blue: 0.20)
    static let sidebar = Color(red: 0.09, green: 0.10, blue: 0.15)
    static let surface = Color(red: 0.14, green: 0.15, blue: 0.21)
    static let surfaceAlt = Color(red: 0.11, green: 0.12, blue: 0.18)
    static let border = Color.white.opacity(0.08)
    static let textMuted = Color.white.opacity(0.65)
}

struct ContentView: View {
    @Bindable var model: AppModel
    @State private var selection: SidebarItem? = .overview

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.callout.weight(.semibold))
                }
                .help("Refresh")
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(model.isLoading)
            }

            ToolbarItem(placement: .automatic) {
                Text(model.pricingStatusLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .background(
            LinearGradient(
                colors: [UITheme.page, UITheme.pageAlt],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
        .frame(minWidth: 1180, minHeight: 780)
    }

    private var sidebar: some View {
        List(selection: $selection) {
            Section("Overview") {
                sidebarRow(.overview)
            }

            Section("Monitor") {
                sidebarRow(.activity)
                sidebarRow(.sessions)
                sidebarRow(.costs)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(UITheme.sidebar.opacity(0.9))
        .navigationTitle("Agent Stats")
    }

    @ViewBuilder
    private func sidebarRow(_ item: SidebarItem) -> some View {
        NavigationLink(value: item) {
            Label(item.rawValue, systemImage: item.systemImage)
                .font(.system(size: 15, weight: .semibold))
        }
    }

    private var detail: some View {
        VStack(spacing: 14) {
            headerBar
            statusBar

            if let errorText = model.errorText {
                Text(errorText)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(UITheme.surfaceAlt, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            detailContent
        }
        .transaction { transaction in
            transaction.animation = nil
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.clear)
    }

    private var headerBar: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                if (selection ?? .overview) == .overview {
                    Text("Night shift, \(firstName)")
                        .font(.title2.weight(.bold))
                    Text(overviewSubtitle)
                        .font(.headline)
                        .foregroundStyle(UITheme.textMuted)
                } else {
                    Text((selection ?? .overview).rawValue)
                        .font(.title3.weight(.semibold))
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            if model.isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            Text(model.statusText)
                .font(.callout)

            Spacer()

            if model.isLoading {
                Text("Refreshing")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(UITheme.textMuted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(UITheme.surface, in: Capsule())
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(UITheme.surfaceAlt)
                .stroke(UITheme.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var detailContent: some View {
        if let snapshot = model.snapshot {
            switch selection ?? .overview {
            case .overview:
                overviewView(snapshot)
            case .costs:
                costsView()
            case .sessions:
                sessionsView(snapshot)
            case .activity:
                activityView(snapshot)
            }
        } else if model.isLoading {
            LoadingStateView(
                showTableSkeleton: (selection ?? .overview) == .sessions
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            ContentUnavailableView(
                "No Data Loaded",
                systemImage: "tray",
                description: Text("Run Codex once so ~/.codex exists, then click Refresh.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func overviewView(_ snapshot: CodexSnapshot) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                let columns = [GridItem(.adaptive(minimum: 210), spacing: 12)]
                LazyVGrid(columns: columns, spacing: 12) {
                    MetricCard(title: "Threads", value: number(snapshot.totalThreads), icon: "bubble.left.and.bubble.right")
                    MetricCard(title: "Session Files", value: number(snapshot.sessionFileCount), icon: "doc.on.doc")
                    MetricCard(title: "Sessions", value: number(snapshot.sessionUsages.count), icon: "clock")
                    MetricCard(title: "Est. Cost", value: (model.costSummary?.allTime ?? 0).currency, icon: "dollarsign")
                }

                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 10) {
                        cardTitle("Activity", subtitle: "30d", icon: "chart.bar.fill")
                        Chart(overviewDailyActivity()) { point in
                            BarMark(
                                x: .value("Day", point.date, unit: .day),
                                y: .value("Count", point.cost)
                            )
                            .foregroundStyle(.blue.gradient)
                            .cornerRadius(3)
                        }
                        .chartXAxis(.hidden)
                        .chartYAxis(.hidden)
                        .frame(height: 110)
                    }
                    .panelCard()

                    VStack(alignment: .leading, spacing: 10) {
                        cardTitle("When You Work", subtitle: "", icon: "clock.fill")
                        Chart(hourlyWorkDistribution(snapshot)) { point in
                            BarMark(
                                x: .value("Hour", point.date, unit: .hour),
                                y: .value("Count", point.cost)
                            )
                            .foregroundStyle(.green.gradient)
                            .cornerRadius(3)
                        }
                        .chartXAxis(.hidden)
                        .chartYAxis(.hidden)
                        .frame(height: 110)
                    }
                    .panelCard()
                }

                HStack(alignment: .top, spacing: 12) {
                    CountListCard(title: "Cost by Model", rows: modelRowsAsCounts(), rowLimit: 5)
                    CountListCard(title: "Top Models", rows: snapshot.modelCounts, rowLimit: 5)
                    CountListCard(title: "Top Tools", rows: snapshot.toolCounts, rowLimit: 5)
                }
            }
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func costsView() -> some View {
        ScrollView {
            VStack(spacing: 16) {
                if let costSummary = model.costSummary {
                    let columns = [GridItem(.adaptive(minimum: 230), spacing: 12)]
                    LazyVGrid(columns: columns, spacing: 12) {
                        MetricCard(title: "Today", value: costSummary.today.currency, icon: "dollarsign.circle")
                        MetricCard(title: "This Week", value: costSummary.thisWeek.currency, icon: "calendar")
                        MetricCard(title: "This Month", value: costSummary.thisMonth.currency, icon: "calendar.badge.clock")
                        MetricCard(title: "All Time", value: costSummary.allTime.currency, icon: "chart.line.uptrend.xyaxis")
                    }

                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Cost by Model")
                                .font(.headline)

                            Chart(Array(costSummary.modelRows.prefix(10))) { row in
                                BarMark(
                                    x: .value("Cost", row.cost),
                                    y: .value("Model", row.model)
                                )
                                .foregroundStyle(.tint)
                                .cornerRadius(4)
                            }
                            .frame(height: 260)
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .panelCard()

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Model Totals")
                                .font(.headline)

                            ForEach(costSummary.modelRows.prefix(12)) { row in
                                HStack {
                                    Text(row.model)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(row.cost.currency)
                                        .foregroundStyle(.secondary)
                                }
                                .font(.callout)
                            }

                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, minHeight: 260, alignment: .topLeading)
                        .panelCard()
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Daily Cost")
                            .font(.headline)

                        Chart(costSummary.daily) { point in
                            BarMark(
                                x: .value("Day", point.date, unit: .day),
                                y: .value("Cost", point.cost)
                            )
                            .foregroundStyle(.blue.gradient)
                        }
                        .frame(height: 220)
                    }
                    .panelCard()

                    if !costSummary.unmatchedModels.isEmpty {
                        Text("No pricing snapshot match for: \(costSummary.unmatchedModels.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    ContentUnavailableView(
                        "Pricing Not Loaded",
                        systemImage: "dollarsign.slash",
                        description: Text("Could not decode bundled pricing data.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                }
            }
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func sessionsView(_ snapshot: CodexSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
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
                .width(min: 80, max: 240)

                TableColumn("Model") { thread in
                    Text(thread.modelProvider)
                }
                .width(min: 80, max: 180)

                TableColumn("Tokens") { thread in
                    Text(number(thread.tokensUsed))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 90, max: 120)

                TableColumn("Archived") { thread in
                    Image(systemName: thread.archived ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(thread.archived ? .secondary : .tertiary)
                }
                .width(70)

                TableColumn("Branch") { thread in
                    Text(thread.gitBranch)
                        .lineLimit(1)
                }
                .width(min: 90, max: 180)

                TableColumn("CWD") { thread in
                    Text(thread.cwd)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .panelCard()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func activityView(_ snapshot: CodexSnapshot) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    CountListCard(title: "Event Types", rows: snapshot.eventTypeCounts)
                    CountListCard(title: "Top Tools", rows: snapshot.toolCounts)
                    CountListCard(title: "Top Sources", rows: snapshot.sourceCounts)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Tool Calls")
                        .font(.headline)

                    Chart(Array(snapshot.toolCounts.prefix(12))) { row in
                        BarMark(
                            x: .value("Tool", row.key),
                            y: .value("Count", row.count)
                        )
                        .foregroundStyle(.mint)
                    }
                    .frame(height: 260)
                }
                .panelCard()
            }
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func number(_ value: Int) -> String {
        NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
    }

    private func number(_ value: Int64) -> String {
        NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
    }

    private var firstName: String {
        let parts = NSFullUserName().split(separator: " ")
        return parts.first.map(String.init) ?? "Operator"
    }

    private var overviewSubtitle: String {
        guard let snapshot = model.snapshot else {
            return "Loading your Codex activity..."
        }

        let sessions = number(snapshot.sessionUsages.count)
        let cost = (model.costSummary?.allTime ?? 0).currency
        return "\(sessions) sessions analyzed. Estimated spend: \(cost)."
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

    @ViewBuilder
    private func cardTitle(_ title: String, subtitle: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.blue)
            Text(title)
                .font(.headline)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(UITheme.textMuted)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

private struct LoadingStateView: View {
    let showTableSkeleton: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Indexing ~/.codex")
                        .font(.headline)
                    Text("Scanning SQLite + JSONL sessions. This can take a bit on large archives.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .panelCard()

            let columns = [GridItem(.adaptive(minimum: 210), spacing: 12)]
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(0..<12, id: \.self) { _ in
                    SkeletonMetricCard()
                }
            }

            HStack(alignment: .top, spacing: 12) {
                ForEach(0..<4, id: \.self) { _ in
                    SkeletonListCard()
                }
            }

            if showTableSkeleton {
                SkeletonTableCard()
            }
        }
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .panelCard(insetPadding: 0)
    }
}

private struct CountListCard: View {
    let title: String
    let rows: [CountStat]
    var rowLimit: Int = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            if rows.isEmpty {
                Text("No data")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(rows.prefix(rowLimit))) { row in
                    HStack {
                        Text(row.key)
                            .lineLimit(1)
                        Spacer()
                        Text(row.count, format: .number)
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(12)
        .panelCard(insetPadding: 0)
    }
}

private struct SkeletonMetricCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SkeletonBlock(width: 110, height: 10, cornerRadius: 4)
            SkeletonBlock(width: 150, height: 22, cornerRadius: 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .panelCard(insetPadding: 0)
    }
}

private struct SkeletonListCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SkeletonBlock(width: 120, height: 12, cornerRadius: 5)
            ForEach(0..<6, id: \.self) { _ in
                SkeletonBlock(width: nil, height: 12, cornerRadius: 4)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
        .padding(12)
        .panelCard(insetPadding: 0)
    }
}

private struct SkeletonTableCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SkeletonBlock(width: 160, height: 12, cornerRadius: 5)
            ForEach(0..<7, id: \.self) { _ in
                SkeletonBlock(width: nil, height: 16, cornerRadius: 4)
            }
        }
        .padding(12)
        .panelCard(insetPadding: 0)
    }
}

private struct SkeletonBlock: View {
    let width: CGFloat?
    let height: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        TimelineView(.animation) { context in
            let cycle = 1.25
            let progress = context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: cycle) / cycle
            let phase = CGFloat(progress * 2.4 - 1.2)

            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(.secondary.opacity(0.18))
                .overlay {
                    GeometryReader { proxy in
                        let w = proxy.size.width
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.35), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .rotationEffect(.degrees(18))
                        .offset(x: phase * max(w, 1))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                }
        }
        .frame(width: width, height: height)
    }
}

private extension View {
    func panelCard(insetPadding: CGFloat = 12) -> some View {
        self
            .padding(insetPadding)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(UITheme.surface)
                    .stroke(UITheme.border, lineWidth: 1)
            )
    }
}

#Preview {
    let container = try! ModelContainer(
        for: CachedSnapshotRecord.self,
        CachedSessionFileRecord.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = ModelContext(container)
    return ContentView(model: AppModel(modelContext: context))
}
