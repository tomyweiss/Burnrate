import SwiftUI

struct EmptySpendView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "flame")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
            Text("No spend since midnight")
                .font(.callout.weight(.medium))
            Text("Usage appears here as you work in Cursor.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

struct ErrorBanner: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message)
                .font(.caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button("Retry", action: onRetry)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(10)
        .background(.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct UsageSkeletonView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("$—.——")
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .foregroundStyle(.tertiary)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.quaternary)
                .frame(height: 36)
                .redacted(reason: .placeholder)
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.quaternary)
                    .frame(height: 52)
                    .redacted(reason: .placeholder)
            }
            Spacer()
        }
        .padding(16)
    }
}
