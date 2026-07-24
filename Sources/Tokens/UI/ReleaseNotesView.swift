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

    var body: some View {
        if let trimmed {
            Group {
                if let attributed = try? AttributedString(markdown: trimmed) {
                    Text(attributed)
                } else {
                    Text(trimmed)
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
