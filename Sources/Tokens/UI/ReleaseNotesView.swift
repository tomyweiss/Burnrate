import SwiftUI

struct ReleaseNotesView: View {
    let notes: String?
    var lineLimit: Int?
    var font: Font = .caption

    private var trimmed: String? {
        guard let notes else { return nil }
        let text = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private var displayNotes: String? {
        guard var text = trimmed else { return nil }

        if text.hasPrefix("## ") {
            text = String(text.dropFirst(3))
        }

        // Generated notes can lose a line break after the version, e.g. "0.0.19Replace…"
        text = text.replacingOccurrences(
            of: #"(What's new in [\d.]+)(\S)"#,
            with: "$1\n$2",
            options: .regularExpression
        )

        return text
    }

    var body: some View {
        if let displayNotes {
            Group {
                if let attributed = try? AttributedString(markdown: displayNotes) {
                    Text(attributed)
                } else {
                    Text(displayNotes)
                }
            }
            .font(font)
            .foregroundStyle(.secondary)
            .lineLimit(lineLimit)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

extension ReleaseNotesView {
    static func hasContent(_ notes: String?) -> Bool {
        guard let notes else { return false }
        return !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
