import Foundation
import TokensCore

/// Reads Grok Bot's on-disk roster and transcript replicas. The remote sandbox
/// `store.db` is not on this Mac; these blobs are the local copy.
enum GrokBotStore {
    struct Library: Sendable {
        var names: [String: String]
        var prompts: [String: [PromptRecord]]
        var subagentParents: [String: String]

        static let empty = Library(names: [:], prompts: [:], subagentParents: [:])
        static var disk: Library { load() }
    }

    static var persistenceDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Grok Bot/sand-client-persistence")
    }

    static func blobName(for key: String) -> String {
        Base32.encode(Data(key.utf8)) + ".blob"
    }

    static func load(directory: URL = persistenceDirectory) -> Library {
        guard FileManager.default.fileExists(atPath: directory.path) else { return .empty }
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            return .empty
        }

        let blobs = files
            .filter { $0.pathExtension == "blob" }
            .sorted { modificationDate(of: $0) < modificationDate(of: $1) }

        var names: [String: String] = [:]
        var prompts: [String: [PromptRecord]] = [:]
        var explicitParents: [String: String] = [:]
        var mentionedBy: [String: Set<String>] = [:]

        for url in blobs {
            let filename = url.deletingPathExtension().lastPathComponent
            guard let keyData = Base32.decode(filename),
                  let key = String(data: keyData, encoding: .utf8)
            else { continue }
            guard let data = try? Data(contentsOf: url), data.count <= 8_000_000 else { continue }

            if key.hasSuffix(".roster.last-roster") {
                names.merge(GrokBotTranscript.agentNames(fromRosterJSON: data)) { _, new in new }
            }
            guard let marker = key.range(of: ".transcript.replicas.") else { continue }
            let agentID = String(key[marker.upperBound...])
            guard !agentID.isEmpty else { continue }

            let parsed = GrokBotTranscript.prompts(fromTranscriptJSON: data)
            if !parsed.isEmpty {
                prompts[agentID] = parsed.map { prompt in
                    PromptRecord(
                        conversationId: agentID,
                        bubbleId: prompt.id,
                        text: prompt.text,
                        createdAtMs: prompt.timestampMs,
                        skills: PromptCatalog.skillMentions(in: prompt.text),
                        turnIndex: nil
                    )
                }
            }
            guard let text = String(data: data, encoding: .utf8) else { continue }
            for (child, parent) in GrokBotTranscript.subagentParents(in: text) where explicitParents[child] == nil {
                explicitParents[child] = parent
            }
            for child in GrokBotTranscript.mentionedSubagentIDs(in: text) {
                mentionedBy[child, default: []].insert(agentID)
            }
        }

        var subagentParents = explicitParents
        for (child, agents) in mentionedBy where subagentParents[child] == nil && agents.count == 1 {
            subagentParents[child] = agents.first
        }
        return Library(names: names, prompts: prompts, subagentParents: subagentParents)
    }

    private static func modificationDate(of url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}

private enum Base32 {
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    static func encode(_ data: Data) -> String {
        var encoded = ""
        var buffer = 0
        var bits = 0
        for byte in data {
            buffer = (buffer << 8) | Int(byte)
            bits += 8
            while bits >= 5 {
                bits -= 5
                encoded.append(alphabet[(buffer >> bits) & 0x1F])
            }
        }
        if bits > 0 {
            encoded.append(alphabet[(buffer << (5 - bits)) & 0x1F])
        }
        return encoded.lowercased()
    }

    static func decode(_ string: String) -> Data? {
        let values = Dictionary(uniqueKeysWithValues: alphabet.enumerated().map { ($1, $0) })
        var decoded = Data()
        var buffer = 0
        var bits = 0
        for character in string.uppercased() where character != "=" {
            guard let value = values[character] else { return nil }
            buffer = (buffer << 5) | value
            bits += 5
            if bits >= 8 {
                bits -= 8
                decoded.append(UInt8((buffer >> bits) & 0xFF))
            }
        }
        return decoded
    }
}
