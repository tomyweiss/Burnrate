import AppKit
import Darwin
import Foundation
import TokensCore

@MainActor
enum AwakeQuit {
    static weak var controller: AwakeSessionController?
}

@MainActor
final class BurnrateAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AwakeQuit.controller?.restoreIfNeeded()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let controller = AwakeQuit.controller, controller.holdsAwake else {
            return .terminateNow
        }
        controller.stop()
        Task { @MainActor in
            for _ in 0..<40 {
                controller.refresh()
                if !controller.holdsAwake { break }
                try? await Task.sleep(for: .milliseconds(200))
            }
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

/// Menu-bar side of a closed-lid trip. The root process owns the sleep switch.
@MainActor
@Observable
final class AwakeSessionController {
    private(set) var isRunning = false
    private(set) var isLaunching = false
    private(set) var deadline: Date?
    private(set) var lastStopMessage: String?
    private(set) var tick = Date()

    var holdsAwake: Bool { isRunning || isLaunching }

    var remainingLabel: String? {
        guard isRunning, let deadline else { return nil }
        return AwakeTrip.remainingLabel(until: deadline, now: tick)
    }

    private var clock: Task<Void, Never>?
    private var didOfferRestore = false
    private let defaults: UserDefaults
    private let warningKey = "lidAwakeWarningConfirmed"
    private let customDurationKey = "lidAwakeCustomDuration"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        clock = Task { @MainActor in
            while !Task.isCancelled {
                self.tick = Date()
                self.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func start(seconds: Int) {
        guard AwakeTrip.isAllowedDuration(seconds) else { return }
        refresh()
        if let block = AwakeTrip.startBlock(for: currentRepair()) {
            present(block)
            return
        }
        guard confirmWarning() else { return }

        let directory = Self.directory
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            presentFailure()
            return
        }
        try? FileManager.default.removeItem(at: Self.cancelURL)
        try? FileManager.default.removeItem(at: Self.resultURL)

        let executable = Bundle.main.executableURL?.path ?? CommandLine.arguments[0]
        let script = AwakeTrip.keepAwakeScript(
            executable: executable,
            seconds: seconds,
            directory: directory.path
        )
        isLaunching = true
        lastStopMessage = nil
        Task.detached {
            let result = PrivilegedShell.run(script)
            await self.finishLaunch(result)
        }
    }

    /// Asks for a trip length. Returns seconds, or nil when the person cancels.
    func askCustomDuration() -> Int? {
        MenuBarPanelKeeper.hidePanelsForModalAlert()
        defer { MenuBarPanelKeeper.restorePanelsAfterModalAlert() }
        NSApp.activate()
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.placeholderString = "2h, 1h30, or 75"
        field.stringValue = defaults.string(forKey: customDurationKey) ?? ""
        let alert = NSAlert()
        alert.messageText = "Keep awake for how long?"
        alert.informativeText = "5 minutes to 8 hours."
        alert.accessoryView = field
        alert.addButton(withTitle: "Start")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        while alert.runModal() == .alertFirstButtonReturn {
            let text = field.stringValue.trimmingCharacters(in: .whitespaces)
            if let seconds = AwakeTrip.parseDuration(text), AwakeTrip.isAllowedDuration(seconds) {
                defaults.set(text, forKey: customDurationKey)
                return seconds
            }
            alert.informativeText = "Enter 5 minutes to 8 hours, like 2h, 1h30, or 75."
        }
        return nil
    }

    func stop() {
        let directory = Self.directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: Self.cancelURL.path, contents: Data("stop".utf8))
    }

    func restoreIfNeeded() {
        refresh()
        guard !didOfferRestore, currentRepair() == .askToRestoreSleep else { return }
        didOfferRestore = true
        let turnOn = confirm(
            "Sleep is still off",
            "An interrupted trip left sleep turned off. Turn it back on?",
            confirmTitle: "Turn sleep on",
            cancelTitle: "Not now"
        )
        guard turnOn else { return }
        turnSleepOn(AwakeTrip.restoreSleepScript())
    }

    private func turnSleepOn(_ script: String) {
        Task.detached {
            let result = PrivilegedShell.run(script)
            await self.finishRestore(result)
        }
    }

    func refresh() {
        if let stop = Self.readStop() {
            lastStopMessage = AwakeTrip.stopMessage(stop.stopReason)
            try? FileManager.default.removeItem(at: Self.resultURL)
        }

        guard let session = Self.readSession() else {
            isRunning = false
            deadline = nil
            return
        }

        if Pid.isAlive(session.pid) {
            isRunning = true
            isLaunching = false
            deadline = session.deadline
            return
        }

        let disabled = PowerSettings.isSleepDisabled ?? false
        let repair = AwakeTrip.repair(
            marker: AwakeTrip.Marker(pid: session.pid, deadline: session.deadline),
            pidAlive: false,
            sleepDisabled: disabled
        )
        isRunning = false
        deadline = nil
        if repair == .idle {
            try? FileManager.default.removeItem(at: Self.statusURL)
        }
    }

    private func finishLaunch(_ result: PrivilegedShell.Result) {
        isLaunching = false
        refresh()
        if result == .failed, !isRunning {
            presentFailure()
        }
    }

    private func finishRestore(_ result: PrivilegedShell.Result) {
        refresh()
        if result == .finished, PowerSettings.isSleepDisabled != true {
            try? FileManager.default.removeItem(at: Self.statusURL)
            lastStopMessage = "Sleep is back on."
        } else if result == .failed {
            presentFailure()
        }
    }

    private func currentRepair() -> AwakeTrip.Repair {
        guard let session = Self.readSession() else {
            let disabled = PowerSettings.isSleepDisabled ?? false
            return AwakeTrip.repair(marker: nil, pidAlive: false, sleepDisabled: disabled)
        }
        let alive = Pid.isAlive(session.pid)
        let disabled = alive ? true : (PowerSettings.isSleepDisabled ?? false)
        return AwakeTrip.repair(
            marker: AwakeTrip.Marker(pid: session.pid, deadline: session.deadline),
            pidAlive: alive,
            sleepDisabled: disabled
        )
    }

    private func present(_ block: AwakeTrip.StartBlock) {
        switch block {
        case .alreadyRunning:
            break
        case .restoreRequired:
            restoreIfNeeded()
        case .foreignSwitch:
            let turnOn = confirm(
                "Sleep is already off",
                "Another app turned sleep off, so this Mac already stays awake. Turn sleep back on? You can start a trip after that.",
                confirmTitle: "Turn sleep on",
                cancelTitle: "Leave it off"
            )
            if turnOn {
                turnSleepOn(AwakeTrip.restoreSleepScript(prompt: AwakeTrip.foreignRestorePrompt))
            }
        }
    }

    private func presentFailure() {
        inform("Burnrate couldn't change sleep", "macOS refused the sleep switch.")
    }

    private func inform(_ title: String, _ body: String) {
        MenuBarPanelKeeper.hidePanelsForModalAlert()
        defer { MenuBarPanelKeeper.restorePanelsAfterModalAlert() }
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func confirmWarning() -> Bool {
        if defaults.bool(forKey: warningKey) { return true }
        let accepted = confirm(
            "This Mac stays awake with the lid closed",
            "Burnrate turns sleep off for the time you pick, including on battery. A Mac running in a bag gets hot. Sleep comes back if the Mac gets hot, the battery reaches 20% while unplugged, the timer ends, or you press Stop. Cursor still needs a network, such as a phone hotspot. If a trip is interrupted, Burnrate asks for your password the next time it opens so it can turn sleep back on.",
            confirmTitle: "Keep awake"
        )
        if accepted {
            defaults.set(true, forKey: warningKey)
        }
        return accepted
    }

    private func confirm(
        _ title: String,
        _ body: String,
        confirmTitle: String,
        cancelTitle: String = "Cancel"
    ) -> Bool {
        MenuBarPanelKeeper.hidePanelsForModalAlert()
        defer { MenuBarPanelKeeper.restorePanelsAfterModalAlert() }
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        alert.addButton(withTitle: confirmTitle)
        alert.addButton(withTitle: cancelTitle)
        return alert.runModal() == .alertFirstButtonReturn
    }

    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let id = Bundle.main.bundleIdentifier ?? AppIdentity.productionBundleIdentifier
        return base
            .appendingPathComponent(id, isDirectory: true)
            .appendingPathComponent("awake", isDirectory: true)
    }

    private static var statusURL: URL { directory.appendingPathComponent("status.json") }
    private static var cancelURL: URL { directory.appendingPathComponent("cancel") }
    private static var resultURL: URL { directory.appendingPathComponent("result.json") }

    private static func readSession() -> AwakeTrip.SessionFile? {
        guard let data = try? Data(contentsOf: statusURL) else { return nil }
        return AwakeTrip.decodeSession(data)
    }

    private static func readStop() -> AwakeTrip.StopFile? {
        guard let data = try? Data(contentsOf: resultURL) else { return nil }
        return AwakeTrip.decodeStop(data)
    }
}

private enum Pid {
    static func isAlive(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }
}
