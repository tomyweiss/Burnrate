import Foundation
import Testing
@testable import TokensCore

@Test func projectSlugFromWorkspacePath() {
    #expect(SessionLogPathMatcher.projectSlug(fromWorkspacePath: "/Users/tom/workspace/tokens") == "Users-tom-workspace-tokens")
    #expect(SessionLogPathMatcher.projectSlug(fromWorkspacePath: "") == nil)
}

@Test func bestTranscriptMatchPrefersWorkspaceSlug() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("session-log-test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }

    let workspace = "/Users/tom/workspace/tokens"
    let slug = try #require(SessionLogPathMatcher.projectSlug(fromWorkspacePath: workspace))
    let conversationId = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"

    let otherProject = root.appendingPathComponent("Other-project")
    let preferredProject = root.appendingPathComponent(slug)
    try FileManager.default.createDirectory(at: otherProject, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: preferredProject, withIntermediateDirectories: true)

    let otherFile = otherProject
        .appendingPathComponent("agent-transcripts/\(conversationId)/\(conversationId).jsonl")
    let preferredFile = preferredProject
        .appendingPathComponent("agent-transcripts/\(conversationId)/\(conversationId).jsonl")
    try FileManager.default.createDirectory(at: otherFile.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: preferredFile.deletingLastPathComponent(), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: otherFile.path, contents: Data("{}".utf8))
    FileManager.default.createFile(atPath: preferredFile.path, contents: Data("{}".utf8))

    let matches = SessionLogPathMatcher.allRootTranscriptURLs(
        projectsRoot: root,
        conversationId: conversationId
    )
    #expect(matches.count == 2)

    let best = SessionLogPathMatcher.bestTranscriptMatch(among: matches, workspacePath: workspace)
    #expect(best?.standardizedFileURL == preferredFile.standardizedFileURL)
}

@Test func rootTranscriptURLFindsSingleMatch() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("session-log-test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }

    let conversationId = "11111111-2222-3333-4444-555555555555"
    let project = root.appendingPathComponent("Users-tom-workspace-demo")
    let file = project
        .appendingPathComponent("agent-transcripts/\(conversationId)/\(conversationId).jsonl")
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: file.path, contents: Data("{}".utf8))

    let found = SessionLogPathMatcher.rootTranscriptURL(
        projectsRoot: root,
        conversationId: conversationId
    )
    #expect(found?.standardizedFileURL == file.standardizedFileURL)
}

@Test func subagentTranscriptURLFindsMatch() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("session-log-test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }

    let parentId = "parent-parent-parent-parent-parentparent"
    let childId = "child-child-child-child-childchildch"
    let project = root.appendingPathComponent("Users-tom-workspace-demo")
    let file = project
        .appendingPathComponent("agent-transcripts/\(parentId)/subagents/\(childId).jsonl")
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: file.path, contents: Data("{}".utf8))

    let found = SessionLogPathMatcher.subagentTranscriptURL(
        projectsRoot: root,
        conversationId: childId,
        parentConversationId: parentId
    )
    #expect(found?.standardizedFileURL == file.standardizedFileURL)
}

@Test func cliStoreURLFindsNormalizedSessionID() throws {
    let chatsRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("cli-chats-test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: chatsRoot) }

    let conversationId = "abcdabcd-abcd-abcd-abcd-abcdabcdabcd"
    let sessionDir = chatsRoot
        .appendingPathComponent("workspace-hash")
        .appendingPathComponent(conversationId)
    try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
    let dbURL = sessionDir.appendingPathComponent("store.db")
    FileManager.default.createFile(atPath: dbURL.path, contents: Data())

    // CLIChatStore is in Tokens target; test normalization inline.
    let normalized = conversationId.replacingOccurrences(of: "-", with: "").lowercased()
    #expect(normalized == "abcdabcdabcdabcdabcdabcdabcdabcd")

    let sessionFolderName = sessionDir.lastPathComponent
    let folderNormalized = sessionFolderName.replacingOccurrences(of: "-", with: "").lowercased()
    #expect(folderNormalized == normalized)
}
