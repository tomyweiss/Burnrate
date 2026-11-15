import Foundation
import Testing
@testable import TokensCore

@Test func claudeTranscriptParsesAssistantUsageLine() {
    let line = Data("""
    {"type":"assistant","timestamp":"2026-11-14T20:02:55.108Z","sessionId":"sess-1","cwd":"/tmp/demo","gitBranch":"main","isSidechain":true,"uuid":"line-1","message":{"id":"msg_1","model":"claude-opus-5-5","role":"assistant","usage":{"input_tokens":2,"cache_creation_input_tokens":33955,"cache_read_input_tokens":46033,"output_tokens":2607}}}
    """.utf8)

    #expect(ClaudeTranscript.parse(line: line) == .usage(ClaudeUsageRecord(
        messageId: "msg_1",
        timestampMs: 1_794_686_575_108,
        sessionId: "sess-1",
        model: "claude-opus-5-5",
        inputTokens: 2,
        outputTokens: 2607,
        cacheCreationTokens: 33955,
        cacheReadTokens: 46033,
        isSidechain: true,
        cwd: "/tmp/demo",
        gitBranch: "main"
    )))
}

@Test func claudeTranscriptParsesAStringUserPrompt() {
    let line = Data("""
    {"type":"user","uuid":"prompt-1","sessionId":"sess-1","timestamp":"2026-11-14T20:02:55.108Z","message":{"role":"user","content":"fix the parser"}}
    """.utf8)

    #expect(ClaudeTranscript.parse(line: line) == .prompt(ClaudePromptRecord(
        uuid: "prompt-1",
        sessionId: "sess-1",
        timestampMs: 1_794_686_575_108,
        text: "fix the parser",
        skills: []
    )))
}

@Test func claudeTranscriptIgnoresToolResultArrays() {
    let line = Data("""
    {"type":"user","uuid":"tool-1","sessionId":"sess-1","timestamp":"2026-11-14T20:02:55.108Z","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"ok"},{"type":"text","text":"still a result"}]}}
    """.utf8)

    #expect(ClaudeTranscript.parse(line: line) == .ignored)
}

@Test func claudeTranscriptReadsASlashCommandFromCommandTags() {
    let line = Data("""
    {"type":"user","uuid":"cmd-1","sessionId":"sess-1","timestamp":"2026-11-14T20:02:55Z","message":{"role":"user","content":"<command-message>loop</command-message><command-name>/loop</command-name><command-args>5m check</command-args>"}}
    """.utf8)

    #expect(ClaudeTranscript.parse(line: line) == .prompt(ClaudePromptRecord(
        uuid: "cmd-1",
        sessionId: "sess-1",
        timestampMs: 1_794_686_575_000,
        text: "5m check",
        skills: ["loop"]
    )))
}

@Test func claudeTranscriptFallsBackToTheSlashCommandWhenArgsAreMissing() {
    let line = Data("""
    {"type":"user","uuid":"cmd-2","sessionId":"sess-1","timestamp":"2026-11-14T20:02:55Z","message":{"role":"user","content":"<command-name>/commit</command-name>"}}
    """.utf8)

    #expect(ClaudeTranscript.parse(line: line) == .prompt(ClaudePromptRecord(
        uuid: "cmd-2",
        sessionId: "sess-1",
        timestampMs: 1_794_686_575_000,
        text: "/commit",
        skills: ["commit"]
    )))
}

@Test func claudeTranscriptReadsSlashSkillsFromPlainPromptText() {
    let line = Data("""
    {"type":"user","uuid":"slash-1","sessionId":"sess-1","timestamp":"2026-11-14T20:02:55Z","message":{"role":"user","content":"/loop foo then /commit"}}
    """.utf8)

    #expect(ClaudeTranscript.parse(line: line) == .prompt(ClaudePromptRecord(
        uuid: "slash-1",
        sessionId: "sess-1",
        timestampMs: 1_794_686_575_000,
        text: "/loop foo then /commit",
        skills: ["loop", "commit"]
    )))
}

@Test func claudeTranscriptDoesNotTreatAbsolutePathsAsSkills() {
    let line = Data("""
    {"type":"user","uuid":"path-1","sessionId":"sess-1","timestamp":"2026-11-14T20:02:55Z","message":{"role":"user","content":"/Users/me/proj"}}
    """.utf8)

    guard case .prompt(let prompt) = ClaudeTranscript.parse(line: line) else {
        Issue.record("expected a prompt")
        return
    }
    #expect(prompt.skills == [])
    #expect(prompt.text == "/Users/me/proj")
}

@Test func claudeTranscriptJoinsTextOnlyContentBlocks() {
    let line = Data("""
    {"type":"user","uuid":"blocks-1","sessionId":"sess-1","timestamp":"2026-11-14T20:02:55Z","message":{"role":"user","content":[{"type":"text","text":"hello"},{"type":"text","text":"there"}]}}
    """.utf8)

    guard case .prompt(let prompt) = ClaudeTranscript.parse(line: line) else {
        Issue.record("expected a prompt")
        return
    }
    #expect(prompt.text == "hello\nthere")
    #expect(prompt.skills == [])
}

@Test func claudeTranscriptIgnoresNonTextContentBlocks() {
    let line = Data("""
    {"type":"user","uuid":"img-1","sessionId":"sess-1","timestamp":"2026-11-14T20:02:55Z","message":{"role":"user","content":[{"type":"image","source":{"type":"base64","data":"qq"}}]}}
    """.utf8)

    #expect(ClaudeTranscript.parse(line: line) == .ignored)
}

@Test func claudeTranscriptParsesACustomTitle() {
    let line = Data("""
    {"type":"custom-title","customTitle":"Parser work","sessionId":"sess-1"}
    """.utf8)

    #expect(ClaudeTranscript.parse(line: line) == .title(sessionId: "sess-1", title: "Parser work"))
}

@Test func claudeTranscriptParsesASummaryTitle() {
    let line = Data("""
    {"type":"summary","summary":"Fallback title","sessionId":"sess-1"}
    """.utf8)

    #expect(ClaudeTranscript.parse(line: line) == .title(sessionId: "sess-1", title: "Fallback title"))
}

@Test func claudeTranscriptIgnoresSyntheticModels() {
    let line = Data("""
    {"type":"assistant","timestamp":"2026-11-14T20:02:55.108Z","sessionId":"sess-1","isSidechain":false,"message":{"id":"msg_syn","model":"<synthetic>","role":"assistant","usage":{"input_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0}}}
    """.utf8)

    #expect(ClaudeTranscript.parse(line: line) == .ignored)
}

@Test func claudeTranscriptIgnoresMetaAndLocalCommandStdout() {
    let meta = Data("""
    {"type":"user","isMeta":true,"uuid":"meta-1","sessionId":"sess-1","timestamp":"2026-11-14T20:02:55Z","message":{"role":"user","content":"injected reminder"}}
    """.utf8)
    let stdout = Data("""
    {"type":"user","uuid":"out-1","sessionId":"sess-1","timestamp":"2026-11-14T20:02:55Z","message":{"role":"user","content":"<local-command-stdout>Set model to opus</local-command-stdout>"}}
    """.utf8)

    #expect(ClaudeTranscript.parse(line: meta) == .ignored)
    #expect(ClaudeTranscript.parse(line: stdout) == .ignored)
}

@Test func claudeTranscriptIgnoresMalformedJSON() {
    #expect(ClaudeTranscript.parse(line: Data("{".utf8)) == .ignored)
    #expect(ClaudeTranscript.parse(line: Data("not json".utf8)) == .ignored)
    #expect(ClaudeTranscript.parse(line: Data()) == .ignored)
}

@Test func claudeTranscriptDedupesUsageByMessageIdKeepingTheLast() {
    let first = ClaudeUsageRecord(
        messageId: "msg_1",
        timestampMs: 1,
        sessionId: "sess-1",
        model: "claude-opus-5-5",
        inputTokens: 2,
        outputTokens: 10,
        cacheCreationTokens: 0,
        cacheReadTokens: 0,
        isSidechain: false,
        cwd: "/tmp/demo",
        gitBranch: "main"
    )
    let other = ClaudeUsageRecord(
        messageId: "msg_2",
        timestampMs: 2,
        sessionId: "sess-1",
        model: "claude-opus-5-5",
        inputTokens: 1,
        outputTokens: 4,
        cacheCreationTokens: 0,
        cacheReadTokens: 0,
        isSidechain: false,
        cwd: nil,
        gitBranch: nil
    )
    let later = ClaudeUsageRecord(
        messageId: "msg_1",
        timestampMs: 3,
        sessionId: "sess-1",
        model: "claude-opus-5-5",
        inputTokens: 2,
        outputTokens: 90,
        cacheCreationTokens: 5,
        cacheReadTokens: 6,
        isSidechain: false,
        cwd: "/tmp/demo",
        gitBranch: "main"
    )

    let kept = ClaudeTranscript.dedupe([first, other, later])

    #expect(kept.map(\.messageId) == ["msg_1", "msg_2"])
    #expect(kept.map(\.outputTokens) == [90, 4])
    #expect(kept.first == later)
}
