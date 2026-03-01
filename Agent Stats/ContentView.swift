import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                headerBar

                if model.isLoading {
                    ProgressView(model.statusText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(model.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let errorText = model.errorText {
                    Text(errorText)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let snapshot = model.snapshot {
                    ScrollView {
                        VStack(spacing: 16) {
                            overviewGrid(snapshot)
                            analyticsGrid(snapshot)
                            sessionsTable(snapshot)
                        }
                        .padding(.bottom, 24)
                    }
                } else if !model.isLoading {
                    ContentUnavailableView(
                        "No Data Loaded",
                        systemImage: "tray",
                        description: Text("Pick your ~/.codex folder and click Refresh.")
                    )
                }
            }
            .padding(20)
            .navigationTitle("Agent Stats")
        }
        .frame(minWidth: 1120, minHeight: 760)
    }

    private var headerBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Codex Folder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(model.codexPathLabel)
                    .font(.callout)
                    .textSelection(.enabled)
            }

            Spacer()

            Button("Choose .codex Folder") {
                model.chooseCodexFolder()
            }

            Button("Refresh") {
                model.refresh()
            }
            .keyboardShortcut("r", modifiers: [.command])
            .disabled(model.isLoading)
        }
    }

    private func overviewGrid(_ snapshot: CodexSnapshot) -> some View {
        let columns = [GridItem(.adaptive(minimum: 210), spacing: 12)]

        return LazyVGrid(columns: columns, spacing: 12) {
            MetricCard(title: "Total Threads", value: number(snapshot.totalThreads), icon: "bubble.left.and.bubble.right")
            MetricCard(title: "Active Threads", value: number(snapshot.activeThreads), icon: "bolt.circle")
            MetricCard(title: "Archived Threads", value: number(snapshot.archivedThreads), icon: "archivebox")
            MetricCard(title: "Thread Tokens", value: number(snapshot.totalTokensFromThreads), icon: "number")
            MetricCard(title: "Event Tokens", value: number(snapshot.totalTokensFromEventFiles), icon: "sum")
            MetricCard(title: ".codex Size", value: snapshot.codexSizeBytes.byteString, icon: "externaldrive")
            MetricCard(title: "Sessions Size", value: snapshot.sessionsSizeBytes.byteString, icon: "folder")
            MetricCard(title: "Archive Size", value: snapshot.archivedSessionsSizeBytes.byteString, icon: "shippingbox")
            MetricCard(title: "Session Files", value: number(snapshot.sessionFileCount), icon: "doc.on.doc")
            MetricCard(title: "Archived Files", value: number(snapshot.archivedSessionFileCount), icon: "doc.on.doc.fill")
            MetricCard(title: "Session Lines", value: number(snapshot.sessionLineCount), icon: "text.line.first.and.arrowtriangle.forward")
            MetricCard(title: "Archived Lines", value: number(snapshot.archivedSessionLineCount), icon: "text.line.last.and.arrowtriangle.forward")
            MetricCard(title: "Allowed Rules", value: number(snapshot.rulesAllowCount), icon: "checkmark.shield")
            MetricCard(title: "Installed Skills", value: number(snapshot.installedSkillCount), icon: "square.stack.3d.up")
            MetricCard(title: "Trusted Projects", value: number(snapshot.projectTrustCount), icon: "checkmark.seal")
            MetricCard(title: "Log Errors / Warns", value: "\(number(snapshot.logErrorCount)) / \(number(snapshot.logWarnCount))", icon: "exclamationmark.triangle")
        }
    }

    private func analyticsGrid(_ snapshot: CodexSnapshot) -> some View {
        HStack(alignment: .top, spacing: 12) {
            CountListCard(title: "Top Models", rows: snapshot.modelCounts)
            CountListCard(title: "Top Sources", rows: snapshot.sourceCounts)
            CountListCard(title: "Event Types", rows: snapshot.eventTypeCounts)
            CountListCard(title: "Top Tools", rows: snapshot.toolCounts)
        }
    }

    private func sessionsTable(_ snapshot: CodexSnapshot) -> some View {
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
                .width(min: 80, max: 260)

                TableColumn("Model") { thread in
                    Text(thread.modelProvider)
                }
                .width(min: 80, max: 160)

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
            .frame(minHeight: 320)
        }
        .padding(12)
        .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func number(_ value: Int) -> String {
        NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
    }

    private func number(_ value: Int64) -> String {
        NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
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
        .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct CountListCard: View {
    let title: String
    let rows: [CountStat]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            if rows.isEmpty {
                Text("No data")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(rows.prefix(10))) { row in
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
        .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

#Preview {
    ContentView(model: AppModel())
}
