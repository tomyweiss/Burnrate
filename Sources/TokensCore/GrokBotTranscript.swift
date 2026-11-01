import Foundation

/// Parses Grok Bot's local roster and transcript replicas, and links billed
/// `sand-subagent-…` tasks back to the agent that ran them.
public enum GrokBotTranscript {
    public struct Prompt: Sendable, Equatable {
        public let id: String
        public let text: String
        public let timestampMs: Double
    }

    /// A sand task belongs to an agent when every one of its billed events
    /// lands within this long of that same agent's own events.
    public static let linkWindowMs: Double = 10 * 60 * 1000

    public static func agentNames(fromRosterJSON data: Data) -> [String: String] {
        guard let rows = rows(in: data) else { return [:] }
        var names: [String: String] = [:]
        for row in rows {
            guard let id = row["id"] as? String else { continue }
            let name = (row["name"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !id.isEmpty, !name.isEmpty else { continue }
            names[id] = name
        }
        return names
    }

    public static func prompts(fromTranscriptJSON data: Data) -> [Prompt] {
        guard let entries = entries(in: data) else { return [] }
        var prompts: [Prompt] = []
        for entry in entries {
            guard (entry["kind"] as? String) == "message",
                  (entry["role"] as? String) == "user",
                  let raw = entry["content"] as? String,
                  let id = entry["id"] as? String
            else { continue }
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, !text.isEmpty, let timestampMs = milliseconds(entry["timestampMs"]) else {
                continue
            }
            prompts.append(Prompt(id: id, text: text, timestampMs: timestampMs))
        }
        return prompts.sorted {
            if $0.timestampMs != $1.timestampMs { return $0.timestampMs < $1.timestampMs }
            return $0.id < $1.id
        }
    }

    /// `sand-subagent-<uuid>` → parent agent id, including ids embedded in a
    /// stringified tool payload rather than a real JSON object.
    public static func subagentParents(in text: String) -> [String: String] {
        let idPattern = #/sand-subagent-([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})/#
        let parentPattern = #/parentAgentId\\?"\s*:\s*\\?"([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})/#
        var parents: [String: String] = [:]
        for match in text.matches(of: idPattern) {
            let sandID = "sand-subagent-\(match.1)"
            guard parents[sandID] == nil else { continue }
            let start = text.index(
                match.range.lowerBound,
                offsetBy: -300,
                limitedBy: text.startIndex
            ) ?? text.startIndex
            let end = text.index(
                match.range.upperBound,
                offsetBy: 300,
                limitedBy: text.endIndex
            ) ?? text.endIndex
            guard let parent = text[start..<end].firstMatch(of: parentPattern) else { continue }
            let parentID = String(parent.1)
            guard !parentID.isEmpty, parentID != sandID else { continue }
            parents[sandID] = parentID
        }
        return parents
    }

    public static func mentionedSubagentIDs(in text: String) -> Set<String> {
        let idPattern = #/sand-subagent-([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})/#
        var ids: Set<String> = []
        for match in text.matches(of: idPattern) {
            ids.insert("sand-subagent-\(match.1)")
        }
        return ids
    }

    /// Links each sand task to one Grok Bot agent. A task stays unlinked when
    /// any of its events is outside the window, or when its events point at
    /// different agents.
    public static func linkSubagents(
        events: [(conversationId: String, timestampMs: Double)],
        agentIds: Set<String>,
        windowMs: Double = linkWindowMs
    ) -> [String: String] {
        let agentEvents = events.filter {
            agentIds.contains($0.conversationId) && !$0.conversationId.hasPrefix("sand-subagent-")
        }
        let sandIDs = Set(events.map(\.conversationId).filter { $0.hasPrefix("sand-subagent-") })
        var parents: [String: String] = [:]
        for sandID in sandIDs {
            let stamps = events.filter { $0.conversationId == sandID }
            guard !stamps.isEmpty else { continue }
            var agreed: String?
            var consistent = true
            for stamp in stamps {
                guard let nearest = nearestAgent(
                    to: stamp.timestampMs,
                    agentEvents: agentEvents,
                    windowMs: windowMs
                ), nearest != sandID else {
                    consistent = false
                    break
                }
                if let agreed, agreed != nearest {
                    consistent = false
                    break
                }
                agreed = nearest
            }
            if consistent, let agreed {
                parents[sandID] = agreed
            }
        }
        return parents
    }

    private static func nearestAgent(
        to timestampMs: Double,
        agentEvents: [(conversationId: String, timestampMs: Double)],
        windowMs: Double
    ) -> String? {
        var bestDelta = windowMs + 1
        var bestID: String?
        var tied = false
        for event in agentEvents {
            let delta = abs(event.timestampMs - timestampMs)
            guard delta <= windowMs else { continue }
            if bestID == nil || delta < bestDelta - 0.5 {
                bestDelta = delta
                bestID = event.conversationId
                tied = false
            } else if abs(delta - bestDelta) <= 0.5, event.conversationId != bestID {
                tied = true
            }
        }
        return tied ? nil : bestID
    }

    private static func rows(in data: Data) -> [[String: Any]]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = root["value"] as? [String: Any]
        else { return nil }
        return value["rows"] as? [[String: Any]]
    }

    private static func entries(in data: Data) -> [[String: Any]]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = root["value"] as? [String: Any]
        else { return nil }
        return value["entries"] as? [[String: Any]]
    }

    private static func milliseconds(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber:
            return number.doubleValue
        case let text as String:
            return Double(text)
        default:
            return nil
        }
    }
}
