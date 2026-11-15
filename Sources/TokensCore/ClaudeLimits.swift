import Foundation

/// One Claude Code plan window from `GET https://api.anthropic.com/api/oauth/usage`.
///
/// `utilization` is already a 0–100 percent: 1.0 means 1%, not full. Confirmed
/// against community clients of that endpoint, including
/// https://github.com/FullFran/claudeops-tui/blob/main/docs/oauth-usage-endpoint.md
/// and the percent-scale fix in
/// https://github.com/Dicklesworthstone/coding_agent_account_manager/commit/65f1e175bc0167131657cdbcd3a42c94ad83a3e9
public struct ClaudeLimitWindow: Sendable, Hashable {
    public let percentUsed: Double
    public let resetsAt: Date?

    public init(percentUsed: Double, resetsAt: Date?) {
        self.percentUsed = percentUsed
        self.resetsAt = resetsAt
    }
}

/// The 5-hour session window and the overall 7-day window.
/// Model-scoped keys (`seven_day_sonnet`, `seven_day_opus`, …) are ignored.
public struct ClaudeLimits: Sendable, Hashable {
    public let fiveHour: ClaudeLimitWindow?
    public let weekly: ClaudeLimitWindow?

    public init(fiveHour: ClaudeLimitWindow?, weekly: ClaudeLimitWindow?) {
        self.fiveHour = fiveHour
        self.weekly = weekly
    }

    /// Nil when neither headline window is present. A missing `seven_day` still
    /// returns the 5-hour window. `resets_at` may be absent, null, or ISO-8601
    /// with or without fractional seconds.
    public static func parse(json: [String: Any]) -> ClaudeLimits? {
        let fiveHour = window(json["five_hour"])
        let weekly = window(json["seven_day"])
        guard fiveHour != nil || weekly != nil else { return nil }
        return ClaudeLimits(fiveHour: fiveHour, weekly: weekly)
    }

    private static func window(_ value: Any?) -> ClaudeLimitWindow? {
        guard let object = value as? [String: Any],
              let percent = percent(object["utilization"])
        else { return nil }
        return ClaudeLimitWindow(percentUsed: percent, resetsAt: resetDate(object["resets_at"]))
    }

    private static func percent(_ value: Any?) -> Double? {
        guard let value, !(value is Bool), let number = value as? NSNumber else { return nil }
        let double = number.doubleValue
        guard double.isFinite, double >= 0 else { return nil }
        return double
    }

    private static func resetDate(_ value: Any?) -> Date? {
        guard let string = value as? String else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }
}

/// Access token inside the `Claude Code-credentials` Keychain item.
///
/// The payload is JSON `{"claudeAiOauth":{"accessToken":"…","expiresAt":<ms>}}`.
/// `expiresAt` is epoch milliseconds, as written by current Claude Code
/// (https://github.com/XueshiQiao/CCSwitcher/blob/main/ARCHITECTURE.md).
public enum ClaudeOAuthToken: Equatable, Sendable {
    case valid(accessToken: String)
    case expired
    case unreadable

    public static func extract(from data: Data, now: Date) -> ClaudeOAuthToken {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let accessToken = oauth["accessToken"] as? String,
              !accessToken.isEmpty,
              let expiresAt = expires(oauth["expiresAt"])
        else { return .unreadable }
        if expiresAt <= now { return .expired }
        return .valid(accessToken: accessToken)
    }

    private static func expires(_ value: Any?) -> Date? {
        guard let value, !(value is Bool), let number = value as? NSNumber else { return nil }
        let raw = number.doubleValue
        guard raw.isFinite, raw > 0 else { return nil }
        return Date(timeIntervalSince1970: raw / 1000)
    }
}
