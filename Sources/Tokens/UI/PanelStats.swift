import SwiftUI

struct PanelStat: Equatable, Sendable {
    let title: String
    let value: String
    let detail: String?

    /// One element per tile. A leading `~` is spoken as "estimated".
    /// Blurred tiles speak only the title, the same way `privacyBlurred` hides the figure.
    func accessibilityLabel(valuesHidden: Bool) -> String {
        if valuesHidden {
            return "\(title), hidden"
        }
        let spoken = value.hasPrefix("~") ? "estimated \(value.dropFirst())" : value
        if let detail {
            return "\(title), \(spoken), \(detail)"
        }
        return "\(title), \(spoken)"
    }

    var accessibilityLabel: String {
        accessibilityLabel(valuesHidden: false)
    }
}

enum PanelStats {
    static func make(snapshot: UsageSnapshot, style: CostStyle, now: Date = .now) -> [PanelStat] {
        [
            PanelStat(title: "Sessions", value: grouped(snapshot.rootSessions.count), detail: nil),
            PanelStat(title: "Events", value: grouped(snapshot.eventCount), detail: nil),
            topModel(snapshot),
            PanelStat(title: "Cache read", value: cacheRead(snapshot), detail: nil),
            PanelStat(title: "Per hour", value: perHour(snapshot, style: style, now: now), detail: nil),
            PanelStat(title: "Avg / session", value: averagePerSession(snapshot, style: style), detail: nil)
        ]
    }

    private static func topModel(_ snapshot: UsageSnapshot) -> PanelStat {
        guard let model = snapshot.models.enumerated().max(by: { lhs, rhs in
            if lhs.element.costCents == rhs.element.costCents {
                return lhs.offset > rhs.offset
            }
            return lhs.element.costCents < rhs.element.costCents
        })?.element else {
            return PanelStat(title: "Top model", value: "—", detail: nil)
        }
        let share = wholePercent(model.costCents, of: snapshot.windowCostCents)
        return PanelStat(title: "Top model", value: model.model, detail: "\(share)%")
    }

    private static func cacheRead(_ snapshot: UsageSnapshot) -> String {
        let total = snapshot.models.reduce(0) { $0 + $1.totalTokens }
        guard total > 0 else { return "—" }
        let cache = snapshot.models.reduce(0) { $0 + $1.cacheReadTokens }
        return "\(wholePercent(Double(cache), of: Double(total)))%"
    }

    /// `—` until the first fetch. Elapsed time never divides by less than one hour.
    private static func perHour(_ snapshot: UsageSnapshot, style: CostStyle, now: Date) -> String {
        guard snapshot.fetchedAt != .distantPast else { return "—" }
        let start = snapshot.window.dateRange(now: now).start
        let hours = max(now.timeIntervalSince(start) / 3600, 1)
        return MoneyFormat.string(snapshot.windowDollars / hours, style: style)
    }

    private static func averagePerSession(_ snapshot: UsageSnapshot, style: CostStyle) -> String {
        let count = snapshot.rootSessions.count
        guard count > 0 else { return "—" }
        return MoneyFormat.string(snapshot.windowDollars / Double(count), style: style)
    }

    private static func wholePercent(_ part: Double, of total: Double) -> Int {
        guard total > 0 else { return 0 }
        return Int((part / total * 100).rounded())
    }

    private static func grouped(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic).locale(Locale(identifier: "en_US")))
    }
}

/// Three columns by two rows, shown in the Stats popover.
struct PanelStatsGrid: View {
    let stats: [PanelStat]

    @Environment(\.blurSensitiveContent) private var blurSensitiveContent

    private static let columns = [
        GridItem(.flexible(), spacing: 8, alignment: .top),
        GridItem(.flexible(), spacing: 8, alignment: .top),
        GridItem(.flexible(), spacing: 8, alignment: .top)
    ]

    var body: some View {
        LazyVGrid(columns: Self.columns, spacing: 6) {
            ForEach(Array(stats.enumerated()), id: \.offset) { _, stat in
                tile(stat)
            }
        }
    }

    private func tile(_ stat: PanelStat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(stat.title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(stat.value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .modelDisplayName()
                .privacyBlurred(blurSensitiveContent)

            if let detail = stat.detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .privacyBlurred(blurSensitiveContent)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(stat.accessibilityLabel(valuesHidden: blurSensitiveContent))
    }
}
