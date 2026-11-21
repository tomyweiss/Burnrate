import SwiftUI

/// Top-of-panel note for an update a background check found.
struct UpdateBanner: View {
    let update: UpdateManager.PendingUpdate
    var onOpen: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(Color.accentColor)
            Text(update.title)
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 8)
            Button(update.actionTitle, action: onOpen)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
