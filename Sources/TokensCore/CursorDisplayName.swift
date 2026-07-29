import Foundation

/// Parses Cursor profile display names from local state DB values (no network).
public enum CursorDisplayName {
    public static func parseScopedProfileJSON(_ json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let displayName = object["displayName"] as? String
        else {
            return nil
        }
        return sanitize(displayName)
    }

    public static func sanitize(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 64 else { return nil }
        return trimmed
    }
}
