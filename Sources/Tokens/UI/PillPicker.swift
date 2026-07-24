import SwiftUI

enum PillPickerSize {
    case regular
    case compact
    /// Control-bar tabs: subheadline labels with compact padding to fit the panel width.
    case controlBar
}

enum PillPickerStyle {
  /// Glass capsule track with sliding accent selection.
    case capsule
  /// Flat secondary control: no track, faint accent fill on selection.
    case flat
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
    var style: PillPickerStyle = .capsule
    var fillsWidth: Bool = false
    var iconOnly: Bool = false

    @Namespace private var selectionNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoveredValue: Value?

    var body: some View {
        HStack(spacing: segmentSpacing) {
            ForEach(options) { option in
                segment(option)
            }
        }
        .padding(style == .capsule ? trackPadding : 0)
        .background {
            if style == .capsule {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Capsule()
                            .strokeBorder(.quaternary.opacity(0.8), lineWidth: 0.5)
                    }
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
                    switch style {
                    case .capsule:
                        Capsule()
                            .fill(.clear)
                            .glassEffect(.regular.tint(.accentColor))
                            .matchedGeometryEffect(id: "pillSelection", in: selectionNamespace)
                    case .flat:
                        Capsule()
                            .fill(Color.accentColor.opacity(0.12))
                            .matchedGeometryEffect(id: "pillSelection", in: selectionNamespace)
                    }
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
            if style == .capsule, iconOnly, isPointerOver {
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
        switch style {
        case .capsule:
            if isSelected { return .white }
            if isHovered { return .primary }
            return .secondary
        case .flat:
            if isSelected { return .accentColor }
            if isHovered { return .primary }
            return Color.secondary.opacity(0.65)
        }
    }

    private func labelFont(isSelected: Bool) -> Font {
        if style == .flat {
            return isSelected ? .caption.weight(.semibold) : .caption.weight(.medium)
        }
        switch size {
        case .regular:
            return isSelected ? .subheadline.weight(.semibold) : .subheadline.weight(.medium)
        case .compact:
            return isSelected ? .caption.weight(.semibold) : .caption.weight(.medium)
        case .controlBar:
            return isSelected ? .callout.weight(.semibold) : .callout.weight(.medium)
        }
    }

    private var iconFont: Font {
        if style == .flat {
            return .caption2.weight(.semibold)
        }
        if iconOnly {
            switch size {
            case .regular: return .subheadline.weight(.semibold)
            case .compact: return .caption.weight(.semibold)
            case .controlBar: return .subheadline.weight(.semibold)
            }
        } else {
            switch size {
            case .regular: return .caption.weight(.semibold)
            case .compact: return .caption2.weight(.semibold)
            case .controlBar: return .caption2.weight(.semibold)
            }
        }
    }

    private var segmentSpacing: CGFloat {
        style == .flat ? 4 : 2
    }

    private var trackPadding: CGFloat {
        switch size {
        case .regular: 3
        case .compact, .controlBar: 2
        }
    }

    private var horizontalPadding: CGFloat {
        if style == .flat {
            return iconOnly ? 6 : 8
        }
        if iconOnly {
            switch size {
            case .regular: return 9
            case .compact: return 7
            case .controlBar: return 7
            }
        } else {
            switch size {
            case .regular: return 10
            case .compact: return 8
            case .controlBar: return 6
            }
        }
    }

    private var verticalPadding: CGFloat {
        if style == .flat { return 3 }
        switch size {
        case .regular: return 5
        case .compact: return 4
        case .controlBar: return 5
        }
    }

    private var iconSpacing: CGFloat {
        switch size {
        case .regular: 4
        case .compact, .controlBar: 3
        }
    }
}
