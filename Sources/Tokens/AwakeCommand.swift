import Darwin
import Foundation
import TokensCore

/// `Tokens --keep-awake` runs as root for one trip, then turns sleep back on.
enum AwakeCommand {
    static func runAndExit() -> Never {
        exit(run())
    }

    static func run() -> Int32 {
        guard getuid() == 0 else {
            fputs("Burnrate keep-awake must run as root.\n", stderr)
            return 1
        }
        guard
            let secondsText = argument("--seconds"),
            let seconds = Int(secondsText),
            AwakeTrip.isAllowedDuration(seconds),
            let directory = argument("--directory"),
            AwakeTrip.isSessionDirectory(directory)
        else {
            fputs("Usage: Tokens --keep-awake --seconds 1800|2700|5400 --directory /path/awake\n", stderr)
            return 2
        }

        let directoryURL = URL(fileURLWithPath: directory, isDirectory: true).standardizedFileURL
        let statusURL = directoryURL.appendingPathComponent("status.json")
        let cancelURL = directoryURL.appendingPathComponent("cancel")
        let resultURL = directoryURL.appendingPathComponent("result.json")
        let files = FileManager.default
        do {
            try files.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        } catch {
            return 1
        }

        let deadline = Date().addingTimeInterval(TimeInterval(seconds))
        let pid = ProcessInfo.processInfo.processIdentifier
        let session = AwakeTrip.SessionFile(pid: pid, deadline: deadline, phase: .running, stopReason: nil)
        guard let data = try? AwakeTrip.encode(session) else { return 1 }
        guard write(data, to: statusURL) else { return 1 }

        if files.fileExists(atPath: cancelURL.path) {
            try? files.removeItem(at: statusURL)
            return 0
        }

        let cancel = CancelFlag()
        let term = installTerminationHandler(cancel)
        defer { term.cancel() }

        let reason: AwakeTrip.StopReason
        do {
            reason = try AwakeTrip.run(
                deadline: deadline,
                now: Date.init,
                isCancelled: { cancel.isSet || files.fileExists(atPath: cancelURL.path) },
                thermal: { .current },
                power: { PowerSettings.current() },
                disableSleep: { try PowerSettings.disableSleep() },
                enableSleep: { PowerSettings.enableSleep() },
                wait: { Thread.sleep(forTimeInterval: $0) }
            )
        } catch {
            // disableSleep throws only when the switch was left unchanged.
            try? files.removeItem(at: statusURL)
            return 1
        }

        if PowerSettings.isSleepDisabled == true {
            let stuck = AwakeTrip.SessionFile(
                pid: pid,
                deadline: deadline,
                phase: .stopped,
                stopReason: reason
            )
            if let stuckData = try? AwakeTrip.encode(stuck) {
                write(stuckData, to: statusURL)
            }
            return 1
        }

        if let result = try? AwakeTrip.encode(AwakeTrip.StopFile(stopReason: reason)) {
            write(result, to: resultURL)
        }
        try? files.removeItem(at: statusURL)
        try? files.removeItem(at: cancelURL)
        return 0
    }

    @discardableResult
    private static func write(_ data: Data, to url: URL) -> Bool {
        do {
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
            return true
        } catch {
            return false
        }
    }

    private static func argument(_ name: String) -> String? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: name), args.index(after: index) < args.endIndex else {
            return nil
        }
        return args[args.index(after: index)]
    }

    private static func installTerminationHandler(_ cancel: CancelFlag) -> DispatchSourceSignal {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .global())
        source.setEventHandler { cancel.set() }
        source.resume()
        return source
    }
}

enum PowerSettings {
    static var isSleepDisabled: Bool? {
        AwakeTrip.parseSleepDisabled(capture("/usr/bin/pmset", ["-g"]))
    }

    static func current() -> AwakeTrip.Power {
        if let power = AwakeTrip.parsePower(capture("/usr/bin/pmset", ["-g", "batt"])) {
            return power
        }
        return .battery(percent: 0)
    }

    /// Leaves the switch unchanged when it throws.
    static func disableSleep() throws {
        if isSleepDisabled == true {
            throw AwakeTrip.SwitchError.failed
        }
        guard run("/usr/bin/pmset", ["-a", "disablesleep", "1"]) == 0, isSleepDisabled == true else {
            if isSleepDisabled == true {
                _ = run("/usr/bin/pmset", ["-a", "disablesleep", "0"])
            }
            throw AwakeTrip.SwitchError.failed
        }
    }

    static func enableSleep() {
        _ = run("/usr/bin/pmset", ["-a", "disablesleep", "0"])
    }

    private static func capture(_ launchPath: String, _ arguments: [String]) -> String {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return "" }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    @discardableResult
    private static func run(_ launchPath: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return 1 }
        process.waitUntilExit()
        return process.terminationStatus
    }
}

enum PrivilegedShell {
    enum Result: Equatable {
        case finished
        case cancelled
        case failed
    }

    static func run(_ source: String) -> Result {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        process.standardOutput = pipe
        process.standardError = pipe
        guard (try? process.run()) != nil else { return .failed }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        if process.terminationStatus == 0 { return .finished }
        if text.localizedCaseInsensitiveContains("User canceled") || text.contains("-128") {
            return .cancelled
        }
        return .failed
    }
}

private final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func set() {
        lock.lock()
        value = true
        lock.unlock()
    }

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
