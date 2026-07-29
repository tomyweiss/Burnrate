import SwiftUI

/// Collapsible search: icon toggles an inline field; optional trailing controls hide while searching.
struct SectionSearchControl<Trailing: View>: View {
    @Binding var text: String
    @Binding var isPresented: Bool
    var placeholder: String
    var reduceMotion: Bool = false
    @ViewBuilder var trailing: () -> Trailing

    init(
        text: Binding<String>,
        isPresented: Binding<Bool>,
        placeholder: String,
        reduceMotion: Bool = false,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        _text = text
        _isPresented = isPresented
        self.placeholder = placeholder
        self.reduceMotion = reduceMotion
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 8) {
            if isPresented {
                SectionSearchField(text: $text, placeholder: placeholder)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }

            Spacer(minLength: 0)

            if !isPresented {
                trailing()
            }

            Button(action: toggle) {
                Image(systemName: isPresented ? "xmark" : "magnifyingglass")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                    .frame(width: 26, height: 26)
                    .background(
                        isActive ? Color.accentColor.opacity(0.12) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
            }
            .buttonStyle(.borderless)
            .help(isPresented ? "Close search" : "Search list")
        }
        .animation(reduceMotion ? nil : .snappy, value: isPresented)
    }

    private var isActive: Bool {
        isPresented || ListSearch.isActive(text)
    }

    private func toggle() {
        if reduceMotion {
            if isPresented {
                isPresented = false
                text = ""
            } else {
                isPresented = true
            }
        } else {
            withAnimation(.snappy) {
                if isPresented {
                    isPresented = false
                    text = ""
                } else {
                    isPresented = true
                }
            }
        }
        MenuBarPanelKeeper.keepOpen()
    }
}

struct SectionSearchField: View {
    @Binding var text: String
    var placeholder: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.tertiary)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.subheadline)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.borderless)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onChange(of: text) { _, _ in
            MenuBarPanelKeeper.keepOpen()
        }
    }
}
