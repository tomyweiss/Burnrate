import Foundation
import CryptoKit

/// Verifies [minisign](https://jedisct1.github.io/minisign/) signatures over release zips.
///
/// Only legacy (non-prehashed) `Ed` signatures are accepted so verification can use
/// CryptoKit Ed25519 directly over the file bytes. Releases must be signed with
/// `minisign -Sm <zip> -l`.
enum SignatureVerifier {
    /// Embedded Burnrate release-signing public key (from `burnrate.pub`).
    /// Format: 8-byte key ID + 32-byte Ed25519 public key.
    private static let embeddedKeyID: [UInt8] = [
        0x9c, 0x78, 0x6e, 0x18, 0x77, 0x58, 0x40, 0xfe
    ]
    private static let embeddedPublicKey: [UInt8] = [
        0x90, 0x3b, 0xdf, 0xc4, 0xb2, 0xdb, 0x79, 0xbe,
        0x85, 0xef, 0xc9, 0x27, 0xf4, 0xe9, 0x18, 0x9b,
        0x2e, 0x0a, 0x10, 0x8d, 0xa1, 0x0e, 0x36, 0x5c,
        0xc4, 0xdd, 0x78, 0xce, 0x5a, 0x0e, 0x1a, 0x80
    ]

    private static let trustedCommentPrefix = "trusted comment: "
    /// Legacy unhashed Ed25519 (`Ed`). Prehashed (`ED`) is rejected.
    private static let legacyAlgorithm = Data([0x45, 0x64]) // "Ed"

    /// Verifies that `signatureText` (contents of a `.minisig` file) is a valid
    /// legacy minisign signature for the file at `fileURL`, under the embedded key.
    static func verify(fileAt fileURL: URL, signature signatureText: String) -> Bool {
        do {
            return try verifyThrowing(fileAt: fileURL, signature: signatureText)
        } catch {
            return false
        }
    }

    static func verifyThrowing(fileAt fileURL: URL, signature signatureText: String) throws -> Bool {
        let parsed = try parseMinisig(signatureText)
        guard parsed.algorithm == legacyAlgorithm else {
            throw VerifyError.prehashedNotSupported
        }
        guard parsed.keyID.elementsEqual(embeddedKeyID) else {
            throw VerifyError.keyIDMismatch
        }

        let publicKey = try Curve25519.Signing.PublicKey(
            rawRepresentation: Data(embeddedPublicKey)
        )

        let fileData = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        guard publicKey.isValidSignature(parsed.signature, for: fileData) else {
            throw VerifyError.fileSignatureInvalid
        }

        // Global signature covers: raw 64-byte file signature || trusted comment body
        let globalMessage = parsed.signature + Data(parsed.trustedComment.utf8)
        guard publicKey.isValidSignature(parsed.globalSignature, for: globalMessage) else {
            throw VerifyError.globalSignatureInvalid
        }

        return true
    }

    // MARK: - Parsing

    struct ParsedSignature: Sendable {
        let algorithm: Data
        let keyID: [UInt8]
        let signature: Data
        let trustedComment: String
        let globalSignature: Data
    }

    enum VerifyError: Error, LocalizedError {
        case malformedSignatureFile
        case prehashedNotSupported
        case keyIDMismatch
        case fileSignatureInvalid
        case globalSignatureInvalid

        var errorDescription: String? {
            switch self {
            case .malformedSignatureFile: "Malformed minisign signature file."
            case .prehashedNotSupported: "Prehashed minisign signatures are not supported; sign with -l."
            case .keyIDMismatch: "Signature key ID does not match the embedded Burnrate public key."
            case .fileSignatureInvalid: "File signature verification failed."
            case .globalSignatureInvalid: "Trusted-comment signature verification failed."
            }
        }
    }

    /// Minisig layout:
    /// ```
    /// untrusted comment: ...
    /// <base64: 2-byte alg || 8-byte key id || 64-byte Ed25519 sig>
    /// trusted comment: ...
    /// <base64: 64-byte Ed25519 global sig>
    /// ```
    static func parseMinisig(_ text: String) throws -> ParsedSignature {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard lines.count >= 4 else {
            throw VerifyError.malformedSignatureFile
        }

        // Find the signature line (base64 after untrusted comment) and trusted comment.
        guard let trustedIndex = lines.firstIndex(where: { $0.hasPrefix(trustedCommentPrefix) }),
              trustedIndex >= 1,
              trustedIndex + 1 < lines.count
        else {
            throw VerifyError.malformedSignatureFile
        }

        let sigLine = lines[trustedIndex - 1]
        let trustedLine = lines[trustedIndex]
        let globalLine = lines[trustedIndex + 1]

        guard let sigBlob = Data(base64Encoded: sigLine), sigBlob.count == 74,
              let globalBlob = Data(base64Encoded: globalLine), globalBlob.count == 64
        else {
            throw VerifyError.malformedSignatureFile
        }

        let algorithm = sigBlob.prefix(2)
        let keyID = Array(sigBlob[2..<10])
        let signature = sigBlob.suffix(from: 10)
        let trustedComment = String(trustedLine.dropFirst(trustedCommentPrefix.count))

        return ParsedSignature(
            algorithm: Data(algorithm),
            keyID: keyID,
            signature: Data(signature),
            trustedComment: trustedComment,
            globalSignature: globalBlob
        )
    }
}
