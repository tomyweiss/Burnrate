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
        VStack(alignment: .leading, spacing: 16) {
            nicknameRow

            if let rank = community.rank, rank.notEnoughParticipants {
                notEnoughView(rank)
            } else if let rank = community.rank {
                heroStats(rank)
                distributionBar(rank)
                nearYouList(rank)
            } else if community.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else if let error = community.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            }

            Spacer(minLength: 0)

            Button {
                Task { await community.disableSharing() }
            } label: {
                Text("Sharing on · tap to stop")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    private var nicknameRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "hare.fill")
                .font(.caption)
                .foregroundStyle(Color.orange)

            Text(community.displayNickname)
                .font(.subheadline.weight(.medium))

            Spacer()

            Button("Shuffle") {
                community.shuffleNickname()
            }
            .font(.caption.weight(.medium))
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button("Clear") {
                community.clearNickname()
            }
            .font(.caption.weight(.medium))
            .buttonStyle(.bordered)
            .controlSize(.small)
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

    private func nearYouList(_ rank: CommunityRankResponse) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NEAR YOU")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(rank.leaderboardNear.indices, id: \.self) { index in
                let entry = rank.leaderboardNear[index]
                nearYouRow(entry)
            }
        }
    }

    private func nearYouRow(_ entry: CommunityLeaderboardEntry) -> some View {
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
