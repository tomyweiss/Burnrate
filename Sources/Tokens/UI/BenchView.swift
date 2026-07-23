import SwiftUI
import Charts

/// Metrics that can drive an axis of the benchmark scatter. Every metric is
/// normalized so that "better" scores higher — top-right is always the best.
enum BenchMetric: String, CaseIterable, Identifiable {
    case avgPromptCost
    case avgTime
    case promptCount
    case totalCost
    case tokens

    var id: String { rawValue }

    var title: String {
        switch self {
        case .avgPromptCost: "Avg $/prompt"
        case .avgTime: "Avg time"
        case .promptCount: "Prompts"
        case .totalCost: "Total $"
        case .tokens: "Tokens"
        }
    }

    /// What earns a high score for this metric.
    var betterHint: String {
        switch self {
        case .avgPromptCost: "cheaper is better"
        case .avgTime: "faster is better"
        case .promptCount: "more is better"
        case .totalCost: "cheaper is better"
        case .tokens: "fewer is better"
        }
    }

    var higherRawIsBetter: Bool {
        self == .promptCount
    }
}

enum BenchBreakdown: String, CaseIterable, Identifiable {
    case skills
    case models
    case sessions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .skills: "Skills"
        case .models: "Models"
        case .sessions: "Sessions"
        }
    }
}

/// One dot on the benchmark: a skill, model, or session with its raw metrics.
struct BenchPoint: Identifiable {
    let id: String
    let name: String
    let promptCount: Int
    let totalCostCents: Double
    let totalTokens: Int
    let totalDurationSeconds: Double

    var avgCostCents: Double {
        promptCount > 0 ? totalCostCents / Double(promptCount) : 0
    }

    var avgDurationSeconds: Double {
        promptCount > 0 ? totalDurationSeconds / Double(promptCount) : 0
    }

    func rawValue(for metric: BenchMetric) -> Double {
        switch metric {
        case .avgPromptCost: avgCostCents
        case .avgTime: avgDurationSeconds
        case .promptCount: Double(promptCount)
        case .totalCost: totalCostCents
        case .tokens: Double(totalTokens)
        }
    }

    func rawLabel(for metric: BenchMetric) -> String {
        switch metric {
        case .avgPromptCost: MoneyFormat.dollarsFromCents(avgCostCents)
        case .avgTime: DurationFormat.compact(avgDurationSeconds)
        case .promptCount: "\(promptCount)"
        case .totalCost: MoneyFormat.dollarsFromCents(totalCostCents)
        case .tokens: TokenFormat.compact(totalTokens)
        }
    }
}

enum DurationFormat {
    static func compact(_ seconds: Double) -> String {
        if seconds >= 3600 {
            return String(format: "%.1fh", seconds / 3600)
        }
        if seconds >= 60 {
            return String(format: "%.0fm", seconds / 60)
        }
        return String(format: "%.0fs", seconds)
    }
}

/// Live benchmark scatter: pick two metrics and a breakdown; each entity is
/// scored 0–1 per axis (better = higher), so the top-right corner is the
/// overall winner on your own data.
struct BenchView: View {
    let snapshot: UsageSnapshot

    @AppStorage("benchBreakdown") private var breakdownRaw = BenchBreakdown.skills.rawValue
    @AppStorage("benchXMetric") private var xMetricRaw = BenchMetric.avgPromptCost.rawValue
    @AppStorage("benchYMetric") private var yMetricRaw = BenchMetric.avgTime.rawValue

    /// Cap the dots so labels stay readable; keeps the biggest spenders.
    private static let maxPoints = 12

    private var breakdown: BenchBreakdown {
        BenchBreakdown(rawValue: breakdownRaw) ?? .skills
    }

    private var xMetric: BenchMetric {
        BenchMetric(rawValue: xMetricRaw) ?? .avgPromptCost
    }

    private var yMetric: BenchMetric {
        BenchMetric(rawValue: yMetricRaw) ?? .avgTime
    }

    var body: some View {
        VStack(spacing: 8) {
            controls
                .padding(.horizontal, 12)

            if points.count < 2 {
                Text("Not enough data to benchmark — need at least two \(breakdown.title.lowercased()) with prompts in this window")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .padding(24)
            } else {
                chart
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)

                Text("Dot size = total spend · top-right = best (\(xMetric.betterHint), \(yMetric.betterHint))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
        }
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 6) {
            Picker("Breakdown", selection: $breakdownRaw) {
                ForEach(BenchBreakdown.allCases) { option in
                    Text(option.title).tag(option.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .onChange(of: breakdownRaw) { _, _ in
                MenuBarPanelKeeper.keepOpen()
            }

            HStack(spacing: 8) {
                metricMenu(title: "X", selection: $xMetricRaw)
                metricMenu(title: "Y", selection: $yMetricRaw)
                Spacer()
            }
        }
    }

    private func metricMenu(title: String, selection: Binding<String>) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
            Picker(title, selection: selection) {
                ForEach(BenchMetric.allCases) { metric in
                    Text(metric.title).tag(metric.rawValue)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
            .onChange(of: selection.wrappedValue) { _, _ in
                MenuBarPanelKeeper.keepOpen()
            }
        }
    }

    // MARK: - Chart

    private var chart: some View {
        Chart(points) { point in
            PointMark(
                x: .value("X", score(point, metric: xMetric)),
                y: .value("Y", score(point, metric: yMetric))
            )
            .symbolSize(symbolSize(point))
            .foregroundStyle(by: .value("Name", point.name))
            .opacity(0.85)
            .annotation(position: .top, spacing: 1) {
                Text(point.name)
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 92)
                    .foregroundStyle(.secondary)
            }
        }
        .chartXScale(domain: -0.08 ... 1.12)
        .chartYScale(domain: -0.08 ... 1.12)
        .chartXAxis {
            AxisMarks(values: [0, 0.5, 1]) { _ in
                AxisGridLine().foregroundStyle(.quaternary)
            }
        }
        .chartYAxis {
            AxisMarks(values: [0, 0.5, 1]) { _ in
                AxisGridLine().foregroundStyle(.quaternary)
            }
        }
        .chartLegend(.hidden)
        .chartPlotStyle { plot in
            plot.background(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .green.opacity(0.05), location: 0.6),
                        .init(color: .green.opacity(0.18), location: 1)
                    ],
                    startPoint: .bottomLeading,
                    endPoint: .topTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .overlay(alignment: .topTrailing) {
            Label("Best", systemImage: "trophy.fill")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.green)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .glassEffect(.regular.tint(.green.opacity(0.25)))
                .clipShape(Capsule())
                .padding(6)
        }
        .overlay(alignment: .bottomTrailing) {
            axisTag("\(xMetric.title) →")
                .padding(.trailing, 6)
                .padding(.bottom, 2)
        }
        .overlay(alignment: .topLeading) {
            axisTag("↑ \(yMetric.title)")
                .padding(.leading, 6)
                .padding(.top, 2)
        }
    }

    private func axisTag(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.tertiary)
    }

    private func symbolSize(_ point: BenchPoint) -> CGFloat {
        let maxCost = points.map(\.totalCostCents).max() ?? 0
        guard maxCost > 0 else { return 140 }
        let fraction = point.totalCostCents / maxCost
        return 90 + CGFloat(fraction) * 360
    }

    /// 0…1 score for a metric where 1 is always "better".
    private func score(_ point: BenchPoint, metric: BenchMetric) -> Double {
        let values = points.map { $0.rawValue(for: metric) }
        guard let min = values.min(), let max = values.max(), max > min else {
            return 0.5
        }
        let normalized = (point.rawValue(for: metric) - min) / (max - min)
        return metric.higherRawIsBetter ? normalized : 1 - normalized
    }

    // MARK: - Data

    private var points: [BenchPoint] {
        let prompts = snapshot.prompts.filter { $0.eventCount > 0 }
        guard !prompts.isEmpty else { return [] }

        var grouped: [String: (name: String, prompts: [PromptUsage])] = [:]
        switch breakdown {
        case .skills:
            for prompt in prompts {
                for skill in prompt.skills {
                    grouped[skill, default: ("/\(skill)", [])].prompts.append(prompt)
                }
            }
        case .models:
            // Attribute each prompt to its top-cost model to avoid double counting.
            for prompt in prompts {
                guard let model = prompt.models.first else { continue }
                grouped[model, default: (model, [])].prompts.append(prompt)
            }
        case .sessions:
            for prompt in prompts {
                let name = prompt.sessionName
                    ?? "Session \(prompt.conversationId.prefix(8))"
                grouped[prompt.conversationId, default: (name, [])].prompts.append(prompt)
            }
        }

        return grouped
            .map { id, entry in
                BenchPoint(
                    id: id,
                    name: entry.name,
                    promptCount: entry.prompts.count,
                    totalCostCents: entry.prompts.reduce(0) { $0 + $1.costCents },
                    totalTokens: entry.prompts.reduce(0) { $0 + $1.totalTokens },
                    totalDurationSeconds: entry.prompts.reduce(0) { $0 + $1.durationSeconds }
                )
            }
            .sorted { $0.totalCostCents > $1.totalCostCents }
            .prefix(Self.maxPoints)
            .map { $0 }
    }
}
