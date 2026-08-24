import Foundation

/// Normalizes Cursor chat bubble text (XML wrappers, timestamps, synthetic task pings).
public enum CursorPromptText {
    /// Cursor-injected bubble (task-finished ping), not a user prompt.
    public static func isSynthetic(text: String, isSimulated: Bool) -> Bool {
        if isSimulated { return true }
        return text.range(of: "<system_notification>", options: .caseInsensitive) != nil
    }

    /// User-visible body: `<user_query>` when present, otherwise wrappers stripped.
    public static func visible(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let inner = slice(trimmed, open: "<user_query>", close: "</user_query>") {
            return inner.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return stripTimestampTags(trimmed)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Compact list title from the visible body.
    public static func headline(_ raw: String) -> String {
        let body = visible(raw)
        let firstLine = body
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? body
        return DisplayText.sanitize(firstLine, collapseWhitespace: true)
    }

    /// Epoch milliseconds from a leading `<timestamp>…</timestamp>` tag.
    public static func timestampMs(in raw: String) -> Double? {
        guard let inner = slice(raw, open: "<timestamp>", close: "</timestamp>") else {
            return nil
        }
        return parseTimestamp(inner.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// `createdAt` JSON/ISO/epoch value, else timestamp tag in `text`.
    public static func resolvedCreatedAtMs(createdAt: String?, text: String) -> Double? {
        if let createdAt {
            let trimmed = createdAt.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, let parsed = parseCreatedAtField(trimmed) {
                return parsed
            }
        }
        return timestampMs(in: text)
    }

    // MARK: - Internals

    private static func slice(_ raw: String, open: String, close: String) -> String? {
        guard let start = raw.range(of: open, options: .caseInsensitive),
              let end = raw.range(
                of: close,
                options: .caseInsensitive,
                range: start.upperBound..<raw.endIndex
              )
        else { return nil }
        return String(raw[start.upperBound..<end.lowerBound])
    }

    private static func stripTimestampTags(_ raw: String) -> String {
        var result = raw
        while let innerStart = result.range(of: "<timestamp>", options: .caseInsensitive),
              let innerEnd = result.range(
                of: "</timestamp>",
                options: .caseInsensitive,
                range: innerStart.upperBound..<result.endIndex
              ) {
            result.removeSubrange(innerStart.lowerBound..<innerEnd.upperBound)
        }
        return result
    }

    private static let isoWithFraction = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let isoPlain = Date.ISO8601FormatStyle()

    private static func parseCreatedAtField(_ text: String) -> Double? {
        if let date = (try? Date(text, strategy: isoWithFraction))
            ?? (try? Date(text, strategy: isoPlain)) {
            return date.timeIntervalSince1970 * 1000
        }
        if let ms = Double(text), ms > 1_000_000_000_000 {
            return ms
        }
        if let seconds = Double(text), seconds > 1_000_000_000, seconds < 1_000_000_000_000 {
            return seconds * 1000
        }
        return nil
    }

    /// Parses `Thursday, Aug 6, 2026, 7:25 PM (UTC+3)`.
    private static func parseTimestamp(_ raw: String) -> Double? {
        var body = raw
        var secondsFromGMT = 0
        if let match = raw.firstMatch(of: /\(UTC(?<sign>[+-])(?<hours>\d{1,2})(?::(?<minutes>\d{2}))?\)/) {
            let sign = match.sign == "+" ? 1 : -1
            let hours = Int(match.hours) ?? 0
            let minutes = match.minutes.flatMap { Int($0) } ?? 0
            secondsFromGMT = sign * (hours * 3600 + minutes * 60)
            body = raw.replacingCharacters(in: match.range, with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: secondsFromGMT)
        formatter.dateFormat = "EEEE, MMM d, yyyy, h:mm a"
        if let date = formatter.date(from: body) {
            return date.timeIntervalSince1970 * 1000
        }
        return nil
    }
}
