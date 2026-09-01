import Foundation

/// Parses Cursor session JWTs from the desktop IDE DB or Agent CLI login.
public enum CursorAccessToken {
    public static func userID(fromJWT jwt: String) -> String? {
        guard let payload = jwtPayload(jwt),
              let subject = payload["sub"] as? String
        else {
            return nil
        }
        if let separatorIndex = subject.lastIndex(of: "|") {
            return String(subject[subject.index(after: separatorIndex)...])
        }
        return subject
    }

    public static func cookieValue(fromJWT jwt: String) -> String? {
        guard let userID = userID(fromJWT: jwt), !userID.isEmpty else {
            return nil
        }
        return "\(userID)%3A%3A\(jwt)"
    }

    public static func isExpired(_ jwt: String, now: Date = Date()) -> Bool {
        guard let payload = jwtPayload(jwt),
              let exp = jsonNumber(payload["exp"])
        else {
            return false
        }
        return Date(timeIntervalSince1970: exp) <= now
    }

    public static func accessToken(fromCLIAuthJSON data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = object["accessToken"] as? String
        else {
            return nil
        }
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func jwtPayload(_ jwt: String) -> [String: Any]? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }

        var payload = String(parts[1])
        let remainder = payload.count % 4
        if remainder > 0 {
            payload += String(repeating: "=", count: 4 - remainder)
        }
        payload = payload
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        return json
    }

    private static func jsonNumber(_ value: Any?) -> TimeInterval? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let value = value as? Double {
            return value
        }
        if let value = value as? Int {
            return TimeInterval(value)
        }
        return nil
    }
}
