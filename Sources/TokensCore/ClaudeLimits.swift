import Foundation

/// One Claude Code plan window from `GET https://api.anthropic.com/api/oauth/usage`.
///
/// `utilization` is already a 0–100 percent: 1.0 means 1%, not full. Confirmed
/// against community clients of that endpoint, including
/// https://github.com/FullFran/claudeops-tui/blob/main/docs/oauth-usage-endpoint.md
/// and the percent-scale fix in
/// https://github.com/Dicklesworthstone/coding_agent_account_manager/commit/65f1e175bc0167131657cdbcd3a42c94ad83a3e9
public struct ClaudeLimitWindow: Sendable, Hashable, Codable {
    public let percentUsed: Double
    public let resetsAt: Date?

    public init(percentUsed: Double, resetsAt: Date?) {
        self.percentUsed = percentUsed
        self.resetsAt = resetsAt
    }
}

/// Pay-as-you-go credit pool from `extra_usage`. Amounts are major units
/// (dollars). `percentUsed` is nil when the payload has no monthly limit.
public struct ClaudeExtraUsage: Sendable, Hashable, Codable {
    public let percentUsed: Double?
    public let usedDollars: Double?
    public let monthlyLimitDollars: Double?

    public init(percentUsed: Double?, usedDollars: Double?, monthlyLimitDollars: Double?) {
        self.percentUsed = percentUsed
        self.usedDollars = usedDollars
        self.monthlyLimitDollars = monthlyLimitDollars
    }

    /// `$12.40 of $50` when both amounts are known. Whole dollars drop the cents.
    public var amountDetail: String? {
        guard let usedDollars, let monthlyLimitDollars else { return nil }
        return "\(Self.money(usedDollars)) of \(Self.money(monthlyLimitDollars))"
    }

    private static func money(_ dollars: Double) -> String {
        let cents = (dollars * 100).rounded()
        guard cents.isFinite else { return "$0" }
        if cents.truncatingRemainder(dividingBy: 100) == 0 {
            return String(format: "$%.0f", cents / 100)
        }
        return String(format: "$%.2f", cents / 100)
    }
}

/// The 5-hour session window, the overall 7-day window, and the optional
/// per-model weekly windows.
public struct ClaudeLimits: Sendable, Hashable, Codable {
    public let fiveHour: ClaudeLimitWindow?
    public let weekly: ClaudeLimitWindow?
    public let weeklyOpus: ClaudeLimitWindow?
    public let weeklySonnet: ClaudeLimitWindow?
    public let extraUsage: ClaudeExtraUsage?

    public init(
        fiveHour: ClaudeLimitWindow?,
        weekly: ClaudeLimitWindow?,
        weeklyOpus: ClaudeLimitWindow? = nil,
        weeklySonnet: ClaudeLimitWindow? = nil,
        extraUsage: ClaudeExtraUsage? = nil
    ) {
        self.fiveHour = fiveHour
        self.weekly = weekly
        self.weeklyOpus = weeklyOpus
        self.weeklySonnet = weeklySonnet
        self.extraUsage = extraUsage
    }

    /// Nil when every bucket is absent. A missing `seven_day` still returns the
    /// other windows. `resets_at` may be absent, null, or ISO-8601 with or
    /// without fractional seconds.
    ///
    /// `seven_day_opus` and `seven_day_sonnet` use the same `{utilization, resets_at}`
    /// object as `seven_day`, and are null on plans without that quota.
    /// `limits` is a newer list of `{kind, percent, resets_at}`; its `session`
    /// and `weekly_all` entries stand in when `five_hour` or `seven_day` is null.
    /// `extra_usage` is present only when `is_enabled` is true. `used_credits`
    /// and `monthly_limit` are minor units (cents when `decimal_places` is
    /// missing or 2); `utilization` is already a 0–100 percent and is ignored
    /// when `monthly_limit` is null or not positive. Other keys are ignored.
    /// https://github.com/FullFran/claudeops-tui/blob/main/docs/oauth-usage-endpoint.md
    /// https://github.com/Maciek-roboblog/Claude-Code-Usage-Monitor/issues/202
    /// https://caleb.software/posts/claude-usage-api.html
    /// https://github.com/projectvelox/claude-usage-widget/commit/d8947c44004b45b1620f3485ef5c494bf6313963
    /// https://github.com/NousResearch/hermes-agent/pull/94883
    public static func parse(json: [String: Any]) -> ClaudeLimits? {
        let fiveHour = window(json["five_hour"]) ?? limitEntry(json["limits"], kind: "session")
        let weekly = window(json["seven_day"]) ?? limitEntry(json["limits"], kind: "weekly_all")
        let weeklyOpus = window(json["seven_day_opus"])
        let weeklySonnet = window(json["seven_day_sonnet"])
        let extra = extraUsage(json["extra_usage"])
        guard fiveHour != nil || weekly != nil || weeklyOpus != nil || weeklySonnet != nil || extra != nil else {
            return nil
        }
        return ClaudeLimits(
            fiveHour: fiveHour,
            weekly: weekly,
            weeklyOpus: weeklyOpus,
            weeklySonnet: weeklySonnet,
            extraUsage: extra
        )
    }

    /// `decimal_places` selects the minor-unit scale (2 → cents). Absent or
    /// unusable values default to cents, matching live captures that omit it.
    private static func extraUsage(_ value: Any?) -> ClaudeExtraUsage? {
        guard let object = value as? [String: Any], object["is_enabled"] as? Bool == true else { return nil }
        let scale = minorUnitScale(object["decimal_places"])
        let used = majorUnits(object["used_credits"], scale: scale)
        let limit = majorUnits(object["monthly_limit"], scale: scale)
        let hasLimit = (limit ?? 0) > 0
        return ClaudeExtraUsage(
            percentUsed: hasLimit ? percent(object["utilization"]) : nil,
            usedDollars: used,
            monthlyLimitDollars: hasLimit ? limit : nil
        )
    }

    private static func minorUnitScale(_ value: Any?) -> Double {
        guard let value, !(value is Bool), let number = value as? NSNumber else { return 100 }
        let raw = number.doubleValue
        guard raw.isFinite, raw >= 0, raw <= 6, raw == raw.rounded() else { return 100 }
        return pow(10, raw)
    }

    private static func majorUnits(_ value: Any?, scale: Double) -> Double? {
        guard scale > 0, let value, !(value is Bool), let number = value as? NSNumber else { return nil }
        let raw = number.doubleValue
        guard raw.isFinite, raw >= 0 else { return nil }
        return raw / scale
    }

    private static func window(_ value: Any?) -> ClaudeLimitWindow? {
        guard let object = value as? [String: Any],
              let percent = percent(object["utilization"])
        else { return nil }
        return ClaudeLimitWindow(percentUsed: percent, resetsAt: resetDate(object["resets_at"]))
    }

    private static func limitEntry(_ value: Any?, kind: String) -> ClaudeLimitWindow? {
        guard let entries = value as? [[String: Any]],
              let entry = entries.first(where: { $0["kind"] as? String == kind }),
              let percent = percent(entry["percent"])
        else { return nil }
        return ClaudeLimitWindow(percentUsed: percent, resetsAt: resetDate(entry["resets_at"]))
    }

    private static func percent(_ value: Any?) -> Double? {
        guard let value, !(value is Bool), let number = value as? NSNumber else { return nil }
        let double = number.doubleValue
        guard double.isFinite, double >= 0 else { return nil }
        return double
    }

    /// `ISO8601DateFormatter` keeps only milliseconds, so `.528743` would become
    /// `.528`. The fraction is applied after the whole-second parse.
    private static func resetDate(_ value: Any?) -> Date? {
        guard let string = value as? String else { return nil }
        if let precise = resetDatePreservingFraction(string) { return precise }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }

    private static func resetDatePreservingFraction(_ string: String) -> Date? {
        let wholeString: String
        let fraction: Double
        if let dot = string.firstIndex(of: "."),
           let zone = string[string.index(after: dot)...].firstIndex(where: { $0 == "Z" || $0 == "z" || $0 == "+" || $0 == "-" }) {
            let digits = string[string.index(after: dot)..<zone]
            guard !digits.isEmpty, digits.allSatisfy(\.isNumber), let numer = Double(digits) else { return nil }
            fraction = numer / pow(10, Double(digits.count))
            var stripped = string
            stripped.removeSubrange(dot..<zone)
            wholeString = stripped
        } else if string.contains(".") {
            return nil
        } else {
            wholeString = string
            fraction = 0
        }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        guard let whole = plain.date(from: wholeString) else { return nil }
        guard fraction > 0 else { return whole }
        return Date(timeIntervalSince1970: whole.timeIntervalSince1970 + fraction)
    }
}

/// Access token inside the `Claude Code-credentials` Keychain item.
///
/// The payload is JSON `{"claudeAiOauth":{"accessToken":"…","expiresAt":<ms>}}`.
/// `expiresAt` is epoch milliseconds, as written by current Claude Code
/// (https://github.com/XueshiQiao/CCSwitcher/blob/main/ARCHITECTURE.md).
/// A signed-out login keeps the item with an empty `accessToken`.
public enum ClaudeOAuthToken: Equatable, Sendable {
    case valid(accessToken: String)
    case expired
    case signedOut
    case unreadable

    public static func extract(from data: Data, now: Date) -> ClaudeOAuthToken {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let accessToken = oauth["accessToken"] as? String
        else { return .unreadable }
        if accessToken.isEmpty { return .signedOut }
        guard let expiresAt = expires(oauth["expiresAt"]) else { return .unreadable }
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

/// Renewing the `claudeAiOauth` login the way Claude Code does, so the Keychain
/// item stays usable by both apps. Claude Code desktop passes its own token to
/// the CLI through the environment and never renews this item, so it goes stale.
public enum ClaudeOAuthRefresh {
    public static let tokenURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
    public static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"

    public static func refreshToken(in data: Data) -> String? {
        guard let oauth = oauth(in: data),
              let token = oauth["refreshToken"] as? String,
              !token.isEmpty
        else { return nil }
        return token
    }

    /// JSON body for the token endpoint, or nil when the item has no refresh token.
    public static func requestBody(from data: Data) -> Data? {
        guard let oauth = oauth(in: data), let token = refreshToken(in: data) else { return nil }
        var body: [String: Any] = [
            "grant_type": "refresh_token",
            "refresh_token": token,
            "client_id": clientID,
        ]
        if let scopes = oauth["scopes"] as? [String], !scopes.isEmpty {
            body["scope"] = scopes.joined(separator: " ")
        }
        return try? JSONSerialization.data(withJSONObject: body)
    }

    /// The Keychain payload with the renewed tokens merged in. Every other field,
    /// including `mcpOAuth`, is kept. A response without `refresh_token` keeps the old one.
    public static func merge(response: Data, into data: Data, now: Date) -> Data? {
        guard var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var oauth = json["claudeAiOauth"] as? [String: Any],
              let reply = try? JSONSerialization.jsonObject(with: response) as? [String: Any],
              let accessToken = reply["access_token"] as? String, !accessToken.isEmpty,
              let expiresIn = seconds(reply["expires_in"])
        else { return nil }
        let nowMs = (now.timeIntervalSince1970 * 1000).rounded()
        oauth["accessToken"] = accessToken
        oauth["expiresAt"] = Int64(nowMs + expiresIn * 1000)
        if let refresh = reply["refresh_token"] as? String, !refresh.isEmpty {
            oauth["refreshToken"] = refresh
        }
        if let refreshExpiresIn = seconds(reply["refresh_token_expires_in"]) {
            oauth["refreshTokenExpiresAt"] = Int64(nowMs + refreshExpiresIn * 1000)
        }
        if let scope = reply["scope"] as? String, !scope.isEmpty {
            oauth["scopes"] = scope.split(separator: " ").map(String.init)
        }
        json["claudeAiOauth"] = oauth
        return try? JSONSerialization.data(withJSONObject: json)
    }

    private static func oauth(in data: Data) -> [String: Any]? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["claudeAiOauth"] as? [String: Any]
    }

    private static func seconds(_ value: Any?) -> Double? {
        guard let value, !(value is Bool), let number = value as? NSNumber else { return nil }
        let raw = number.doubleValue
        guard raw.isFinite, raw > 0 else { return nil }
        return raw
    }
}
