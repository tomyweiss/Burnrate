import Foundation

/// Strips terminal/font glyphs that render as "?" in the UI (Nerd Font / Powerline PUA).
public enum DisplayText {
    public static func sanitize(_ raw: String, collapseWhitespace: Bool = false) -> String {
        let filtered = raw.unicodeScalars.filter { scalar in
            let value = scalar.value
            if value >= 0xE000 && value <= 0xF8FF { return false }
            if value == 0xFFFD { return false }
            return true
        }
        let cleaned = String(String.UnicodeScalarView(filtered))
        if collapseWhitespace {
            return cleaned
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return cleaned
    }
}
