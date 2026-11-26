import Foundation
import Testing
import TokensCore

@Test func spendCapStepsThroughWarnAndTrip() {
    #expect(SpendCap.step(spentCents: 100, capCents: 2000, warned: false, tripped: false) == .none)
    #expect(SpendCap.step(spentCents: 1600, capCents: 2000, warned: false, tripped: false) == .warn)
    #expect(SpendCap.step(spentCents: 1700, capCents: 2000, warned: true, tripped: false) == .none)
    #expect(SpendCap.step(spentCents: 2000, capCents: 2000, warned: true, tripped: false) == .trip)
    #expect(SpendCap.step(spentCents: 2500, capCents: 2000, warned: false, tripped: false) == .trip)
    #expect(SpendCap.step(spentCents: 9000, capCents: 2000, warned: true, tripped: true) == .none)
    #expect(SpendCap.step(spentCents: 10, capCents: 0, warned: false, tripped: false) == .none)
}

@Test func stopHookInstallKeepsOtherHooksAndIsIdempotent() throws {
    let existing: [String: Any] = [
        "model": "opus",
        "hooks": [
            "PreToolUse": [
                ["matcher": "Bash", "hooks": [["type": "command", "command": "rtk hook"]]]
            ],
            "Stop": [["hooks": [["type": "command", "command": "say done"]]]]
        ]
    ]
    let once = ClaudeStopHook.installing(into: existing, flagPath: "/tmp/flag")
    let twice = ClaudeStopHook.installing(into: once, flagPath: "/tmp/flag")
    #expect(ClaudeStopHook.isInstalled(in: twice))
    #expect(twice["model"] as? String == "opus")
    let hooks = try #require(twice["hooks"] as? [String: Any])
    let pre = try #require(hooks["PreToolUse"] as? [[String: Any]])
    #expect(pre.count == 2)
    #expect(hooks["Stop"] != nil)

    let removed = ClaudeStopHook.removing(from: twice)
    #expect(!ClaudeStopHook.isInstalled(in: removed))
    let removedHooks = try #require(removed["hooks"] as? [String: Any])
    #expect((removedHooks["PreToolUse"] as? [Any])?.count == 1)
    #expect(removedHooks["Stop"] != nil)
}

@Test func stopHookRemovalDropsEmptyContainers() {
    let installed = ClaudeStopHook.installing(into: [:], flagPath: "/tmp/flag")
    #expect(ClaudeStopHook.isInstalled(in: installed))
    let removed = ClaudeStopHook.removing(from: installed)
    #expect(removed.isEmpty)
}

@Test func stopHookCommandBlocksOnlyWhileFlagExists() throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("burnrate hook \(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let flag = dir.appendingPathComponent("it's tripped").path
    let command = ClaudeStopHook.command(flagPath: flag)

    func run() throws -> (Int32, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        let err = Pipe()
        process.standardError = err
        try process.run()
        process.waitUntilExit()
        let text = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return (process.terminationStatus, text)
    }

    #expect(try run().0 == 0)
    try "stop now".write(toFile: flag, atomically: true, encoding: .utf8)
    let (status, text) = try run()
    #expect(status == 2)
    #expect(text == "stop now")
}

@Test func claudeProcessMatchRecognizesInstalls() {
    #expect(ClaudeProcessMatch.isClaudeCode(executablePath: "/Users/a/.local/share/claude/versions/2.1.0/claude", arguments: ["claude"]))
    #expect(ClaudeProcessMatch.isClaudeCode(executablePath: "/Users/a/.local/share/claude/versions/2.1.332", arguments: ["claude", "--model", "x"]))
    #expect(ClaudeProcessMatch.isClaudeCode(
        executablePath: "/Users/a/Library/Application Support/Claude/claude-code/2.1.331/x/claude.app/Contents/MacOS/claude",
        arguments: ["claude", "--output-format", "stream-json"]
    ))
    #expect(ClaudeProcessMatch.isClaudeCode(
        executablePath: "/opt/homebrew/bin/node",
        arguments: ["node", "/opt/homebrew/lib/node_modules/@anthropic-ai/claude-code/cli.js"]
    ))
    #expect(ClaudeProcessMatch.isClaudeCode(executablePath: "/opt/homebrew/bin/node", arguments: ["node", "/opt/homebrew/bin/claude"]))
    #expect(!ClaudeProcessMatch.isClaudeCode(executablePath: "/Applications/Claude.app/Contents/MacOS/Claude", arguments: ["Claude"]))
    #expect(!ClaudeProcessMatch.isClaudeCode(executablePath: "/opt/homebrew/bin/node", arguments: ["node", "server.js"]))
    #expect(!ClaudeProcessMatch.isClaudeCode(executablePath: "/usr/bin/grep", arguments: ["grep", "claude"]))
}

@Test func procArgsParserReadsArgv() {
    var bytes: [UInt8] = [3, 0, 0, 0]
    bytes += Array("/bin/claude".utf8) + [0, 0, 0, 0]
    bytes += Array("claude".utf8) + [0] + Array("-p".utf8) + [0] + Array("hi there".utf8) + [0]
    bytes += Array("HOME=/Users/a".utf8) + [0]
    #expect(ClaudeProcessMatch.arguments(fromProcArgs: bytes) == ["claude", "-p", "hi there"])
    #expect(ClaudeProcessMatch.arguments(fromProcArgs: []) == [])
}

@Test func usedUpLimitNamesFirstFullWindow() {
    #expect(SpendCap.usedUpLimit(nil) == nil)
    let room = ClaudeLimits(
        fiveHour: ClaudeLimitWindow(percentUsed: 99, resetsAt: nil),
        weekly: ClaudeLimitWindow(percentUsed: 40, resetsAt: nil)
    )
    #expect(SpendCap.usedUpLimit(room) == nil)
    let fiveHourFull = ClaudeLimits(
        fiveHour: ClaudeLimitWindow(percentUsed: 100, resetsAt: nil),
        weekly: ClaudeLimitWindow(percentUsed: 100, resetsAt: nil)
    )
    #expect(SpendCap.usedUpLimit(fiveHourFull) == "5-hour limit")
    let opusFull = ClaudeLimits(
        fiveHour: nil,
        weekly: ClaudeLimitWindow(percentUsed: 50, resetsAt: nil),
        weeklyOpus: ClaudeLimitWindow(percentUsed: 104, resetsAt: nil)
    )
    #expect(SpendCap.usedUpLimit(opusFull) == "Weekly Opus limit")
}
