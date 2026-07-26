import Foundation

/// Competition ranking: tied values share rank; next rank skips (1, 2, 2, 4).
public enum CompetitionRank {
    /// Returns ranks for values sorted in **descending** spend order.
    public static func ranks(spendCentsDescending values: [Int]) -> [Int] {
        guard !values.isEmpty else { return [] }
        var result: [Int] = []
        result.reserveCapacity(values.count)
        var rank = 1
        var index = 0
        while index < values.count {
            let value = values[index]
            var count = 1
            while index + count < values.count, values[index + count] == value {
                count += 1
            }
            for _ in 0..<count {
                result.append(rank)
            }
            rank += count
            index += count
        }
        return result
    }

    /// Rank a single participant among all spends (descending sort).
    public static func rank(of spendCents: Int, among allSpendCents: [Int]) -> Int {
        let sorted = allSpendCents.sorted(by: >)
        let ranks = ranks(spendCentsDescending: sorted)
        guard let index = sorted.firstIndex(of: spendCents) else { return allSpendCents.count }
        return ranks[index]
    }
}
