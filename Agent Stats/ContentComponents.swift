import Charts
import SwiftUI

struct TechBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [UITheme.page, UITheme.pageAlt],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            UITheme.accentA.opacity(0.10),
                            .clear,
                            UITheme.accentB.opacity(0.14),
                        ],
                        startPoint: .bottomLeading,
                        endPoint: .topTrailing
                    )
                )
                .blendMode(.screen)

            GridPattern()
                .stroke(UITheme.border.opacity(0.5), lineWidth: 0.5)
                .opacity(0.28)
        }
    }
}

struct LoadingStateView: View {
    let showTableSkeleton: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.title3)
                    .foregroundStyle(UITheme.textMuted)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Analyzing local data")
                        .font(.headline)
                    Text("Reading Codex + Claude sessions and recalculating costs.")
                        .font(.caption)
                        .foregroundStyle(UITheme.textMuted)
                }
                Spacer()
            }
            .padding(12)
            .panelCard()

            let columns = [GridItem(.adaptive(minimum: 175, maximum: 320), spacing: 10)]
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(0..<8, id: \.self) { _ in
                    SkeletonMetricCard()
                }
            }

            HStack(alignment: .top, spacing: 12) {
                ForEach(0..<3, id: \.self) { _ in
                    SkeletonListCard()
                }
            }

            if showTableSkeleton {
                SkeletonTableCard()
            }
        }
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(UITheme.textMuted)
            Text(value)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.55)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .panelCard(insetPadding: 0)
    }
}

struct CardHeader: View {
    let title: String
    let icon: String
    var subtitle: String = ""
    var iconColor: Color = UITheme.accentB
    var trailingText: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(iconColor)
            Text(title)
                .font(.headline)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(UITheme.textMuted)
            }
            Spacer()
            if let trailingText, !trailingText.isEmpty {
                Text(trailingText)
                    .font(.caption)
                    .foregroundStyle(UITheme.textMuted)
            }
        }
    }
}

struct CountListCard: View {
    let title: String
    let rows: [CountStat]
    var rowLimit: Int = 10
    var keyFormatter: (String) -> String = { $0 }
    var icon: String = "list.bullet"
    var minHeight: CGFloat? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(title: title, icon: icon)

            if rows.isEmpty {
                Text("No data")
                    .font(.caption)
                    .foregroundStyle(UITheme.textMuted)
            } else {
                ForEach(Array(rows.prefix(rowLimit))) { row in
                    HStack(spacing: 8) {
                        Text(keyFormatter(row.key))
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        Spacer()
                        Text(row.count, format: .number)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(UITheme.textMuted)
                            .monospacedDigit()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(minHeight: minHeight, alignment: .topLeading)
        .padding(12)
        .panelCard(insetPadding: 0)
    }
}

struct CostByModelCard: View {
    let title: String
    let rows: [ModelCostRow]
    var rowLimit: Int = 5
    var minHeight: CGFloat? = nil

    private let barPalette: [Color] = [
        UITheme.accentC,
        UITheme.accentB,
        Color(red: 0.43, green: 0.77, blue: 0.50),
        Color.white.opacity(0.25),
        UITheme.accentA,
    ]

    var body: some View {
        let displayedRows = Array(rows.prefix(rowLimit))
        let maxCost = displayedRows.map(\.cost).max() ?? 0
        let totalCost = displayedRows.reduce(0) { $0 + $1.cost }

        return VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: title, icon: "dollarsign.circle.fill", iconColor: UITheme.accentC)

            if displayedRows.isEmpty {
                Text("No data")
                    .font(.caption)
                    .foregroundStyle(UITheme.textMuted)
                    .padding(.vertical, 6)
            } else {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(Array(displayedRows.enumerated()), id: \.element.id) { index, row in
                        HStack(spacing: 10) {
                            Text(row.model.modelDisplayName)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                                .frame(minWidth: 92, maxWidth: 145, alignment: .leading)

                            GeometryReader { proxy in
                                let ratio = maxCost > 0 ? row.cost / maxCost : 0
                                let width = max(proxy.size.width * ratio, row.cost > 0 ? 4 : 0)

                                ZStack(alignment: .leading) {
                                    Capsule(style: .continuous)
                                        .fill(UITheme.surfaceAlt.opacity(0.9))
                                    Capsule(style: .continuous)
                                        .fill(colorForBar(index))
                                        .frame(width: width)
                                }
                            }
                            .frame(height: 8)

                            Text(row.cost.currency)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(UITheme.textMuted)
                                .monospacedDigit()
                                .frame(width: 92, alignment: .trailing)
                        }
                    }
                }

                HStack {
                    Spacer()
                    Text("Total: \(totalCost.currency)")
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                }
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(minHeight: minHeight, alignment: .topLeading)
        .padding(12)
        .panelCard(insetPadding: 0)
    }

    private func colorForBar(_ index: Int) -> Color {
        barPalette[index % barPalette.count]
    }
}

struct ModelSeriesPoint: Identifiable, Hashable {
    let date: Date
    let model: String
    let value: Double

    var id: String { "\(model)|\(date.timeIntervalSince1970)" }
}

struct ModelHourlyUsagePoint: Identifiable, Hashable {
    let hour: Int
    let model: String
    let count: Double

    var id: String { "\(model)|\(hour)" }
}

private struct ModelLegend: View {
    let models: [String]
    let colors: [String: Color]
    var wraps: Bool = true

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 150, maximum: 260), spacing: 10)]
    }

    var body: some View {
        Group {
            if wraps {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                    ForEach(models, id: \.self) { model in
                        legendItem(model)
                    }
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(models, id: \.self) { model in
                            legendItem(model)
                        }
                    }
                    .padding(.trailing, 2)
                }
            }
        }
    }

    private func legendItem(_ model: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(colors[model] ?? .gray)
                .frame(width: 8, height: 8)
            Text(model)
                .font(.caption)
                .foregroundStyle(UITheme.textMuted)
                .lineLimit(1)
        }
    }
}

struct ActivityHeatmapCard: View {
    let title: String
    let subtitle: String
    let countsByDay: [Date: Int]
    let days: Int
    var minHeight: CGFloat? = nil

    private let cellSize: CGFloat = 13
    private let cellGap: CGFloat = 4

    @State private var hoveredDate: Date?

    var body: some View {
        let calendar = isoCalendar
        let endDay = calendar.startOfDay(for: Date())
        let startDay = calendar.date(byAdding: .day, value: -(max(days, 1) - 1), to: endDay) ?? endDay
        let dates = dayRange(from: startDay, to: endDay, calendar: calendar)
        let startPadding = weekdayOffset(startDay, calendar: calendar)

        var cells: [Date?] = Array(repeating: nil, count: startPadding)
        cells.append(contentsOf: dates.map(Optional.some))
        while cells.count % 7 != 0 {
            cells.append(nil)
        }

        let weekColumns = stride(from: 0, to: cells.count, by: 7).map { startIndex in
            Array(cells[startIndex ..< min(startIndex + 7, cells.count)])
        }
        let maxCount = max(countsByDay.values.max() ?? 0, 1)
        let totalSessions = countsByDay.values.reduce(0, +)
        let activeDays = countsByDay.values.filter { $0 > 0 }.count
        let averagePerDay = days > 0 ? Double(totalSessions) / Double(days) : 0
        let peakDay = peakDay(calendar: calendar)
        let topWeekdays = weekdayTotals(calendar: calendar).prefix(3)

        return VStack(alignment: .leading, spacing: 12) {
            CardHeader(
                title: title,
                icon: "calendar",
                subtitle: subtitle,
                iconColor: UITheme.accentA,
                trailingText: hoveredHeatmapText(calendar: calendar)
            )

            HStack(alignment: .top, spacing: 14) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .trailing, spacing: cellGap) {
                        ForEach(0..<7, id: \.self) { row in
                            Text(dayRowLabel(row))
                                .font(.caption2)
                                .foregroundStyle(UITheme.textMuted)
                                .frame(width: 26, height: cellSize, alignment: .trailing)
                        }
                    }
                    .padding(.top, 0)

                    HStack(alignment: .top, spacing: cellGap) {
                        ForEach(Array(weekColumns.enumerated()), id: \.offset) { _, week in
                            VStack(spacing: cellGap) {
                                ForEach(Array(week.enumerated()), id: \.offset) { _, cellDate in
                                    heatCell(cellDate, maxCount: maxCount, calendar: calendar)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: 320, alignment: .leading)

                Divider()
                    .background(UITheme.border)

                VStack(alignment: .leading, spacing: 8) {
                    statRow("Total sessions", value: "\(totalSessions)")
                    statRow("Active days", value: "\(activeDays) / \(days)")
                    statRow("Avg / day", value: String(format: "%.1f", averagePerDay))
                    statRow(
                        "Peak day",
                        value: peakDay.map { "\($0.date.formatted(.dateTime.month(.abbreviated).day())) • \($0.count)" } ?? "No activity"
                    )

                    Divider()
                        .background(UITheme.border)
                        .padding(.vertical, 2)

                    ForEach(Array(topWeekdays.enumerated()), id: \.offset) { _, weekday in
                        HStack(spacing: 8) {
                            Text(weekday.label)
                                .font(.caption)
                                .foregroundStyle(UITheme.textMuted)
                                .frame(width: 44, alignment: .leading)
                            GeometryReader { proxy in
                                let maxWeekday = max(topWeekdays.map(\.count).max() ?? 1, 1)
                                let width = proxy.size.width * (Double(weekday.count) / Double(maxWeekday))
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(UITheme.accentA.opacity(0.8))
                                    .frame(width: max(width, weekday.count > 0 ? 6 : 0))
                            }
                            .frame(height: 6)
                            Text("\(weekday.count)")
                                .font(.caption)
                                .foregroundStyle(UITheme.textMuted)
                                .monospacedDigit()
                        }
                        .frame(height: 14)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            HStack(spacing: 6) {
                Text("Less")
                    .font(.caption2)
                    .foregroundStyle(UITheme.textMuted)
                ForEach(0..<5, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(heatColor(level: level, maxLevel: 4))
                        .frame(width: cellSize, height: cellSize)
                }
                Text("More")
                    .font(.caption2)
                    .foregroundStyle(UITheme.textMuted)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(minHeight: minHeight, alignment: .topLeading)
        .padding(12)
        .panelCard(insetPadding: 0)
    }

    private func statRow(_ label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(UITheme.textMuted)
            Spacer()
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.92))
                .monospacedDigit()
        }
    }

    private var isoCalendar: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        return calendar
    }

    private func dayRange(from start: Date, to end: Date, calendar: Calendar) -> [Date] {
        guard start <= end else { return [] }
        var days: [Date] = []
        var cursor = start
        while cursor <= end {
            days.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return days
    }

    private func weekdayOffset(_ date: Date, calendar: Calendar) -> Int {
        let weekday = calendar.component(.weekday, from: date)
        return (weekday + 5) % 7 // monday = 0
    }

    private func weekdayTotals(calendar: Calendar) -> [(label: String, count: Int)] {
        var totals: [Int: Int] = [:]
        for (day, count) in countsByDay {
            let weekday = calendar.component(.weekday, from: day)
            totals[weekday, default: 0] += count
        }

        return totals
            .map { (weekday, count) in
                let label = calendar.veryShortWeekdaySymbols[(weekday - 1 + 7) % 7]
                return (label, count)
            }
            .sorted { lhs, rhs in
                if lhs.count == rhs.count {
                    return lhs.label < rhs.label
                }
                return lhs.count > rhs.count
            }
    }

    private func peakDay(calendar: Calendar) -> (date: Date, count: Int)? {
        countsByDay
            .map { (date: calendar.startOfDay(for: $0.key), count: $0.value) }
            .max { lhs, rhs in
                if lhs.count == rhs.count {
                    return lhs.date < rhs.date
                }
                return lhs.count < rhs.count
            }
    }

    @ViewBuilder
    private func heatCell(_ date: Date?, maxCount: Int, calendar: Calendar) -> some View {
        if let date {
            let day = calendar.startOfDay(for: date)
            let count = countsByDay[day] ?? 0
            let intensity = Int(round((Double(count) / Double(maxCount)) * 4.0))

            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(heatColor(level: intensity, maxLevel: 4))
                .frame(width: cellSize, height: cellSize)
                .onHover { inside in
                    hoveredDate = inside ? day : nil
                }
        } else {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.clear)
                .frame(width: cellSize, height: cellSize)
        }
    }

    private func heatColor(level: Int, maxLevel: Int) -> Color {
        let normalized = max(0, min(level, maxLevel))
        switch normalized {
        case 0: return UITheme.surfaceAlt.opacity(0.55)
        case 1: return Color(red: 0.13, green: 0.30, blue: 0.16)
        case 2: return Color(red: 0.18, green: 0.47, blue: 0.22)
        case 3: return Color(red: 0.33, green: 0.68, blue: 0.34)
        default: return Color(red: 0.49, green: 0.83, blue: 0.47)
        }
    }

    private func dayRowLabel(_ row: Int) -> String {
        switch row {
        case 0: return "Mon"
        case 2: return "Wed"
        case 4: return "Fri"
        default: return ""
        }
    }

    private func hoveredHeatmapText(calendar: Calendar) -> String? {
        guard let hoveredDate else { return nil }
        let day = calendar.startOfDay(for: hoveredDate)
        let count = countsByDay[day] ?? 0
        return "\(count) sessions • \(hoveredDate.formatted(.dateTime.month().day()))"
    }
}

struct ModelMultiLineChartCard: View {
    let title: String
    let subtitle: String
    let points: [ModelSeriesPoint]
    let colors: [String: Color]
    var minHeight: CGFloat? = nil

    @State private var hoveredDate: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            cardHeader

            if points.isEmpty {
                Text("No data in selected range")
                    .font(.caption)
                    .foregroundStyle(UITheme.textMuted)
                    .padding(.vertical, 6)
            } else {
                let seriesOrder = orderedModels(points: points)
                Chart {
                    ForEach(points) { point in
                        LineMark(
                            x: .value("Day", point.date, unit: .day),
                            y: .value("Value", point.value)
                        )
                        .interpolationMethod(.catmullRom)
                        .lineStyle(.init(lineWidth: 2))
                        .foregroundStyle(by: .value("Model", point.model))

                        if let hoveredDate,
                           Calendar.current.isDate(point.date, inSameDayAs: hoveredDate) {
                            PointMark(
                                x: .value("Day", point.date, unit: .day),
                                y: .value("Value", point.value)
                            )
                            .foregroundStyle(by: .value("Model", point.model))
                        }
                    }

                    if let hoveredDate {
                        RuleMark(x: .value("Day", hoveredDate, unit: .day))
                            .lineStyle(.init(lineWidth: 1, dash: [4, 4]))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                }
                .chartForegroundStyleScale(
                    domain: seriesOrder,
                    range: seriesOrder.map { colors[$0] ?? .gray }
                )
                .chartLegend(.hidden)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let location):
                                    guard let plotFrame = proxy.plotFrame else {
                                        hoveredDate = nil
                                        return
                                    }
                                    let origin = geometry[plotFrame].origin
                                    let x = location.x - origin.x
                                    guard x >= 0, x <= proxy.plotSize.width,
                                          let date: Date = proxy.value(atX: x) else {
                                        hoveredDate = nil
                                        return
                                    }
                                    hoveredDate = Calendar.current.startOfDay(for: date)
                                case .ended:
                                    hoveredDate = nil
                                }
                            }
                    }
                }
                .frame(height: 210)

                ModelLegend(models: seriesOrder, colors: colors, wraps: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(minHeight: minHeight, alignment: .topLeading)
        .padding(12)
        .panelCard(insetPadding: 0)
    }

    @ViewBuilder
    private var cardHeader: some View {
        CardHeader(
            title: title,
            icon: "chart.line.uptrend.xyaxis",
            subtitle: subtitle,
            iconColor: UITheme.accentB,
            trailingText: hoveredDate.map { $0.formatted(.dateTime.month(.abbreviated).day()) }
        )
    }
}

struct ModelHourlyStackedCard: View {
    let title: String
    let subtitle: String
    let points: [ModelHourlyUsagePoint]
    let colors: [String: Color]
    var minHeight: CGFloat? = nil

    @State private var hoveredHour: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(
                title: title,
                icon: "clock.fill",
                subtitle: subtitle,
                iconColor: UITheme.accentA,
                trailingText: hoveredHour.map(hourLabel)
            )

            if points.isEmpty {
                Text("No data")
                    .font(.caption)
                    .foregroundStyle(UITheme.textMuted)
                    .padding(.vertical, 6)
            } else {
                let seriesOrder = orderedModels(points: points)
                Chart {
                    ForEach(points) { point in
                        BarMark(
                            x: .value("Hour", point.hour),
                            y: .value("Sessions", point.count)
                        )
                        .foregroundStyle(by: .value("Model", point.model))
                        .cornerRadius(2)
                    }

                    if let hoveredHour {
                        RuleMark(x: .value("Hour", hoveredHour))
                            .lineStyle(.init(lineWidth: 1, dash: [4, 4]))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                }
                .chartForegroundStyleScale(
                    domain: seriesOrder,
                    range: seriesOrder.map { colors[$0] ?? .gray }
                )
                .chartLegend(.hidden)
                .chartXAxis {
                    AxisMarks(values: [0, 6, 12, 18, 23]) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let hour = value.as(Int.self) {
                                Text(hourLabel(hour))
                            }
                        }
                    }
                }
                .chartYAxis(.hidden)
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let location):
                                    guard let plotFrame = proxy.plotFrame else {
                                        hoveredHour = nil
                                        return
                                    }
                                    let origin = geometry[plotFrame].origin
                                    let x = location.x - origin.x
                                    guard x >= 0, x <= proxy.plotSize.width,
                                          let hourValue: Int = proxy.value(atX: x) else {
                                        hoveredHour = nil
                                        return
                                    }
                                    hoveredHour = min(max(hourValue, 0), 23)
                                case .ended:
                                    hoveredHour = nil
                                }
                            }
                    }
                }
                .frame(height: 170)

                ModelLegend(models: seriesOrder, colors: colors, wraps: false)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(minHeight: minHeight, alignment: .topLeading)
        .padding(12)
        .panelCard(insetPadding: 0)
    }

    private func hourLabel(_ hour: Int) -> String {
        switch hour {
        case 0: return "12a"
        case 12: return "12p"
        case 1..<12: return "\(hour)a"
        default: return "\(hour - 12)p"
        }
    }

    private func orderedModels(points: [ModelHourlyUsagePoint]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for point in points {
            if seen.insert(point.model).inserted {
                ordered.append(point.model)
            }
        }
        return ordered
    }
}

private extension ModelMultiLineChartCard {
    func orderedModels(points: [ModelSeriesPoint]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for point in points {
            if seen.insert(point.model).inserted {
                ordered.append(point.model)
            }
        }
        return ordered
    }
}

struct ProviderLimitCard: View {
    let status: ProviderLimitStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(status.provider)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(status.plan)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(UITheme.textMuted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(UITheme.surfaceAlt, in: Capsule())
            }

            Text(status.usageSummary)
                .font(.callout)
                .lineLimit(2)
                .foregroundStyle(.white.opacity(0.92))
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(12)
        .panelCard(insetPadding: 0)
    }
}

struct LiveSessionCardGrid: View {
    let title: String
    let subtitle: String
    let rows: [LiveSessionRow]
    let maxRows: Int
    var minHeight: CGFloat? = nil

    private static let tokenFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    var body: some View {
        let displayedRows = Array(rows.prefix(maxRows))
        let columns = [GridItem(.adaptive(minimum: 250, maximum: 460), spacing: 10)]

        return VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: title, icon: "clock.arrow.circlepath", subtitle: subtitle)

            if displayedRows.isEmpty {
                Text("No live sessions.")
                    .font(.callout)
                    .foregroundStyle(UITheme.textMuted)
                    .padding(.vertical, 6)
            } else {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(displayedRows) { row in
                        liveSessionCard(row)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(minHeight: minHeight, alignment: .topLeading)
        .padding(12)
        .panelCard(insetPadding: 0)
    }

    private func liveSessionCard(_ row: LiveSessionRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(row.isActiveNow ? "Live" : "Idle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(row.isActiveNow ? UITheme.accentA : UITheme.textMuted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(UITheme.surfaceAlt, in: Capsule())
                Text(row.provider)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(UITheme.textMuted)
                Spacer()
                Text(updatedLabel(for: row))
                    .font(.caption)
                    .foregroundStyle(UITheme.textMuted)
            }

            Text(row.model.modelDisplayName)
                .font(.headline)
                .lineLimit(1)

            Text(row.source)
                .font(.caption)
                .foregroundStyle(UITheme.textMuted)
                .lineLimit(1)

            HStack(spacing: 12) {
                metric("Tokens", number(row.totalTokens))
                metric("Est. Cost", row.estimatedCost.currency)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(10)
        .background(UITheme.surface.opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(UITheme.border, lineWidth: 1)
        )
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(UITheme.textMuted)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func updatedLabel(for row: LiveSessionRow) -> String {
        let delta = max(Int(Date().timeIntervalSince(row.lastUpdated)), 0)
        let minutes = delta / 60
        let seconds = delta % 60

        if minutes == 0 {
            return "\(seconds)s ago"
        }
        if minutes < 60 {
            return "\(minutes)m \(seconds)s"
        }
        return row.lastUpdated.friendly
    }

    private func number(_ value: Int64) -> String {
        LiveSessionCardGrid.tokenFormatter.string(from: NSNumber(value: value)) ?? "0"
    }
}

struct SessionPricingList: View {
    let title: String
    let subtitle: String
    let rows: [LiveSessionRow]
    let maxRows: Int
    var minHeight: CGFloat? = nil

    private static let tokenFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    var body: some View {
        let displayedRows = Array(rows.prefix(maxRows))

        return VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: title, icon: "clock.arrow.circlepath", subtitle: subtitle)

            if displayedRows.isEmpty {
                Text("No sessions available.")
                    .font(.callout)
                    .foregroundStyle(UITheme.textMuted)
                    .padding(.vertical, 10)
            } else {
                ViewThatFits(in: .horizontal) {
                    tableContent(displayedRows, isCompact: false)
                    tableContent(displayedRows, isCompact: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(minHeight: minHeight, alignment: .topLeading)
        .padding(12)
        .panelCard(insetPadding: 0)
    }

    @ViewBuilder
    private func tableContent(_ displayedRows: [LiveSessionRow], isCompact: Bool) -> some View {
        VStack(spacing: 0) {
            if isCompact {
                compactHeader
            } else {
                rowHeader
            }
            Divider().overlay(UITheme.border)

            LazyVStack(spacing: 0) {
                ForEach(displayedRows) { row in
                    if isCompact {
                        compactRowView(row)
                    } else {
                        rowView(row)
                    }
                    Divider().overlay(UITheme.border.opacity(0.65))
                }
            }
        }
    }

    private var compactHeader: some View {
        HStack(spacing: 8) {
            headerCell("Session", width: 220, alignment: .leading)
            Spacer(minLength: 0)
            headerCell("Tokens", width: 100, alignment: .trailing)
            headerCell("Est. Cost", width: 78, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var rowHeader: some View {
        HStack(spacing: 8) {
            headerCell("State", width: 64, alignment: .leading)
            headerCell("Provider", width: 74, alignment: .leading)
            headerCell("Source", width: 120, alignment: .leading)
            headerCell("Model", width: 150, alignment: .leading)
            headerCell("Updated", width: 115, alignment: .leading)
            headerCell("Tokens", width: 104, alignment: .trailing)
            headerCell("Est. Cost", width: 78, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func rowView(_ row: LiveSessionRow) -> some View {
        HStack(spacing: 8) {
            textCell(row.isActiveNow ? "Live" : "Idle", width: 64, color: row.isActiveNow ? UITheme.accentA : UITheme.textMuted)
            textCell(row.provider, width: 74)
            textCell(row.source, width: 120)
            textCell(row.model.modelDisplayName, width: 150)
            textCell(updatedLabel(for: row), width: 115)
            textCell(number(row.totalTokens), width: 104, alignment: .trailing)
            textCell(row.estimatedCost.currency, width: 78, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(row.isActiveNow ? UITheme.accentB.opacity(0.07) : Color.clear)
    }

    private func compactRowView(_ row: LiveSessionRow) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.isActiveNow ? "Live" : "Idle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(row.isActiveNow ? UITheme.accentA : UITheme.textMuted)
                    Text(row.provider)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(UITheme.textMuted)
                }
                Text(row.model.modelDisplayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("\(row.source) • \(updatedLabel(for: row))")
                    .font(.caption)
                    .foregroundStyle(UITheme.textMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            textCell(number(row.totalTokens), width: 100, alignment: .trailing)
            textCell(row.estimatedCost.currency, width: 78, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(row.isActiveNow ? UITheme.accentB.opacity(0.07) : Color.clear)
    }

    private func headerCell(_ text: String, width: CGFloat, alignment: Alignment) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(UITheme.textMuted)
            .frame(width: width, alignment: alignment)
    }

    private func textCell(
        _ text: String,
        width: CGFloat,
        alignment: Alignment = .leading,
        color: Color = .white
    ) -> some View {
        Text(text)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .frame(width: width, alignment: alignment)
    }

    private func updatedLabel(for row: LiveSessionRow) -> String {
        let delta = max(Int(Date().timeIntervalSince(row.lastUpdated)), 0)
        let minutes = delta / 60
        let seconds = delta % 60

        if minutes == 0 {
            return "\(seconds) sec"
        }
        if minutes < 60 {
            return "\(minutes) min, \(seconds) sec"
        }
        return row.lastUpdated.friendly
    }

    private func number(_ value: Int64) -> String {
        SessionPricingList.tokenFormatter.string(from: NSNumber(value: value)) ?? "0"
    }
}

private struct SkeletonMetricCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SkeletonBlock(width: 120, height: 12, cornerRadius: 5)
            SkeletonBlock(width: 180, height: 28, cornerRadius: 7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .panelCard(insetPadding: 0)
    }
}

private struct SkeletonListCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SkeletonBlock(width: 130, height: 12, cornerRadius: 5)
            ForEach(0..<5, id: \.self) { _ in
                SkeletonBlock(width: nil, height: 12, cornerRadius: 4)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
        .padding(12)
        .panelCard(insetPadding: 0)
    }
}

private struct SkeletonTableCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SkeletonBlock(width: 180, height: 12, cornerRadius: 5)
            ForEach(0..<8, id: \.self) { _ in
                SkeletonBlock(width: nil, height: 16, cornerRadius: 5)
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
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(UITheme.surfaceAlt)
            .overlay {
                TimelineView(.animation(minimumInterval: 1 / 24.0)) { context in
                    let cycle = 1.2
                    let progress = context.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: cycle) / cycle

                    GeometryReader { proxy in
                        let span = max(proxy.size.width, 1)
                        let offset = CGFloat(progress) * (span * 1.8) - (span * 0.9)

                        LinearGradient(
                            colors: [.clear, .white.opacity(0.22), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: span * 0.7)
                        .offset(x: offset)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            }
            .frame(width: width, height: height)
    }
}

private struct GridPattern: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let spacing: CGFloat = 24

        var x: CGFloat = 0
        while x <= rect.width {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: rect.height))
            x += spacing
        }

        var y: CGFloat = 0
        while y <= rect.height {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: rect.width, y: y))
            y += spacing
        }

        return path
    }
}

extension View {
    func panelCard(insetPadding: CGFloat = 10) -> some View {
        self
            .padding(insetPadding)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(UITheme.surface.opacity(0.93))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(UITheme.border, lineWidth: 1)
                    )
            )
    }
}
