import SwiftUI
import TokensCore

struct CommunityView: View {
    @Bindable var community: CommunityStore

    var body: some View {
        Group {
            if community.isSharing {
                sharingContent
            } else {
                lockedContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            community.refreshCursorDisplayName()
            if community.isSharing {
                await community.refreshRank()
            }
        }
    }

    // MARK: - Locked

    private var lockedContent: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            Image(systemName: "lock.fill")
                .font(.system(size: 28))
                .foregroundStyle(Color.orange)
                .frame(width: 52, height: 52)
                .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text("Share to see the cohort")
                .font(.title3.weight(.semibold))
                .padding(.top, 20)

            Text("Upload anonymous 24h spend + model mix. No personal info. You only see others if you share.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.top, 8)

            Button {
                Task { await community.enableSharing() }
            } label: {
                Text("Enable sharing")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.orange, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.top, 24)

            Spacer()

            Text("Turn off anytime — your data is deleted.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 16)
        }
    }

    // MARK: - Sharing

    private var sharingContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            sharingHeader
                .padding(.horizontal, 16)
                .padding(.top, 4)

            if let rank = community.rank, !rank.notEnoughParticipants {
                leaderboardList(rank)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                Spacer(minLength: 0)
            }

            sharingFooterButton
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var sharingHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            nicknameRow

            if let rank = community.rank, rank.notEnoughParticipants {
                notEnoughView(rank)
            } else if let rank = community.rank {
                if community.rankIsStale {
                    Text("Offline — showing cached cohort data.")
                        .font(.caption)
                        .foregroundStyle(.orange)
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

    private var sharingFooterButton: some View {
        Button {
            Task { await community.disableSharing() }
        } label: {
            Text("Sharing on · tap to stop")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private var nicknameRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: nicknameIcon)
                    .font(.caption)
                    .foregroundStyle(Color.orange)

                Text(community.displayNickname)
                    .font(.subheadline.weight(.medium))

                if community.nicknameSource == .random {
                    Button {
                        community.shuffleNickname()
                    } label: {
                        Image(systemName: "shuffle")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.mini)
                    .help("Shuffle nickname")
                }

                Spacer()
            }

            Picker("Display name", selection: Binding(
                get: { community.nicknameSource },
                set: { newSource in
                    guard newSource != community.nicknameSource else { return }
                    switch newSource {
                    case .cursor: community.useCursorName()
                    case .random: community.shuffleNickname()
                    case .anonymous: community.useAnonymous()
                    }
                }
            )) {
                if community.canUseCursorName, let cursorName = community.cursorDisplayName {
                    Text("Cursor · \(cursorName)").tag(CommunityNicknameSource.cursor)
                }
                Text("Random").tag(CommunityNicknameSource.random)
                Text("Anonymous").tag(CommunityNicknameSource.anonymous)
            }
            .pickerStyle(.segmented)
            .disabled(!community.canUseCursorName && community.nicknameSource == .cursor)
        }
    }

    private var nicknameIcon: String {
        switch community.nicknameSource {
        case .cursor: "person.crop.circle"
        case .random: "hare.fill"
        case .anonymous: "eye.slash"
        }
    }

    private func heroStats(_ rank: CommunityRankResponse) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("24H SPEND")
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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("LEADERBOARD")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
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

        return HStack {
            Text("\(entry.rank) · \(displayName) · \(MoneyFormat.dollars(Double(entry.spendCents) / 100))")
                .font(.subheadline)
                .foregroundStyle(entry.isYou ? .primary : .secondary)
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
