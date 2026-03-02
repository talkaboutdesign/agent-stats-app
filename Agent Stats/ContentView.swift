import SwiftData
import SwiftUI

private enum SidebarItem: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case pricing = "Costs"
    case threads = "Threads"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .dashboard: return "square.grid.2x2.fill"
        case .pricing: return "dollarsign.circle"
        case .threads: return "text.bubble.fill"
        }
    }
}

enum SessionHistoryRange: String, CaseIterable, Identifiable {
    case last24Hours = "24h"
    case last7Days = "7d"
    case last30Days = "30d"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .last24Hours:
            return "Last 24 Hours"
        case .last7Days:
            return "Last 7 Days"
        case .last30Days:
            return "Last 30 Days"
        }
    }

    func cutoff(from now: Date = Date()) -> Date {
        let calendar = Calendar.current
        switch self {
        case .last24Hours:
            return calendar.date(byAdding: .hour, value: -24, to: now) ?? .distantPast
        case .last7Days:
            return calendar.date(byAdding: .day, value: -7, to: now) ?? .distantPast
        case .last30Days:
            return calendar.date(byAdding: .day, value: -30, to: now) ?? .distantPast
        }
    }
}

private struct DetailWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

enum UITheme {
    static let page = Color(red: 0.02, green: 0.03, blue: 0.06)
    static let pageAlt = Color(red: 0.05, green: 0.08, blue: 0.14)
    static let sidebar = Color(red: 0.04, green: 0.06, blue: 0.10)
    static let shell = Color(red: 0.06, green: 0.08, blue: 0.13)
    static let surface = Color(red: 0.09, green: 0.11, blue: 0.17)
    static let surfaceAlt = Color(red: 0.07, green: 0.09, blue: 0.14)
    static let border = Color.white.opacity(0.10)
    static let textMuted = Color.white.opacity(0.65)

    static let accentA = Color(red: 0.25, green: 0.91, blue: 0.78)
    static let accentB = Color(red: 0.35, green: 0.52, blue: 1.00)
    static let accentC = Color(red: 0.98, green: 0.74, blue: 0.26)
    static let danger = Color(red: 0.98, green: 0.41, blue: 0.50)

    // Canonical model colors — keyword-matched, consistent across all charts
    static func modelColor(for name: String) -> Color {
        let lower = name.lowercased()

        // Opus versions
        if lower.contains("opus") && lower.contains("4.6") {
            return Color(red: 0.35, green: 0.52, blue: 1.00)   // bright blue
        }
        if lower.contains("opus") && lower.contains("4.5") {
            return Color(red: 0.68, green: 0.42, blue: 0.98)   // purple
        }
        if lower.contains("opus") {
            return Color(red: 0.68, green: 0.42, blue: 0.98)
        }

        // Sonnet versions
        if lower.contains("sonnet") && lower.contains("4.5") {
            return Color(red: 0.98, green: 0.45, blue: 0.58)   // coral pink
        }
        if lower.contains("sonnet") {
            return Color(red: 0.98, green: 0.45, blue: 0.58)
        }

        // Haiku
        if lower.contains("haiku") {
            return Color(red: 0.82, green: 0.56, blue: 0.95)   // lavender
        }

        // Codex
        if lower.contains("codex") {
            return Color(red: 0.25, green: 0.91, blue: 0.78)   // teal
        }

        // Fallback palette for unknown models
        let fallback: [Color] = [
            Color(red: 0.98, green: 0.74, blue: 0.26),  // amber
            Color(red: 0.43, green: 0.77, blue: 0.50),  // green
            Color(red: 0.53, green: 0.82, blue: 0.90),  // sky
            Color(red: 0.95, green: 0.62, blue: 0.32),  // orange
        ]
        let hash = lower.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) }
        return fallback[abs(hash) % fallback.count]
    }
}

struct ContentView: View {
    @Bindable var model: AppModel

    @State private var selection: SidebarItem? = .dashboard
    @State var sessionHistoryRange: SessionHistoryRange = .last24Hours
    @State var detailAvailableWidth: CGFloat = 0

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.prominentDetail)
        .background(TechBackdrop().ignoresSafeArea())
        .frame(minWidth: 680, minHeight: 520)
    }

    private var sidebar: some View {
        List(selection: $selection) {
            Section("Overview") {
                sidebarRow(.dashboard)
            }

            Section("Monitor") {
                sidebarRow(.pricing)
                sidebarRow(.threads)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(UITheme.sidebar.opacity(0.90))
        .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 220)
    }

    @ViewBuilder
    private func sidebarRow(_ item: SidebarItem) -> some View {
        NavigationLink(value: item) {
            Label(item.rawValue, systemImage: item.systemImage)
                .font(.system(size: 15, weight: .semibold))
        }
    }

    private var detail: some View {
        Group {
            if usesPageScroll {
                ScrollView {
                    detailBody
                }
            } else {
                detailBody
            }
        }
        .onPreferenceChange(DetailWidthPreferenceKey.self) { newWidth in
            detailAvailableWidth = newWidth
        }
        .background(Color.clear)
    }

    private var detailBody: some View {
        VStack(spacing: 12) {
            headerBar

            if let errorText = model.errorText {
                Text(errorText)
                    .font(.callout)
                    .foregroundStyle(UITheme.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(UITheme.surfaceAlt)
                            .stroke(UITheme.danger.opacity(0.35), lineWidth: 1)
                    )
            }

            detailContent
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(8)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: DetailWidthPreferenceKey.self, value: proxy.size.width)
            }
        )
    }

    private var usesPageScroll: Bool {
        switch selection ?? .dashboard {
        case .dashboard, .pricing, .threads:
            return true
        }
    }

    private var headerBar: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(headerTitle)
                    .font(.title3.weight(.bold))

                Text(headerSubtitle)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(UITheme.textMuted)

                Text(model.statusText)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button {
                model.refresh()
            } label: {
                Group {
                    if model.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(UITheme.textMuted)
                    }
                }
                .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help("Refresh")
            .keyboardShortcut("r", modifiers: [.command])
            .disabled(model.isLoading)
        }
        .padding(.horizontal, 2)
    }

    private var headerTitle: String {
        switch selection ?? .dashboard {
        case .dashboard:
            return "\(timeOfDayGreeting), \(firstName)"
        default:
            return (selection ?? .dashboard).rawValue
        }
    }

    private var headerSubtitle: String {
        switch selection ?? .dashboard {
        case .dashboard:
            guard let snapshot = model.snapshot else {
                return "Loading summary from Codex + Claude..."
            }
            let sessions = number(snapshot.sessionUsages.count)
            let cost = (model.costSummary?.allTime ?? 0).currency
            return "\(sessions) sessions analyzed. Estimated spend: \(cost)."
        case .pricing:
            let cutoff = sessionHistoryRange.cutoff()
            let count = number(model.liveSessions.filter { $0.lastUpdated >= cutoff }.count)
            return "Detailed model-level costs and \(count) session rows in \(sessionHistoryRange.rawValue)."
        case .threads:
            let count = number(model.snapshot?.threads.count ?? 0)
            return "\(count) recent threads. Deep dive view can be added next."
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        if let snapshot = model.snapshot {
            switch selection ?? .dashboard {
            case .dashboard:
                dashboardView(snapshot)
            case .pricing:
                pricingView()
            case .threads:
                threadsView(snapshot)
            }
        } else if model.isLoading {
            LoadingStateView(showTableSkeleton: (selection ?? .dashboard) != .dashboard)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            ContentUnavailableView(
                "No Data Loaded",
                systemImage: "tray",
                description: Text("Run Codex or Claude once so ~/.codex or ~/.claude exists, then click Refresh.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var firstName: String {
        let parts = NSFullUserName().split(separator: " ")
        return parts.first.map(String.init) ?? "Operator"
    }

    private var timeOfDayGreeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:
            return "Good morning"
        case 12..<17:
            return "Good afternoon"
        case 17..<22:
            return "Good evening"
        default:
            return "Burning the midnight oil"
        }
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
