import AppKit
import Foundation
import TokensCore

/// Lets the app delegate ask before a quit leaves Claude Code unwatched.
@MainActor
enum SpendCapQuit {
    static weak var controller: SpendCapController?

    /// True when quitting is fine: nothing is armed, or the person chose to quit anyway.
    static func confirm() -> Bool {
        guard let controller, let warning = controller.quitWarning else { return true }
        // Logout, restart and shutdown quit apps through this path too. Never block those.
        if NSAppleEventManager.shared().currentAppleEvent?
            .attributeDescriptor(forKeyword: kAEQuitReason) != nil {
            return true
        }
        MenuBarPanelKeeper.hidePanelsForModalAlert()
        defer { MenuBarPanelKeeper.restorePanelsAfterModalAlert() }
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = warning.title
        alert.informativeText = warning.detail
        alert.addButton(withTitle: "Keep Running")
        alert.addButton(withTitle: "Quit Anyway")
        return alert.runModal() == .alertSecondButtonReturn
    }
}

/// Stops Claude Code agents when an armed guard trips: estimated spend since arming
/// reaches the cap, or a plan limit is used up. It first asks every agent to stop
/// through a `PreToolUse` hook, then stops the remaining processes after a grace period.
@MainActor
@Observable
final class SpendCapController {
    enum TripReason: Equatable {
        case spend
        case planLimit(String)
    }

    private enum Keys {
        static let capDollars = "spendCapDollars"
        static let capEnabled = "spendCapEnabled"
        static let planLimitEnabled = "spendCapPlanLimitEnabled"
        static let stopsProcesses = "spendCapStopsProcesses"
        static let armedAt = "spendCapArmedAt"
        static let warned = "spendCapWarned"
        static let trippedAt = "spendCapTrippedAt"
        static let tripDetail = "spendCapTripDetail"
        static let processesStopped = "spendCapProcessesStopped"
    }

    var capDollars: Double {
        didSet { defaults.set(capDollars, forKey: Keys.capDollars) }
    }
    var capEnabled: Bool {
        didSet { defaults.set(capEnabled, forKey: Keys.capEnabled) }
    }
    var planLimitEnabled: Bool {
        didSet { defaults.set(planLimitEnabled, forKey: Keys.planLimitEnabled) }
    }
    var stopsProcesses: Bool {
        didSet { defaults.set(stopsProcesses, forKey: Keys.stopsProcesses) }
    }

    private(set) var armedAt: Date?
    private(set) var trippedAt: Date?
    /// One line on why the guard tripped and what was stopped.
    private(set) var tripDetail: String?
    private(set) var processesStopped: Bool
    private(set) var isStoppingProcesses = false
    /// Estimated cents since arming, from the latest Claude Code refresh.
    private(set) var spentCents: Double?
    private(set) var hookInstalled = false
    private(set) var hookError: String?

    var isArmed: Bool { armedAt != nil }
    var isTripped: Bool { trippedAt != nil }
    var hasTrigger: Bool { capEnabled || planLimitEnabled }

    /// What a quit would leave undone. Nil when quitting loses nothing.
    var quitWarning: (title: String, detail: String)? {
        if isTripped {
            guard stopsProcesses, !processesStopped else { return nil }
            return (
                "Claude Code processes haven't been stopped yet",
                "Burnrate stops them when it opens again. Until then, agents that ignore the stop hook keep running."
            )
        }
        guard isArmed else { return nil }
        return (
            "The Claude Code stop is armed",
            "While Burnrate is closed, nothing watches Claude Code spend or plan limits, and agents keep running. "
                + "The stop picks up again when Burnrate opens."
        )
    }

    private var warned: Bool
    private var hardStopTask: Task<Void, Never>?
    private let defaults: UserDefaults
    private let notifier: AnomalyMonitor?
    private let flagURL: URL
    private let claudeSettingsURL: URL
    private let stopProcesses: (TimeInterval) async -> Int

    init(
        defaults: UserDefaults = .standard,
        notifier: AnomalyMonitor? = nil,
        flagURL: URL = SpendCapController.defaultFlagURL,
        claudeSettingsURL: URL = SpendCapController.defaultClaudeSettingsURL,
        stopProcesses: @escaping (TimeInterval) async -> Int = { await ClaudeProcesses.stopAll(wait: $0) }
    ) {
        self.defaults = defaults
        self.notifier = notifier
        self.flagURL = flagURL
        self.claudeSettingsURL = claudeSettingsURL
        self.stopProcesses = stopProcesses
        let stored = defaults.double(forKey: Keys.capDollars)
        capDollars = stored > 0 ? stored : SpendCap.defaultDollars
        capEnabled = defaults.object(forKey: Keys.capEnabled) as? Bool ?? true
        planLimitEnabled = defaults.bool(forKey: Keys.planLimitEnabled)
        stopsProcesses = defaults.object(forKey: Keys.stopsProcesses) as? Bool ?? true
        armedAt = defaults.object(forKey: Keys.armedAt) as? Date
        warned = defaults.bool(forKey: Keys.warned)
        trippedAt = defaults.object(forKey: Keys.trippedAt) as? Date
        tripDetail = defaults.string(forKey: Keys.tripDetail)
        processesStopped = defaults.bool(forKey: Keys.processesStopped)
        refreshHookStatus()
        resumePendingHardStop()
    }

    nonisolated static var defaultFlagURL: URL {
        ClaudeTranscriptIndex.defaultCacheURL.deletingLastPathComponent()
            .appendingPathComponent("spend-cap-tripped")
    }

    nonisolated static var defaultClaudeSettingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
    }

    // MARK: Arming

    func arm(now: Date = Date()) {
        hardStopTask?.cancel()
        hardStopTask = nil
        clearFlag()
        armedAt = now
        warned = false
        trippedAt = nil
        tripDetail = nil
        processesStopped = false
        spentCents = nil
        persistState()
    }

    func disarm() {
        hardStopTask?.cancel()
        hardStopTask = nil
        clearFlag()
        armedAt = nil
        warned = false
        trippedAt = nil
        tripDetail = nil
        processesStopped = false
        spentCents = nil
        persistState()
    }

    // MARK: Evaluation

    /// Called after each Claude Code refresh with spend since `armedAt` and the
    /// latest plan windows.
    func evaluate(spentCents: Double?, limits: ClaudeLimits?, now: Date = Date()) async {
        guard isArmed, !isTripped else { return }
        if let spentCents { self.spentCents = spentCents }

        if planLimitEnabled, let limit = SpendCap.usedUpLimit(limits) {
            await trip(.planLimit(limit), now: now)
            return
        }
        guard capEnabled, let spentCents else { return }
        switch SpendCap.step(spentCents: spentCents, capCents: capDollars * 100, warned: warned, tripped: false) {
        case .none:
            return
        case .warn:
            warned = true
            persistState()
            await notifier?.notify(
                title: "Burnrate · spend cap at 80%",
                body: "\(MoneyFormat.estimated(spentCents / 100)) of \(MoneyFormat.dollars(capDollars)) since armed. Claude Code agents stop at the cap."
            )
        case .trip:
            await trip(.spend, now: now)
        }
    }

    private func trip(_ reason: TripReason, now: Date) async {
        trippedAt = now
        let message: String
        let headline: String
        switch reason {
        case .spend:
            let spent = MoneyFormat.estimated((spentCents ?? 0) / 100)
            let cap = MoneyFormat.dollars(capDollars)
            message = SpendCap.stopMessage(spentDollars: spent, capDollars: cap)
            headline = "\(spent) of \(cap) cap reached"
        case .planLimit(let limit):
            message = SpendCap.planLimitStopMessage(limit: limit)
            headline = "\(limit) used up"
        }
        writeFlag(message)

        let graceful = hookInstalled
        let wait = graceful ? SpendCap.graceInterval : 0
        let action: String
        if stopsProcesses {
            action = graceful
                ? "Agents were asked to stop. Processes stop in \(Int(wait / 60)) min."
                : "Stopping Claude Code processes."
        } else {
            action = graceful ? "Agents were asked to stop." : "Install the stop hook so agents can be stopped."
        }
        tripDetail = "\(headline) · \(Self.time(now))"
        persistState()
        await notifier?.notify(title: "Burnrate · stopping Claude Code", body: "\(headline). \(action)")
        if stopsProcesses {
            scheduleHardStop(after: wait)
        }
    }

    private func scheduleHardStop(after delay: TimeInterval) {
        hardStopTask?.cancel()
        hardStopTask = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
            }
            guard let self, !Task.isCancelled, self.isTripped else { return }
            await self.runHardStop()
        }
    }

    /// Stops the processes now, without waiting for the grace period.
    func stopProcessesNow() {
        guard !isStoppingProcesses else { return }
        hardStopTask?.cancel()
        hardStopTask = Task { [weak self] in await self?.runHardStop() }
    }

    private func runHardStop() async {
        isStoppingProcesses = true
        let count = await stopProcesses(SpendCap.killWait)
        isStoppingProcesses = false
        processesStopped = true
        let stopped = count == 1 ? "Stopped 1 Claude Code process" : "Stopped \(count) Claude Code processes"
        if let detail = tripDetail {
            tripDetail = "\(detail) · \(stopped.lowercased())"
        }
        persistState()
        if count > 0 {
            await notifier?.notify(title: "Burnrate · Claude Code stopped", body: "\(stopped).")
        }
    }

    /// A trip from before a relaunch still owes its hard stop.
    private func resumePendingHardStop() {
        guard let trippedAt, stopsProcesses, !processesStopped else { return }
        let elapsed = Date().timeIntervalSince(trippedAt)
        scheduleHardStop(after: max(0, SpendCap.graceInterval - elapsed))
    }

    // MARK: Stop hook

    func refreshHookStatus() {
        hookInstalled = (try? readClaudeSettings()).map(ClaudeStopHook.isInstalled) ?? false
    }

    func installHook() {
        updateClaudeSettings { ClaudeStopHook.installing(into: $0, flagPath: self.flagURL.path) }
    }

    func removeHook() {
        updateClaudeSettings { ClaudeStopHook.removing(from: $0) }
    }

    private func updateClaudeSettings(_ change: ([String: Any]) -> [String: Any]) {
        do {
            let current = try readClaudeSettings()
            let next = change(current)
            let fm = FileManager.default
            try fm.createDirectory(at: claudeSettingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: claudeSettingsURL.path) {
                let backup = claudeSettingsURL.appendingPathExtension("burnrate-backup")
                try? fm.removeItem(at: backup)
                try fm.copyItem(at: claudeSettingsURL, to: backup)
            }
            let data = try JSONSerialization.data(
                withJSONObject: next,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            )
            try data.write(to: claudeSettingsURL, options: .atomic)
            hookError = nil
        } catch {
            hookError = "Could not update ~/.claude/settings.json: \(error.localizedDescription)"
        }
        refreshHookStatus()
    }

    /// Missing file reads as empty settings. Unparseable JSON throws so it is never overwritten.
    private func readClaudeSettings() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: claudeSettingsURL.path) else { return [:] }
        let data = try Data(contentsOf: claudeSettingsURL)
        if data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) { return [:] }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return object
    }

    // MARK: Persistence

    private func writeFlag(_ message: String) {
        try? FileManager.default.createDirectory(
            at: flagURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? message.write(to: flagURL, atomically: true, encoding: .utf8)
    }

    private func clearFlag() {
        try? FileManager.default.removeItem(at: flagURL)
    }

    private func persistState() {
        defaults.set(armedAt, forKey: Keys.armedAt)
        defaults.set(warned, forKey: Keys.warned)
        defaults.set(trippedAt, forKey: Keys.trippedAt)
        defaults.set(tripDetail, forKey: Keys.tripDetail)
        defaults.set(processesStopped, forKey: Keys.processesStopped)
    }

    nonisolated static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}
