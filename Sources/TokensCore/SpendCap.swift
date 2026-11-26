import Foundation

/// Decides when an armed Claude Code spend cap warns and when it trips.
public enum SpendCap {
    /// Warn once when estimated spend reaches this share of the cap.
    public static let warnFraction = 0.8
    /// Time between asking agents to stop (stop hook) and stopping their processes.
    public static let graceInterval: TimeInterval = 120
    /// Time between SIGTERM and SIGKILL for processes that are still running.
    public static let killWait: TimeInterval = 10
    public static let dollarChoices: [Double] = [5, 10, 20, 30, 50, 75, 100, 150, 200, 300, 500]
    public static let defaultDollars: Double = 20

    public enum Step: Equatable, Sendable {
        case none
        case warn
        case trip
    }

    public static func step(spentCents: Double, capCents: Double, warned: Bool, tripped: Bool) -> Step {
        guard !tripped, capCents > 0 else { return .none }
        if spentCents >= capCents { return .trip }
        if !warned, spentCents >= capCents * warnFraction { return .warn }
        return .none
    }

    /// What the stop hook tells every Claude Code agent once the cap trips.
    public static func stopMessage(spentDollars: String, capDollars: String) -> String {
        """
        Burnrate spend cap reached: about \(spentDollars) of the \(capDollars) cap was spent \
        since it was armed. Stop working now and do not call any more tools. Reply with a \
        short summary of where you stopped so the user can resume later. To continue, \
        re-arm or turn off the cap in Burnrate.
        """
    }
}

/// The `PreToolUse` hook Burnrate adds to `~/.claude/settings.json`. While the flag
/// file exists, every tool call is blocked (exit 2) and Claude reads the file's text.
public enum ClaudeStopHook {
    public static let marker = "burnrate-spend-cap"

    public static func command(flagPath: String) -> String {
        let quoted = "'" + flagPath.replacingOccurrences(of: "'", with: "'\\''") + "'"
        return "f=\(quoted); [ -f \"$f\" ] || exit 0; cat \"$f\" >&2; exit 2 # \(marker)"
    }

    public static func isInstalled(in settings: [String: Any]) -> Bool {
        preToolUse(settings).contains(where: isOurs)
    }

    /// Adds the hook, replacing an older copy. Everything else is kept as is.
    public static func installing(into settings: [String: Any], flagPath: String) -> [String: Any] {
        var settings = removing(from: settings)
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        var groups = hooks["PreToolUse"] as? [Any] ?? []
        groups.append([
            "matcher": "*",
            "hooks": [
                ["type": "command", "command": command(flagPath: flagPath), "timeout": 5]
            ]
        ] as [String: Any])
        hooks["PreToolUse"] = groups
        settings["hooks"] = hooks
        return settings
    }

    /// Drops only Burnrate's hook, and the containers it leaves empty.
    public static func removing(from settings: [String: Any]) -> [String: Any] {
        guard var hooks = settings["hooks"] as? [String: Any],
              let groups = hooks["PreToolUse"] as? [Any]
        else { return settings }
        var settings = settings
        var kept: [Any] = []
        for group in groups {
            guard var dict = group as? [String: Any], let inner = dict["hooks"] as? [Any] else {
                kept.append(group)
                continue
            }
            let remaining = inner.filter { !isOurs($0) }
            if remaining.count == inner.count {
                kept.append(group)
            } else if !remaining.isEmpty {
                dict["hooks"] = remaining
                kept.append(dict)
            }
        }
        if kept.isEmpty {
            hooks.removeValue(forKey: "PreToolUse")
        } else {
            hooks["PreToolUse"] = kept
        }
        if hooks.isEmpty {
            settings.removeValue(forKey: "hooks")
        } else {
            settings["hooks"] = hooks
        }
        return settings
    }

    private static func preToolUse(_ settings: [String: Any]) -> [Any] {
        guard let hooks = settings["hooks"] as? [String: Any],
              let groups = hooks["PreToolUse"] as? [Any]
        else { return [] }
        return groups.flatMap { ($0 as? [String: Any])?["hooks"] as? [Any] ?? [] }
    }

    private static func isOurs(_ hook: Any) -> Bool {
        ((hook as? [String: Any])?["command"] as? String)?.contains(marker) == true
    }
}

/// Recognizes Claude Code CLI processes: the native installer's versioned binary
/// (`~/.local/share/claude/versions/2.1.332`), a binary named `claude` (the Claude
/// desktop app's Code sessions, Homebrew), and npm installs run by Node.
public enum ClaudeProcessMatch {
    public static func isClaudeCode(executablePath: String, arguments: [String]) -> Bool {
        let name = (executablePath as NSString).lastPathComponent
        if name == "claude" { return true }
        if executablePath.contains("/claude/versions/") { return true }
        if name == "node" || name == "bun" {
            return arguments.dropFirst().prefix(2).contains { argument in
                argument.contains("@anthropic-ai/claude-code") || (argument as NSString).lastPathComponent == "claude"
            }
        }
        return false
    }

    /// Splits a `KERN_PROCARGS2` buffer: argc, the exec path, NUL padding, then argv.
    public static func arguments(fromProcArgs bytes: [UInt8]) -> [String] {
        guard bytes.count > 4 else { return [] }
        let argc = Int(bytes[0]) | Int(bytes[1]) << 8 | Int(bytes[2]) << 16 | Int(bytes[3]) << 24
        var index = 4
        while index < bytes.count, bytes[index] != 0 { index += 1 }
        while index < bytes.count, bytes[index] == 0 { index += 1 }
        var result: [String] = []
        while result.count < argc, index < bytes.count {
            let start = index
            while index < bytes.count, bytes[index] != 0 { index += 1 }
            result.append(String(decoding: bytes[start..<index], as: UTF8.self))
            index += 1
        }
        return result
    }
}

extension SpendCap {
    /// A plan window at or past this percent counts as used up.
    public static let planLimitPercent: Double = 100

    /// The first used-up plan window, named for a notification. Nil while all have room.
    public static func usedUpLimit(_ limits: ClaudeLimits?) -> String? {
        guard let limits else { return nil }
        let windows: [(String, ClaudeLimitWindow?)] = [
            ("5-hour limit", limits.fiveHour),
            ("Weekly limit", limits.weekly),
            ("Weekly Opus limit", limits.weeklyOpus),
            ("Weekly Sonnet limit", limits.weeklySonnet)
        ]
        return windows.first { ($0.1?.percentUsed ?? 0) >= planLimitPercent }?.0
    }

    public static func planLimitStopMessage(limit: String) -> String {
        """
        Burnrate stop: the Claude plan's \(limit) is used up, and further work may be billed \
        as extra usage. Stop working now and do not call any more tools. Reply with a short \
        summary of where you stopped so the user can resume later. To continue, re-arm or \
        turn off the stop in Burnrate.
        """
    }
}
