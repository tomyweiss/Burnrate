import SwiftUI

enum PillPickerSize {
    case regular
    case compact
    /// Control-bar tabs: subheadline labels with compact padding to fit the panel width.
    case controlBar
}

/// Capsule segmented control with a sliding glass selection indicator.
struct PillPicker<Value: Hashable>: View {
    struct Option: Identifiable {
        let value: Value
        let title: String
        let icon: String?
        let help: String?

        var id: Value { value }

        init(value: Value, title: String, icon: String? = nil, help: String? = nil) {
            self.value = value
            self.title = title
            self.icon = icon
            self.help = help
        }
    }

    @Binding var selection: Value
    let options: [Option]
    var size: PillPickerSize = .regular
    var fillsWidth: Bool = false
    var iconOnly: Bool = false

    @Namespace private var selectionNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoveredValue: Value?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                segment(option)
            }
        }
        .padding(trackPadding)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule()
                        .strokeBorder(.quaternary.opacity(0.8), lineWidth: 0.5)
                }
        }
        .frame(maxWidth: fillsWidth ? .infinity : nil)
        .animation(reduceMotion ? nil : .snappy, value: hoveredValue)
    }

    @ViewBuilder
    private func segment(_ option: Option) -> some View {
        let isSelected = selection == option.value
        let isHovered = hoveredValue == option.value && !isSelected
        let isPointerOver = hoveredValue == option.value

        Button {
            guard selection != option.value else { return }
            if reduceMotion {
                selection = option.value
            } else {
                withAnimation(.snappy) {
                    selection = option.value
                }
            }
        } label: {
            HStack(spacing: iconSpacing) {
                if let icon = option.icon {
                    Image(systemName: icon)
                        .font(iconFont)
                }
                if !iconOnly {
                    Text(option.title)
                        .font(labelFont(isSelected: isSelected))
                        .lineLimit(1)
                        .minimumScaleFactor(fillsWidth ? 0.8 : 1)
                }
            }
            .foregroundStyle(labelColor(isSelected: isSelected, isHovered: isHovered))
            .frame(maxWidth: fillsWidth ? .infinity : nil)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background {
                if isSelected {
                    Capsule()
                        .fill(.clear)
                        .glassEffect(.regular.tint(.accentColor))
                        .matchedGeometryEffect(id: "pillSelection", in: selectionNamespace)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                hoveredValue = option.value
            } else if hoveredValue == option.value {
                hoveredValue = nil
            }
        }
        .overlay(alignment: .top) {
            if iconOnly, isPointerOver {
                segmentTooltip(option)
                    .offset(y: -30)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .accessibilityLabel(option.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help(option.help ?? option.title)
    }

    private func segmentTooltip(_ option: Option) -> some View {
        Text(option.help ?? option.title)
            .font(.caption.weight(.medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.regularMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(.quaternary.opacity(0.8), lineWidth: 0.5)
            }
            .fixedSize()
            .allowsHitTesting(false)
    }

    private func labelColor(isSelected: Bool, isHovered: Bool) -> Color {
        if isSelected { return .white }
        if isHovered { return .primary }
        return .secondary
    }

    private func labelFont(isSelected: Bool) -> Font {
        switch size {
        case .regular:
            isSelected ? .subheadline.weight(.semibold) : .subheadline.weight(.medium)
        case .compact:
            isSelected ? .caption.weight(.semibold) : .caption.weight(.medium)
        case .controlBar:
            isSelected ? .subheadline.weight(.semibold) : .subheadline.weight(.medium)
        }
    }

    private var iconFont: Font {
        if iconOnly {
            switch size {
            case .regular: .subheadline.weight(.semibold)
            case .compact: .caption.weight(.semibold)
            case .controlBar: .caption.weight(.semibold)
            }
        } else {
            switch size {
            case .regular: .caption.weight(.semibold)
            case .compact: .caption2.weight(.semibold)
            case .controlBar: .caption2.weight(.semibold)
            }
        }
    }

    private var trackPadding: CGFloat {
        switch size {
        case .regular: 3
        case .compact, .controlBar: 2
        }
    }

    private var horizontalPadding: CGFloat {
        if iconOnly {
            switch size {
            case .regular: 9
            case .compact: 7
            case .controlBar: 7
            }
        } else {
            switch size {
            case .regular: 10
            case .compact: 8
            case .controlBar: 6
            }
        }
    }

    private var verticalPadding: CGFloat {
        switch size {
        case .regular: 5
        case .compact, .controlBar: 4
        }
    }

    private var iconSpacing: CGFloat {
        switch size {
        case .regular: 4
        case .compact, .controlBar: 3
        }
    }
}
