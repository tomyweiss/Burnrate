import SwiftUI
import TokensCore

/// What the keep-awake button says in each state.
enum AwakeButtonState: Equatable {
    case idle
    /// The password prompt is up; no trip is running yet.
    case starting
    case running(remaining: String)

    static func make(holdsAwake: Bool, remaining: String?) -> AwakeButtonState {
        if let remaining { return .running(remaining: remaining) }
        return holdsAwake ? .starting : .idle
    }

    var isActive: Bool { self != .idle }

    var title: String {
        switch self {
        case .idle: "Keep awake"
        case .starting: "Starting…"
        case .running(let remaining): "Awake · \(remaining)"
        }
    }

    /// Shown next to the cup when the row has no room for the title.
    var compactTitle: String? {
        switch self {
        case .idle, .starting: nil
        case .running(let remaining): remaining
        }
    }

    var symbolName: String {
        isActive ? "cup.and.saucer.fill" : "cup.and.saucer"
    }

    var help: String {
        switch self {
        case .idle: "Keep this Mac awake with the lid closed"
        case .starting: "Waiting for your password"
        case .running(let remaining): "Awake with the lid closed, \(remaining) left. Click to stop."
        }
    }

    var menuHeading: String {
        switch self {
        case .idle: "Stay awake with the lid closed. Sleep returns if the Mac gets hot."
        case .starting: "Waiting for your password"
        case .running(let remaining): "Awake with the lid closed · \(remaining) left"
        }
    }
}

/// Idle is violet, so the cup reads as its own feature: not the orange Community
/// pill, and not the blue used for a selected source. A trip in progress is green,
/// with a stronger fill, so on and off are obvious next to each other.
enum AwakeButtonPalette {
    static let active = Color.green

    static func idle(_ scheme: ColorScheme) -> Color {
        switch scheme {
        case .dark:
            Color(red: 0.769, green: 0.710, blue: 0.992)
        default:
            Color(red: 0.427, green: 0.157, blue: 0.851)
        }
    }

    static func tint(for state: AwakeButtonState, scheme: ColorScheme) -> Color {
        state.isActive ? active : idle(scheme)
    }

    static func capsuleOpacity(for state: AwakeButtonState) -> Double {
        state.isActive ? 0.30 : 0.18
    }
}

struct AwakeButtonLabel: View {
    var state: AwakeButtonState
    /// False when the top row is too narrow for the title.
    var showsTitle = true

    @Environment(\.colorScheme) private var colorScheme

    private var text: String? {
        showsTitle ? state.title : state.compactTitle
    }

    private var tint: Color {
        AwakeButtonPalette.tint(for: state, scheme: colorScheme)
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: state.symbolName)
            if let text {
                Text(text)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .font(.subheadline.weight(.semibold))
        .fixedSize(horizontal: true, vertical: false)
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(tint.opacity(AwakeButtonPalette.capsuleOpacity(for: state))))
        .contentShape(Capsule())
    }
}

/// Top-row control for a closed-lid trip. Idle: pick a duration. Running: time left, and Stop.
struct AwakeButton: View {
    var awake: AwakeSessionController
    var showsTitle = true
    /// Called once a trip is actually starting. Cancelling the warning leaves the intro up.
    var onTripStarted: () -> Void = {}

    private var state: AwakeButtonState {
        .make(holdsAwake: awake.holdsAwake, remaining: awake.remainingLabel)
    }

    var body: some View {
        Menu {
            Section(state.menuHeading) {
                if awake.holdsAwake {
                    Button("Stop keeping awake", systemImage: "stop.fill") {
                        awake.stop()
                        MenuBarPanelKeeper.keepOpen()
                    }
                } else {
                    ForEach(AwakeTrip.durationChoices, id: \.self) { seconds in
                        Button("For \(AwakeTrip.durationLabel(seconds))") {
                            awake.start(seconds: seconds)
                            if awake.holdsAwake {
                                onTripStarted()
                            }
                            MenuBarPanelKeeper.keepOpen()
                        }
                    }
                }
            }
        } label: {
            AwakeButtonLabel(state: state, showsTitle: showsTitle)
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(state.help)
        .accessibilityLabel(state.help)
    }
}
