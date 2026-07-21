import Foundation
import CryptoKit
import AppKit

struct AvailableUpdate: Sendable, Equatable {
    let version: String
    let zipURL: URL
    let sha256URL: URL?
    let signatureURL: URL?
    let releasePageURL: URL?
    let notes: String?
}

enum UpdateError: Error, LocalizedError {
    case noRelease
    case missingZipAsset
    case checksumMissing
    case checksumMismatch
    case signatureMissing
    case signatureInvalid
    case downloadFailed
    case unzipFailed
    case invalidAppBundle
    case helperFailed

    var errorDescription: String? {
        switch self {
        case .noRelease: "No GitHub release found."
        case .missingZipAsset: "Release has no Burnrate-*.zip asset."
        case .checksumMissing: "Release is missing a .sha256 checksum file."
        case .checksumMismatch: "Downloaded update failed checksum verification."
        case .signatureMissing: "Release is missing a .minisig signature file."
        case .signatureInvalid: "Downloaded update failed signature verification."
        case .downloadFailed: "Could not download the update."
        case .unzipFailed: "Could not unpack the update archive."
        case .invalidAppBundle: "Update archive did not contain Burnrate.app."
        case .helperFailed: "Could not start the update helper."
        }
    }
}

actor UpdateChecker {
    static let shared = UpdateChecker()

    private let owner = "tomyweiss"
    private let repo = "Burnrate"
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        config.httpAdditionalHeaders = [
            "Accept": "application/vnd.github+json",
            "User-Agent": "Burnrate-Updater"
        ]
        session = URLSession(configuration: config)
    }

    func fetchLatestUpdate(currentVersion: String) async throws -> AvailableUpdate? {
        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest") else {
            throw UpdateError.noRelease
        }
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode == 404 {
            return nil
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw UpdateError.noRelease
        }

        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        let remote = Self.normalizeVersion(release.tagName)
        let local = Self.normalizeVersion(currentVersion)
        guard Self.isVersion(remote, newerThan: local) else {
            return nil
        }

        let zip = release.assets.first {
            $0.name.hasPrefix("Burnrate-") && $0.name.hasSuffix(".zip") && !$0.name.contains("sha256")
        }
        guard let zip, let zipURL = URL(string: zip.browserDownloadURL) else {
            throw UpdateError.missingZipAsset
        }

        let shaAsset = release.assets.first {
            $0.name.hasSuffix(".sha256") || $0.name.hasSuffix(".zip.sha256")
        }
        let shaURL = shaAsset.flatMap { URL(string: $0.browserDownloadURL) }

        let sigAsset = release.assets.first {
            $0.name.hasSuffix(".minisig")
        }
        let sigURL = sigAsset.flatMap { URL(string: $0.browserDownloadURL) }

        return AvailableUpdate(
            version: remote,
            zipURL: zipURL,
            sha256URL: shaURL,
            signatureURL: sigURL,
            releasePageURL: URL(string: release.htmlURL),
            notes: release.body
        )
    }

    func downloadAndPrepareInstall(_ update: AvailableUpdate) async throws -> URL {
        let cache = try updatesDirectory()
        let zipPath = cache.appendingPathComponent("Burnrate-\(update.version).zip")
        let extractDir = cache.appendingPathComponent("extract-\(update.version)", isDirectory: true)

        try? FileManager.default.removeItem(at: zipPath)
        try? FileManager.default.removeItem(at: extractDir)
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)

        let (zipTemp, _) = try await session.download(from: update.zipURL)
        if FileManager.default.fileExists(atPath: zipPath.path) {
            try FileManager.default.removeItem(at: zipPath)
        }
        try FileManager.default.moveItem(at: zipTemp, to: zipPath)

        let expected = try await loadExpectedSHA256(update: update, cache: cache, version: update.version)
        let actual = try Self.sha256Hex(of: zipPath)
        guard actual.caseInsensitiveCompare(expected) == .orderedSame else {
            throw UpdateError.checksumMismatch
        }

        let signatureText = try await loadSignature(update: update)
        guard SignatureVerifier.verify(fileAt: zipPath, signature: signatureText) else {
            throw UpdateError.signatureInvalid
        }

        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-x", "-k", zipPath.path, extractDir.path]
        try unzip.run()
        unzip.waitUntilExit()
        guard unzip.terminationStatus == 0 else {
            throw UpdateError.unzipFailed
        }

        let appURL = try findAppBundle(in: extractDir)
        return appURL
    }

    func launchHelperReplacing(currentApp: URL, with newApp: URL) throws {
        let cache = try updatesDirectory()
        let helper = cache.appendingPathComponent("update-helper.sh")
        let script = """
        #!/bin/bash
        set -euo pipefail
        PID="$1"
        SRC="$2"
        DEST="$3"
        while kill -0 "$PID" 2>/dev/null; do sleep 0.2; done
        sleep 0.4
        rm -rf "$DEST"
        /usr/bin/ditto "$SRC" "$DEST"
        /usr/bin/xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
        /usr/bin/open "$DEST"
        """
        try script.write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: helper.path
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            helper.path,
            String(ProcessInfo.processInfo.processIdentifier),
            newApp.path,
            currentApp.path
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw UpdateError.helperFailed
        }
    }

    private func loadExpectedSHA256(update: AvailableUpdate, cache: URL, version: String) async throws -> String {
        guard let shaURL = update.sha256URL else {
            throw UpdateError.checksumMissing
        }
        let (data, response) = try await session.data(from: shaURL)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let text = String(data: data, encoding: .utf8)
        else {
            throw UpdateError.checksumMissing
        }
        // Formats: "<hex>  filename" or bare hex
        let token = text.split(whereSeparator: { $0.isWhitespace || $0 == "*" }).first.map(String.init)
        guard let hex = token, hex.count == 64, hex.allSatisfy(\.isHexDigit) else {
            throw UpdateError.checksumMissing
        }
        let _ = cache
        let _ = version
        return hex
    }

    private func loadSignature(update: AvailableUpdate) async throws -> String {
        guard let sigURL = update.signatureURL else {
            throw UpdateError.signatureMissing
        }
        let (data, response) = try await session.data(from: sigURL)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let text = String(data: data, encoding: .utf8),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw UpdateError.signatureMissing
        }
        return text
    }

    private func updatesDirectory() throws -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Burnrate/updates", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func findAppBundle(in directory: URL) throws -> URL {
        let fm = FileManager.default
        if let kids = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            if let direct = kids.first(where: { $0.lastPathComponent == "Burnrate.app" }) {
                return direct
            }
            for kid in kids where kid.hasDirectoryPath {
                if let nested = try? findAppBundle(in: kid), nested.lastPathComponent == "Burnrate.app" {
                    return nested
                }
            }
        }
        throw UpdateError.invalidAppBundle
    }

    static func normalizeVersion(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.lowercased().hasPrefix("v") {
            s = String(s.dropFirst())
        }
        return s
    }

    static func isVersion(_ remote: String, newerThan local: String) -> Bool {
        let r = remote.split(separator: ".").map { Int($0) ?? 0 }
        let l = local.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(r.count, l.count)
        for i in 0..<count {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv != lv { return rv > lv }
        }
        return false
    }

    static func sha256Hex(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        while autoreleasepool(invoking: {
            let chunk = handle.readData(ofLength: 1024 * 1024)
            if chunk.isEmpty { return false }
            hasher.update(data: chunk)
            return true
        }) {}
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: String
    let body: String?
    let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case body
        case assets
    }
}

private struct GitHubAsset: Decodable {
    let name: String
    let browserDownloadURL: String

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}
