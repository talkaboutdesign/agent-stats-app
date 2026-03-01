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

struct CountListCard: View {
    let title: String
    let rows: [CountStat]
    var rowLimit: Int = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            if rows.isEmpty {
                Text("No data")
                    .font(.caption)
                    .foregroundStyle(UITheme.textMuted)
            } else {
                ForEach(Array(rows.prefix(rowLimit))) { row in
                    HStack(spacing: 8) {
                        Text(row.key)
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
        .padding(12)
        .panelCard(insetPadding: 0)
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

struct SessionPricingList: View {
    let title: String
    let subtitle: String
    let rows: [LiveSessionRow]
    let maxRows: Int

    private static let tokenFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    var body: some View {
        let displayedRows = Array(rows.prefix(maxRows))

        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline.weight(.bold))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(UITheme.textMuted)
            }

            if displayedRows.isEmpty {
                Text("No sessions available.")
                    .font(.callout)
                    .foregroundStyle(UITheme.textMuted)
                    .padding(.vertical, 10)
            } else {
                GeometryReader { proxy in
                    let isCompact = proxy.size.width < 760

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
                .frame(minHeight: CGFloat(displayedRows.count) * 38 + 42)
                .background(UITheme.surface.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(UITheme.border, lineWidth: 1)
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(12)
        .panelCard(insetPadding: 0)
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
            textCell(row.model, width: 150)
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
                Text(row.model)
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
