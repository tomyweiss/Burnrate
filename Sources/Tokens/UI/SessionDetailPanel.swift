import SwiftUI

struct SessionDetailPanel: View {
    let conversation: ConversationUsage
    var glassNamespace: Namespace.ID
    var onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    onBack()
                    MenuBarPanelKeeper.keepOpen()
                } label: {
                    Label("Sessions", systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)
                .glassEffect(.regular.interactive())
                .glassEffectID("session-back", in: glassNamespace)

                Spacer()

                Text("Session")
                    .font(.headline)

                Spacer()

                Color.clear.frame(width: 88, height: 1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header

                    VStack(alignment: .leading, spacing: 2) {
                        agentRow(conversation.main)
                        ForEach(conversation.subagents) { agent in
                            Divider().opacity(0.35)
                            agentRow(agent)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 16)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(conversation.displayName)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                Spacer(minLength: 8)
                Text(MoneyFormat.dollars(conversation.costDollars))
                    .font(.title3.monospacedDigit().weight(.semibold))
            }

            Text(tokenLine(
                input: conversation.inputTokens,
                output: conversation.outputTokens,
                cacheRead: conversation.cacheReadTokens,
                cacheWrite: conversation.cacheWriteTokens
            ))
            .font(.caption)
            .foregroundStyle(.secondary)

            if conversation.subagentCount > 0 {
                Text("Main + \(conversation.subagentCount) agent\(conversation.subagentCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func agentRow(_ agent: AgentUsage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(agent.displayName)
                        .font(.callout.weight(.medium))
                        .lineLimit(2)
                    if let type = agent.subagentTypeName, !agent.isMain {
                        Text(type)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer(minLength: 8)
                Text(MoneyFormat.dollars(agent.costDollars))
                    .font(.callout.monospacedDigit().weight(.semibold))
            }

            Text(tokenLine(
                input: agent.inputTokens,
                output: agent.outputTokens,
                cacheRead: agent.cacheReadTokens,
                cacheWrite: agent.cacheWriteTokens
            ))
            .font(.caption)
            .foregroundStyle(.secondary)

            if let top = agent.models.first {
                let modelText = agent.models.count > 1
                    ? "\(top) +\(agent.models.count - 1)"
                    : top
                Text(modelText)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
    }

    private func tokenLine(
        input: Int,
        output: Int,
        cacheRead: Int,
        cacheWrite: Int
    ) -> String {
        var parts = [
            "in \(TokenFormat.compact(input))",
            "out \(TokenFormat.compact(output))"
        ]
        if cacheRead > 0 {
            parts.append("cache read \(TokenFormat.compact(cacheRead))")
        }
        if cacheWrite > 0 {
            parts.append("cache write \(TokenFormat.compact(cacheWrite))")
        }
        return parts.joined(separator: " · ")
    }
}
