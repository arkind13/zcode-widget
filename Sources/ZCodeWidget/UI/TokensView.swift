import SwiftUI
import Charts

// MARK: - TokensViewModel

@MainActor
final class TokensViewModel: ObservableObject {
    @Published var totals = UsageTotals(totalInput: 0, totalOutput: 0, totalComputed: 0, callCount: 0)
    @Published var dailyTotals: [DailyUsage] = []
    @Published var recentTurns: [TurnRecord] = []

    private let repository = TokenUsageRepository()
    private var watcher: TokenTailWatcher?

    init() {
        watcher = TokenTailWatcher()
        watcher?.onNewRecord = { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func refresh() {
        do {
            totals = try repository.totals()
            dailyTotals = try repository.dailyTotals(days: 7)
            recentTurns = try repository.recentTurns(limit: 20)
        } catch {
            print("TokensViewModel.refresh error: \(error)")
        }
    }
}

// MARK: - TokensView

struct TokensView: View {
    @StateObject private var viewModel = TokensViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Totals header
                HStack(spacing: 16) {
                    StatCard(title: "Input", value: formatTokens(viewModel.totals.totalInput), color: .blue)
                    StatCard(title: "Output", value: formatTokens(viewModel.totals.totalOutput), color: .orange)
                    StatCard(title: "Total", value: formatTokens(viewModel.totals.totalComputed), color: .green)
                }

                // 7-day bar chart
                if !viewModel.dailyTotals.isEmpty {
                    Text("Last 7 Days")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Chart(viewModel.dailyTotals) { item in
                        BarMark(
                            x: .value("Day", item.date, unit: .day),
                            y: .value("Tokens", item.computedTotal)
                        )
                        .foregroundStyle(.green.gradient)
                        .cornerRadius(3)
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day)) { _ in
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true)
                        }
                    }
                    .chartYAxis {
                        AxisMarks { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let v = value.as(Int.self) {
                                    Text(formatTokens(v))
                                        .font(.system(size: 9))
                                }
                            }
                        }
                    }
                    .frame(height: 120)
                }

                Divider()

                // Recent turns sparkline
                Text("Recent Turns")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                if !viewModel.recentTurns.isEmpty {
                    Chart(viewModel.recentTurns) { turn in
                        LineMark(
                            x: .value("Turn", turn.id),
                            y: .value("Tokens", turn.computedTotalTokens)
                        )
                        .foregroundStyle(.blue.gradient)
                        .interpolationMethod(.catmullRom)

                        AreaMark(
                            x: .value("Turn", turn.id),
                            y: .value("Tokens", turn.computedTotalTokens)
                        )
                        .foregroundStyle(.blue.opacity(0.1).gradient)
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis {
                        AxisMarks { value in
                            AxisValueLabel {
                                if let v = value.as(Int.self) {
                                    Text(formatTokens(v)).font(.system(size: 9))
                                }
                            }
                        }
                    }
                    .frame(height: 80)

                    // Turn list
                    ForEach(viewModel.recentTurns.suffix(5).reversed()) { turn in
                        HStack {
                            Text(formatDate(turn.createdAt))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(formatTokens(turn.inputTokens)) in -> \(formatTokens(turn.outputTokens)) out")
                                .font(.system(size: 10))
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
            .padding(16)
        }
        .onAppear {
            viewModel.refresh()
        }
    }

    private func formatTokens(_ n: Int) -> String {
        if n >= 1_000_000 {
            return String(format: "%.1fM", Double(n) / 1_000_000)
        } else if n >= 1_000 {
            return String(format: "%.1fK", Double(n) / 1_000)
        }
        return "\(n)"
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f.string(from: date)
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
}