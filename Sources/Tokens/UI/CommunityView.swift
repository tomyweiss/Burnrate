import SwiftUI
import TokensCore

struct CommunityView: View {
    @Bindable var community: CommunityStore

    var body: some View {
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        HStack(spacing: 6) {
            Image(systemName: "person.crop.circle")
                .font(.caption)
                .foregroundStyle(Color.orange)

            Text(community.displayNickname)
                .font(.subheadline.weight(.medium))

            Spacer()
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
        let entries = LeaderboardDedup.deduplicateNicknames(rank.leaderboardNear)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("LEADERBOARD")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("self-reported")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                if rank.participantCount > entries.count {
                    Text("Top \(entries.count) of \(rank.participantCount)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(entries.indices, id: \.self) { index in
                        leaderboardRow(entries[index])
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
