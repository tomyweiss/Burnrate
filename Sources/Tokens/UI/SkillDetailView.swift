import SwiftUI

/// Drill-in view for one skill: every prompt that invoked it, with costs.
struct SkillDetailView: View {
    let skill: SkillUsage
    let prompts: [PromptUsage]
    let onBack: () -> Void

    @AppStorage("sessionPromptSort") private var sortRaw = SessionPromptSort.newest.rawValue

    private var sort: Binding<SessionPromptSort> {
        Binding(
            get: { SessionPromptSort(rawValue: sortRaw) ?? .newest },
            set: { sortRaw = $0.rawValue }
        )
    }

    private var sortedPrompts: [PromptUsage] {
        switch sort.wrappedValue {
        case .newest:
            prompts.sorted { $0.createdAtMs > $1.createdAtMs }
        case .cost:
            prompts.sorted {
                $0.costCents == $1.costCents
                    ? $0.createdAtMs > $1.createdAtMs
                    : $0.costCents > $1.costCents
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            Picker("Sort", selection: sort) {
                ForEach(SessionPromptSort.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .onChange(of: sortRaw) { _, _ in
                MenuBarPanelKeeper.keepOpen()
            }

            if prompts.isEmpty {
                Text("No prompts used this skill in the window")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(sortedPrompts) { prompt in
                            PromptRowView(prompt: prompt)
                            Divider().opacity(0.35)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Back to skills")

            VStack(alignment: .leading, spacing: 2) {
                Text("/\(skill.skill)")
                    .font(.callout.weight(.semibold).monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(MoneyFormat.dollars(skill.costDollars))
                .font(.callout.monospacedDigit().weight(.semibold))
                .help("Total across all uses, including subagent work")
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        parts.append(skill.invocationCount == 1 ? "1 use" : "\(skill.invocationCount) uses")
        parts.append("avg \(MoneyFormat.dollars(skill.averageCostDollars))")
        parts.append("med \(MoneyFormat.dollars(skill.medianCostDollars))")
        return parts.joined(separator: " · ")
    }
}
