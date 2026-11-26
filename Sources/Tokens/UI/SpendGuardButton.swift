import SwiftUI
import TokensCore

/// Top-bar menu that arms the Claude Code stop in one click: at a spend cap, or when
/// a plan limit is used up.
struct SpendGuardButton: View {
    @Environment(SpendCapController.self) private var guardian
    @Bindable var settings: SettingsStore
    /// False when the top row is too narrow for the title.
    var showsTitle = true
    var onOpenSettings: () -> Void

    var body: some View {
        Menu {
            if guardian.isTripped {
                Text(guardian.tripDetail ?? "Claude Code was stopped")
                Button("Re-arm", systemImage: "arrow.clockwise") { guardian.arm() }
                if guardian.stopsProcesses, !guardian.processesStopped {
                    Button("Stop processes now", systemImage: "stop.circle") {
                        guardian.stopProcessesNow()
                    }
                }
                Button("Turn off", systemImage: "xmark.circle") { guardian.disarm() }
            } else if guardian.isArmed {
                Text(armedSummary)
                Button("Turn off", systemImage: "xmark.circle") { guardian.disarm() }
                if !settings.launchAtLogin {
                    Button("Launch Burnrate at login", systemImage: "power") {
                        settings.launchAtLogin = true
                    }
                }
            } else {
                Button("Stop when a plan limit is used up", systemImage: "gauge.with.dots.needle.100percent") {
                    armPlanLimit()
                }
                Menu("Stop at a spend cap", systemImage: "dollarsign.circle") {
                    ForEach(SpendCap.dollarChoices, id: \.self) { dollars in
                        Button(SpendGuardTitle.wholeDollars(dollars)) { armCap(dollars) }
                    }
                }
            }
            Divider()
            Button("Stop settings…", systemImage: "gearshape") { onOpenSettings() }
        } label: {
            SpendGuardLabel(
                state: .make(isArmed: guardian.isArmed, isTripped: guardian.isTripped),
                title: showsTitle ? title : nil
            )
        }
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(helpText)
        .accessibilityLabel("Stop Claude Code")
        .accessibilityValue(helpText)
        .disabled(!settings.claudeCodeEnabled && !guardian.isArmed && !guardian.isTripped)
    }


    private var title: String {
        SpendGuardTitle.make(
            isArmed: guardian.isArmed,
            isTripped: guardian.isTripped,
            capEnabled: guardian.capEnabled,
            capDollars: guardian.capDollars,
            spentCents: guardian.spentCents,
            planLimitEnabled: guardian.planLimitEnabled
        )
    }

    private var helpText: String {
        if guardian.isTripped { return guardian.tripDetail ?? "Claude Code was stopped" }
        if guardian.isArmed { return armedSummary }
        if !settings.claudeCodeEnabled { return "Turn on Claude Code in Settings → Sources to use the stop" }
        return "Stop Claude Code agents at a spend cap or when a plan limit is used up"
    }

    private var armedSummary: String {
        SpendCapSummary.armed(
            capEnabled: guardian.capEnabled,
            capDollars: guardian.capDollars,
            spentCents: guardian.spentCents,
            planLimitEnabled: guardian.planLimitEnabled,
            armedAt: guardian.armedAt
        )
    }

    private func armPlanLimit() {
        settings.claudeLimitsEnabled = true
        guardian.planLimitEnabled = true
        guardian.capEnabled = false
        guardian.arm()
    }

    private func armCap(_ dollars: Double) {
        guardian.capDollars = dollars
        guardian.capEnabled = true
        guardian.arm()
    }
}

/// The top-bar pill. Same shape as Keep awake so the two read as a pair.
struct SpendGuardLabel: View {
    enum State {
        case idle, armed, tripped

        static func make(isArmed: Bool, isTripped: Bool) -> State {
            isTripped ? .tripped : (isArmed ? .armed : .idle)
        }

        var symbol: String {
            switch self {
            case .idle: "shield"
            case .armed: "shield.lefthalf.filled"
            case .tripped: "stop.circle.fill"
            }
        }

        /// Idle is teal so it reads apart from violet Keep awake and the orange
        /// Community pill. Armed is green like a running trip. Tripped is red.
        var tint: Color {
            switch self {
            case .idle: .teal
            case .armed: .green
            case .tripped: .red
            }
        }
    }

    var state: State
    var title: String?

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: state.symbol)
            if let title {
                Text(title)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .font(.subheadline.weight(.semibold))
        .fixedSize(horizontal: true, vertical: false)
        .foregroundStyle(state.tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(state.tint.opacity(state == .idle ? 0.18 : 0.30)))
        .contentShape(Capsule())
    }
}

/// The pill's text: what the stop is set to, at a glance.
enum SpendGuardTitle {
    static func make(
        isArmed: Bool,
        isTripped: Bool,
        capEnabled: Bool,
        capDollars: Double,
        spentCents: Double?,
        planLimitEnabled: Bool
    ) -> String {
        if isTripped { return "Agents stopped" }
        guard isArmed else { return "Stop agents" }
        if capEnabled {
            let spent = MoneyFormat.estimated((spentCents ?? 0) / 100)
            return "Stop at \(wholeDollars(capDollars)) · \(spent)"
        }
        return planLimitEnabled ? "Stop at plan limit" : "Stop armed"
    }

    /// `$20` for whole amounts, `$12.50` otherwise.
    static func wholeDollars(_ value: Double) -> String {
        value.rounded() == value ? String(format: "$%.0f", value) : MoneyFormat.dollars(value)
    }
}

enum SpendCapSummary {
    /// `Stops at ~$3.20 of $20 · plan limit · since 11:42 PM`.
    static func armed(
        capEnabled: Bool,
        capDollars: Double,
        spentCents: Double?,
        planLimitEnabled: Bool,
        armedAt: Date?
    ) -> String {
        var parts: [String] = []
        if capEnabled {
            let spent = MoneyFormat.estimated((spentCents ?? 0) / 100)
            parts.append("\(spent) of \(MoneyFormat.dollars(capDollars))")
        }
        if planLimitEnabled { parts.append("plan limit") }
        var text = parts.isEmpty ? "Armed, no trigger" : "Stops at " + parts.joined(separator: " or ")
        if let armedAt { text += " · since \(SpendCapController.time(armedAt))" }
        return text
    }
}
