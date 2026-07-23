import SwiftUI

struct SkillRowView: View {
    let skill: SkillUsage
    let windowCostCents: Double

    @State private var hovering = false

    private var share: Double {
        guard windowCostCents > 0 else { return 0 }
        return skill.costCents / windowCostCents
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("/\(skill.skill)")
                    .font(.callout.weight(.medium).monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Text(MoneyFormat.dollars(skill.costDollars))
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .contentTransition(.numericText())
            }

            ShareBar(fraction: share)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(hovering ? Color.primary.opacity(0.06) : Color.clear)
        )
        .onHover { hovering = $0 }
    }

    private var subtitle: String {
        var parts: [String] = []
        parts.append(skill.invocationCount == 1 ? "1 use" : "\(skill.invocationCount) uses")
        parts.append("avg \(MoneyFormat.dollars(skill.averageCostDollars))")
        if skill.lastUsedMs > 0 {
            parts.append(RelativeTimeFormat.string(fromTimestampMs: skill.lastUsedMs))
        }
        return parts.joined(separator: " · ")
    }
}

struct PromptRowView: View {
    let prompt: PromptUsage
    var showSessionName: Bool = true

    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(prompt.headline)
                    .font(.callout)
                    .lineLimit(2)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                Text(MoneyFormat.dollars(prompt.costDollars))
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .foregroundStyle(prompt.costCents > 0 ? Color.primary : Color.secondary)
                    .contentTransition(.numericText())
            }

            if !prompt.skills.isEmpty {
                HStack(spacing: 4) {
                    ForEach(prompt.skills, id: \.self) { skill in
                        Text("/\(skill)")
                            .font(.caption2.weight(.semibold).monospaced())
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                Capsule().fill(Color.accentColor.opacity(0.18))
                            )
                    }
                }
            }

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(hovering ? Color.primary.opacity(0.06) : Color.clear)
        )
        .onHover { hovering = $0 }
        .help(prompt.text)
    }

    private var subtitle: String {
        var parts: [String] = []
        if prompt.createdAtMs > 0 {
            parts.append(RelativeTimeFormat.string(fromTimestampMs: prompt.createdAtMs))
        }
        if showSessionName, let name = prompt.sessionName, !name.isEmpty {
            parts.append(name)
        }
        if let model = prompt.models.first {
            parts.append(
                prompt.models.count > 1 ? "\(model) +\(prompt.models.count - 1)" : model
            )
        }
        return parts.joined(separator: " · ")
    }
}
