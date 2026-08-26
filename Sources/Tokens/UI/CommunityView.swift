import SwiftUI
import TokensCore

struct CommunityView: View {
    @Bindable var community: CommunityStore
    @State private var windowMode: WindowMode = .live

    private enum WindowMode: String, CaseIterable, Identifiable {
        case live
        case day

        var id: String { rawValue }

        var title: String {
            switch self {
            case .live: "Live"
            case .day: "By day"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sharingHeader
                .padding(.horizontal, 16)
                .padding(.top, 4)

            if let rank = community.rank,
               rank.rankWindow == community.selectedWindow,
               !rank.notEnoughParticipants {
                leaderboardList(rank)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            syncWindowModeFromStore()
        }
        .onChange(of: community.selectedWindow) { _, _ in
            syncWindowModeFromStore()
        }
        .task {
            community.refreshCursorDisplayName()
            await community.activateCommunity()
            await community.refreshRank()
        }
    }

    @ViewBuilder
    private var sharingHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            nicknameRow
            if windowMode == .day {
                dayNavigator
            }

            if community.needsCursorSignIn {
                signInPrompt
            } else if let rank = community.rank, rank.notEnoughParticipants {
                notEnoughView(rank)
            } else if let rank = community.rank {
                if community.rankIsStale {
                    Text("Offline — showing cached cohort data.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if rank.isProvisional {
                    Text("Today’s UTC totals are still updating.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if community.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
                heroStats(rank)
                distributionBar(rank)
            } else if community.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else if let error = community.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            }
        }
    }

    private var windowModePicker: some View {
        PillPicker(
            selection: Binding(
                get: { windowMode },
                set: { newMode in
                    windowMode = newMode
                    MenuBarPanelKeeper.keepOpen()
                    Task {
                        switch newMode {
                        case .live:
                            await community.selectWindow(.rolling24h)
                        case .day:
                            await community.selectWindow(.yesterdayUTC())
                        }
                    }
                }
            ),
            options: WindowMode.allCases.map { mode in
                PillPicker.Option(value: mode, title: mode.title)
            },
            size: .compact,
            style: .flat
        )
    }

    private var dayNavigator: some View {
        HStack(spacing: 8) {
            Button {
                MenuBarPanelKeeper.keepOpen()
                Task { await community.stepWindow(forward: false) }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.caption.weight(.semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!community.selectedWindow.canStepBackward || community.isLoading)

            Text(community.selectedWindow.displayLabel())
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)

            Button {
                MenuBarPanelKeeper.keepOpen()
                Task { await community.stepWindow(forward: true) }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!community.selectedWindow.canStepForward || community.isLoading)
        }
        .foregroundStyle(.secondary)
    }

    private func syncWindowModeFromStore() {
        windowMode = community.selectedWindow.kind == .rolling24h ? .live : .day
    }

    private var signInPrompt: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sign in to Cursor to appear on the leaderboard.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let error = community.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var nicknameRow: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "person.crop.circle")
                .font(.caption)
                .foregroundStyle(Color.orange)

            Text(community.displayNickname)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)

            Spacer(minLength: 8)

            windowModePicker
        }
    }

    private func heroStats(_ rank: CommunityRankResponse) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(rank.rankWindow.spendCaption())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(MoneyFormat.dollars(Double(rank.yourSpendCents) / 100))
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("RANK")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                if let position = rank.rank {
                    Text("#\(position) / \(rank.participantCount)")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                } else {
                    Text("—")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                }
            }
        }
    }

    private func distributionBar(_ rank: CommunityRankResponse) -> some View {
        let maxCents = max(rank.maxSpendCents ?? rank.yourSpendCents, 1)
        let yourFraction = min(max(Double(rank.yourSpendCents) / Double(maxCents), 0), 1)

        return VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.12))
                        .frame(height: 6)

                    Capsule()
                        .fill(Color.orange)
                        .frame(width: max(geo.size.width * yourFraction, 4), height: 6)

                    VStack(spacing: 2) {
                        Text("you")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.orange)
                        Rectangle()
                            .fill(Color.orange)
                            .frame(width: 2, height: 14)
                    }
                    .offset(x: geo.size.width * yourFraction - 1, y: -10)
                }
            }
            .frame(height: 28)

            HStack {
                Text("$0")
                Spacer()
                if let median = rank.medianSpendCents {
                    Text("median \(MoneyFormat.dollars(Double(median) / 100))")
                }
                Spacer()
                Text(MoneyFormat.dollars(Double(maxCents) / 100))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    private func leaderboardList(_ rank: CommunityRankResponse) -> some View {
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("LEADERBOARD")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                if rank.rankWindow.kind == .utcDay {
                    Text(rank.rankWindow.displayLabel())
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    Text("self-reported")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                if rank.participantCount > rank.leaderboardNear.count {
                    Text("Top \(rank.leaderboardNear.count) of \(rank.participantCount)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(rank.leaderboardNear.indices, id: \.self) { index in
                        leaderboardRow(rank.leaderboardNear[index])
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func leaderboardRow(_ entry: CommunityLeaderboardEntry) -> some View {
        let name = entry.nickname?.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = (name?.isEmpty == false) ? name! : "Anonymous"
        let modelLabel = CommunityModelLabel.leaderboard(entry.topModel)
        let versionLabel = entry.clientVersion?.trimmingCharacters(in: .whitespacesAndNewlines)

        return HStack(spacing: 8) {
            Text("\(entry.rank) · \(displayName) · \(MoneyFormat.dollars(Double(entry.spendCents) / 100))")
                .font(.subheadline)
                .foregroundStyle(entry.isYou ? .primary : .secondary)
                .lineLimit(1)

            Spacer(minLength: 4)

            HStack(spacing: 6) {
                if let modelLabel {
                    Text(modelLabel)
                        .font(.caption2)
                        .foregroundStyle(Color.orange.opacity(0.9))
                        .lineLimit(1)
                }

                if let versionLabel, !versionLabel.isEmpty {
                    Text(versionLabel)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            entry.isYou ? Color.orange.opacity(0.12) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
    }

    private func notEnoughView(_ rank: CommunityRankResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            heroStats(rank)
            Text("Not enough sharers yet (\(rank.participantCount)/5). Check back soon.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
