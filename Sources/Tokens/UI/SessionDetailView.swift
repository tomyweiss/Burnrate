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

private enum SessionDetailTab: String, CaseIterable, Identifiable {
    case prompts
    case subagents

    var id: String { rawValue }

    var title: String {
        switch self {
        case .prompts: "Prompts"
        case .subagents: "Subagents"
        }
    }
}

/// Drill-in view for one session: prompts and (when present) child subagents.
struct SessionDetailView: View {
    let session: SessionUsage
    let prompts: [PromptUsage]
    let subagents: [SessionUsage]
    let windowCostCents: Double
    let onBack: () -> Void
    var onOpenSubagent: ((SessionUsage) -> Void)? = nil

    @AppStorage("sessionPromptSort") private var sortRaw = SessionPromptSort.newest.rawValue
    @State private var detailTab: SessionDetailTab = .prompts
    @Environment(\.blurSensitiveContent) private var blurSensitiveContent

    private var showsSubagentTabs: Bool { session.hasSubagents }

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

    private var sortedSubagents: [SessionUsage] {
        switch sort.wrappedValue {
        case .newest:
            subagents.sorted {
                $0.lastTimestampMs == $1.lastTimestampMs
                    ? $0.ownCostCents > $1.ownCostCents
                    : $0.lastTimestampMs > $1.lastTimestampMs
            }
        case .cost:
            subagents.sorted {
                $0.ownCostCents == $1.ownCostCents
                    ? $0.lastTimestampMs > $1.lastTimestampMs
                    : $0.ownCostCents > $1.ownCostCents
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            if showsSubagentTabs {
                Picker("Detail", selection: $detailTab) {
                    ForEach(SessionDetailTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .onChange(of: detailTab) { _, _ in
                    MenuBarPanelKeeper.keepOpen()
                }
            }

            if !showsSubagentTabs || detailTab == .prompts {
                promptsToolbar
                promptsBody
            } else {
                subagentsToolbar
                subagentsBody
            }
        }
        .onAppear {
            if !showsSubagentTabs {
                detailTab = .prompts
            }
        }
    }

    private var promptsToolbar: some View {
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
    }

    private var subagentsToolbar: some View {
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
    }

    @ViewBuilder
    private var promptsBody: some View {
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

    @ViewBuilder
    private var subagentsBody: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                subagentCostSummary
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)

                ForEach(sortedSubagents) { child in
                    SessionRowView(
                        session: child.withDisplayedCost(child.ownCostCents),
                        windowCostCents: max(windowCostCents, session.costCents),
                        showModelChips: true,
                        showShareBar: true,
                        showLocationSubtitle: false,
                        onOpen: {
                            onOpenSubagent?(child)
                        }
                    )
                    Divider().opacity(0.35)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
    }

    private var subagentCostSummary: some View {
        let subagentTotal = subagents.reduce(0.0) { $0 + $1.ownCostCents }
        return VStack(alignment: .leading, spacing: 4) {
            Text("Own \(MoneyFormat.dollarsFromCents(session.ownCostCents)) · Subagents \(MoneyFormat.dollarsFromCents(subagentTotal)) · Total \(MoneyFormat.dollarsFromCents(session.costCents))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Text(subagents.count == 1 ? "1 subagent" : "\(subagents.count) subagents")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
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
            .help(session.isSubagent ? "Back to parent" : "Back to sessions")

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if session.isSubagent {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Subagent")
                    }
                    Text(session.displayName)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .privacyBlurred(blurSensitiveContent)
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(MoneyFormat.dollarsFromCents(headerCostCents))
                .font(.callout.monospacedDigit().weight(.semibold))
                .help(headerCostHelp)
        }
    }

    private var headerCostCents: Double {
        if showsSubagentTabs, detailTab == .prompts {
            return prompts.reduce(0) { $0 + $1.costCents }
        }
        return session.costCents
    }

    private var headerCostHelp: String {
        if session.isSubagent {
            return "Cost for this subagent"
        }
        if session.hasSubagents {
            return "Total including subagents"
        }
        return "Total for the listed prompts, including subagent work"
    }

    private var subtitle: String {
        var parts: [String] = []
        if showsSubagentTabs, detailTab == .subagents {
            parts.append(subagents.count == 1 ? "1 subagent" : "\(subagents.count) subagents")
        } else {
            parts.append(prompts.count == 1 ? "1 prompt" : "\(prompts.count) prompts")
        }
        if let location = session.locationSubtitle {
            parts.append(location)
        }
        return parts.joined(separator: " · ")
    }
}

private extension SessionUsage {
    /// Row display helper: show a specific cost (e.g. own cost) without mutating hierarchy.
    func withDisplayedCost(_ cents: Double) -> SessionUsage {
        SessionUsage(
            conversationId: conversationId,
            name: name,
            workspaceName: workspaceName,
            isCloud: isCloud,
            isArchived: isArchived,
            repoName: repoName,
            branchName: branchName,
            ownCostCents: ownCostCents,
            costCents: cents,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheReadTokens: cacheReadTokens,
            cacheWriteTokens: cacheWriteTokens,
            eventCount: eventCount,
            lastTimestampMs: lastTimestampMs,
            models: models,
            parentConversationId: parentConversationId,
            childConversationIds: childConversationIds
        )
    }
}
