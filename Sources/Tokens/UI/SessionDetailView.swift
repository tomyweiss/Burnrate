import SwiftUI

enum SessionPromptSort: String, CaseIterable, Identifiable {
    case newest
    case cost

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newest: "New → Old"
        case .cost: "$ High → Low"
        }
    }
}

/// Drill-in view for one session: its prompts with attributed costs
/// (including subagent work folded into the prompt that triggered it).
struct SessionDetailView: View {
    let session: SessionUsage
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

    private var totalCostCents: Double {
        prompts.reduce(0) { $0 + $1.costCents }
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
                Text("No prompts recorded for this session")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(sortedPrompts) { prompt in
                            PromptRowView(prompt: prompt, showSessionName: false)
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
            .help("Back to sessions")

            VStack(alignment: .leading, spacing: 2) {
                Text(session.displayName)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(MoneyFormat.dollarsFromCents(totalCostCents))
                .font(.callout.monospacedDigit().weight(.semibold))
                .help("Total for the listed prompts, including subagent work")
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        parts.append(prompts.count == 1 ? "1 prompt" : "\(prompts.count) prompts")
        if let location = session.locationSubtitle {
            parts.append(location)
        }
        return parts.joined(separator: " · ")
    }
}
