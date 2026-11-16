import Foundation

/// Parses one Claude Code JSONL transcript line into usage, a prompt, or a title.
public enum ClaudeTranscript {
    /// Parses one JSONL line. Never throws; malformed lines are `.ignored`.
    public static func parse(line: Data) -> ClaudeTranscriptLine {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
            return .ignored
        }
        switch object["type"] as? String {
        case "assistant":
            return usage(from: object)
        case "user":
            return prompt(from: object)
        case "custom-title":
            return title(sessionId: object["sessionId"], title: object["customTitle"])
        case "summary":
            return title(sessionId: object["sessionId"], title: object["summary"])
        default:
            return .ignored
        }
    }

    /// Keeps the last record per messageId, preserving first-seen order.
    public static func dedupe(_ records: [ClaudeUsageRecord]) -> [ClaudeUsageRecord] {
        var order: [String] = []
        var latest: [String: ClaudeUsageRecord] = [:]
        for record in records {
            if latest[record.messageId] == nil {
                order.append(record.messageId)
            }
            latest[record.messageId] = record
        }
        return order.compactMap { latest[$0] }
    }

    private static func usage(from object: [String: Any]) -> ClaudeTranscriptLine {
        guard let message = object["message"] as? [String: Any],
              let messageId = nonEmpty(message["id"]),
              let model = nonEmpty(message["model"]),
              model != "<synthetic>",
              let usage = message["usage"] as? [String: Any],
              let sessionId = nonEmpty(object["sessionId"]),
              let timestampMs = TimestampParser.shared.milliseconds(from: object["timestamp"])
        else { return .ignored }
        return .usage(ClaudeUsageRecord(
            messageId: messageId,
            timestampMs: timestampMs,
            sessionId: sessionId,
            model: model,
            inputTokens: int(usage["input_tokens"]),
            outputTokens: int(usage["output_tokens"]),
            cacheCreationTokens: int(usage["cache_creation_input_tokens"]),
            cacheCreation1hTokens: cacheCreation1hTokens(in: usage),
            cacheReadTokens: int(usage["cache_read_input_tokens"]),
            isSidechain: object["isSidechain"] as? Bool ?? false,
            cwd: nonEmpty(object["cwd"]),
            gitBranch: nonEmpty(object["gitBranch"])
        ))
    }

    private static func prompt(from object: [String: Any]) -> ClaudeTranscriptLine {
        guard object["isMeta"] as? Bool != true,
              let message = object["message"] as? [String: Any],
              (message["role"] as? String) == "user",
              let uuid = nonEmpty(object["uuid"]),
              let sessionId = nonEmpty(object["sessionId"]),
              let timestampMs = TimestampParser.shared.milliseconds(from: object["timestamp"]),
              let raw = promptText(from: message["content"])
        else { return .ignored }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("<local-command-stdout>") else { return .ignored }
        let (text, skills) = promptFields(from: trimmed)
        guard !text.isEmpty else { return .ignored }
        return .prompt(ClaudePromptRecord(
            uuid: uuid,
            sessionId: sessionId,
            timestampMs: timestampMs,
            text: text,
            skills: skills
        ))
    }

    private static func title(sessionId: Any?, title: Any?) -> ClaudeTranscriptLine {
        guard let sessionId = nonEmpty(sessionId), let title = nonEmpty(title) else { return .ignored }
        return .title(sessionId: sessionId, title: title)
    }

    /// A prompt is a string, or an array whose blocks are all text. Tool results are skipped.
    private static func promptText(from content: Any?) -> String? {
        if let text = content as? String { return text }
        guard let blocks = content as? [[String: Any]], !blocks.isEmpty else { return nil }
        var parts: [String] = []
        for block in blocks {
            if (block["type"] as? String) == "tool_result" { return nil }
            guard (block["type"] as? String) == "text", let text = block["text"] as? String else {
                return nil
            }
            parts.append(text)
        }
        return parts.joined(separator: "\n")
    }

    private static func promptFields(from text: String) -> (text: String, skills: [String]) {
        guard let command = tagBody("command-name", in: text) else {
            return (text, skillMentions(in: text))
        }
        let skill = command
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
        guard !skill.isEmpty else { return (text, skillMentions(in: text)) }
        let args = tagBody("command-args", in: text)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let promptText = args.isEmpty ? "/\(skill)" : args
        var skills = [skill]
        for mention in skillMentions(in: promptText) where !skills.contains(mention) {
            skills.append(mention)
        }
        return (promptText, skills)
    }

    private static func tagBody(_ name: String, in text: String) -> String? {
        let open = "<\(name)>"
        let close = "</\(name)>"
        guard let start = text.range(of: open),
              let end = text.range(of: close, range: start.upperBound..<text.endIndex)
        else { return nil }
        return String(text[start.upperBound..<end.lowerBound])
    }

    /// Same rule as Cursor skills: `/name` at a word boundary, but not a path like `/Users/…`.
    private static func skillMentions(in text: String) -> [String] {
        let skillRegex = #/(?:^|[\s(\["'`])/([A-Za-z][A-Za-z0-9_-]*)(?![A-Za-z0-9_/-])/#
        var seen: Set<String> = []
        var skills: [String] = []
        for match in text.matches(of: skillRegex) {
            let name = String(match.1).lowercased()
            if seen.insert(name).inserted {
                skills.append(name)
            }
        }
        return skills
    }

    private static func nonEmpty(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Absent `cache_creation` means the whole write was 5-minute. 5m = total - 1h.
    private static func cacheCreation1hTokens(in usage: [String: Any]) -> Int {
        guard let creation = usage["cache_creation"] as? [String: Any] else { return 0 }
        return int(creation["ephemeral_1h_input_tokens"])
    }

    private static func int(_ value: Any?) -> Int {
        switch value {
        case let number as NSNumber:
            return number.intValue
        case let text as String:
            return Int(text) ?? 0
        default:
            return 0
        }
    }
}

public struct ClaudeUsageRecord: Sendable, Hashable, Codable {
    public let messageId: String
    public let timestampMs: Double
    public let sessionId: String
    public let model: String
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheCreationTokens: Int
    public let cacheCreation1hTokens: Int
    public let cacheReadTokens: Int
    public let isSidechain: Bool
    public let cwd: String?
    public let gitBranch: String?

    public init(
        messageId: String,
        timestampMs: Double,
        sessionId: String,
        model: String,
        inputTokens: Int,
        outputTokens: Int,
        cacheCreationTokens: Int,
        cacheCreation1hTokens: Int,
        cacheReadTokens: Int,
        isSidechain: Bool,
        cwd: String?,
        gitBranch: String?
    ) {
        self.messageId = messageId
        self.timestampMs = timestampMs
        self.sessionId = sessionId
        self.model = model
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.cacheCreation1hTokens = cacheCreation1hTokens
        self.cacheReadTokens = cacheReadTokens
        self.isSidechain = isSidechain
        self.cwd = cwd
        self.gitBranch = gitBranch
    }
}

public struct ClaudePromptRecord: Sendable, Hashable, Codable {
    public let uuid: String
    public let sessionId: String
    public let timestampMs: Double
    public let text: String
    public let skills: [String]

    public init(
        uuid: String,
        sessionId: String,
        timestampMs: Double,
        text: String,
        skills: [String]
    ) {
        self.uuid = uuid
        self.sessionId = sessionId
        self.timestampMs = timestampMs
        self.text = text
        self.skills = skills
    }
}

public enum ClaudeTranscriptLine: Sendable, Hashable {
    case usage(ClaudeUsageRecord)
    case prompt(ClaudePromptRecord)
    case title(sessionId: String, title: String)
    case ignored
}

/// `ISO8601DateFormatter` is not thread-safe. Parsing runs off the main actor.
private final class TimestampParser: @unchecked Sendable {
    static let shared = TimestampParser()

    private let fractional: ISO8601DateFormatter
    private let plain: ISO8601DateFormatter
    private let lock = NSLock()

    init() {
        fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
    }

    func milliseconds(from value: Any?) -> Double? {
        guard let text = value as? String else { return nil }
        lock.lock()
        defer { lock.unlock() }
        guard let date = fractional.date(from: text) ?? plain.date(from: text) else { return nil }
        return date.timeIntervalSince1970 * 1000
    }
}
