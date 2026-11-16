public struct ClaudeModelPrice: Sendable, Hashable {
    public let inputPerMTok: Double
    public let outputPerMTok: Double
    public let cacheWritePerMTok: Double
    public let cacheWrite1hPerMTok: Double
    public let cacheReadPerMTok: Double

    public init(
        inputPerMTok: Double,
        outputPerMTok: Double,
        cacheWritePerMTok: Double,
        cacheWrite1hPerMTok: Double,
        cacheReadPerMTok: Double
    ) {
        self.inputPerMTok = inputPerMTok
        self.outputPerMTok = outputPerMTok
        self.cacheWritePerMTok = cacheWritePerMTok
        self.cacheWrite1hPerMTok = cacheWrite1hPerMTok
        self.cacheReadPerMTok = cacheReadPerMTok
    }
}

public enum ClaudePricing {
    /// Estimated cost in cents, nil when the model has no price.
    public static func costCents(for record: ClaudeUsageRecord) -> Double? {
        guard let price = price(for: record.model) else { return nil }
        let cacheTotal = max(0, record.cacheCreationTokens)
        let cache1h = min(max(0, record.cacheCreation1hTokens), cacheTotal)
        let cache5m = cacheTotal - cache1h
        let dollars = (
            Double(record.inputTokens) * price.inputPerMTok
                + Double(record.outputTokens) * price.outputPerMTok
                + Double(cache5m) * price.cacheWritePerMTok
                + Double(cache1h) * price.cacheWrite1hPerMTok
                + Double(record.cacheReadTokens) * price.cacheReadPerMTok
        ) / 1_000_000
        return dollars * 100
    }

    public static func price(for model: String) -> ClaudeModelPrice? {
        var key = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let alias = aliases[key] {
            key = alias
        }
        if let match = key.firstMatch(of: #/-\d{8}$/#) {
            key.removeSubrange(match.range)
        }
        return prices.first { key == $0.id || key.hasPrefix($0.id + "-") }?.price
    }

    private static let aliases = [
        "opus": "claude-opus-5-5",
        "sonnet": "claude-sonnet-5-5",
        "fable": "claude-fable-5-2",
        "haiku": "claude-haiku-5-5"
    ]

    // API list prices checked 2026-11-15 at https://platform.claude.com/docs/en/about-claude/pricing. 5-minute and 1-hour cache writes are the published columns.
    // claude-haiku-5-5 uses the published rate for prompts up to 100,000 tokens.
    private static let prices: [(id: String, price: ClaudeModelPrice)] = [
        ("claude-fable-5-2", ClaudeModelPrice(inputPerMTok: 8, outputPerMTok: 40, cacheWritePerMTok: 10, cacheWrite1hPerMTok: 16, cacheReadPerMTok: 0.20)),
        ("claude-opus-5-5", ClaudeModelPrice(inputPerMTok: 4, outputPerMTok: 20, cacheWritePerMTok: 5, cacheWrite1hPerMTok: 8, cacheReadPerMTok: 0.20)),
        ("claude-opus-5", ClaudeModelPrice(inputPerMTok: 5, outputPerMTok: 25, cacheWritePerMTok: 6.25, cacheWrite1hPerMTok: 10, cacheReadPerMTok: 0.50)),
        ("claude-sonnet-5-5", ClaudeModelPrice(inputPerMTok: 2, outputPerMTok: 10, cacheWritePerMTok: 2.50, cacheWrite1hPerMTok: 4, cacheReadPerMTok: 0.10)),
        ("claude-sonnet-5", ClaudeModelPrice(inputPerMTok: 2, outputPerMTok: 10, cacheWritePerMTok: 2.50, cacheWrite1hPerMTok: 4, cacheReadPerMTok: 0.20)),
        ("claude-haiku-5-5", ClaudeModelPrice(inputPerMTok: 0.10, outputPerMTok: 0.50, cacheWritePerMTok: 0.125, cacheWrite1hPerMTok: 0.20, cacheReadPerMTok: 0.01)),
        ("claude-haiku-4-5", ClaudeModelPrice(inputPerMTok: 1, outputPerMTok: 5, cacheWritePerMTok: 1.25, cacheWrite1hPerMTok: 2, cacheReadPerMTok: 0.10))
    ].sorted { $0.id.count > $1.id.count }
}
