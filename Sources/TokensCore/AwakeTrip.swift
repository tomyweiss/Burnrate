import Foundation

/// Decides when a closed-lid awake trip keeps going, and when sleep must come back.
public enum AwakeTrip {
    public static let durationChoices: [Int] = [30 * 60, 45 * 60, 90 * 60]
    public static let batteryCutoffPercent = 20
    public static let pollInterval: TimeInterval = 1

    public enum Thermal: Equatable, Sendable {
        case nominal
        case fair
        case serious
        case critical

        public static var current: Self {
            switch ProcessInfo.processInfo.thermalState {
            case .nominal: .nominal
            case .fair: .fair
            case .serious: .serious
            case .critical: .critical
            @unknown default: .critical
            }
        }
    }

    public enum Power: Equatable, Sendable {
        case battery(percent: Int)
        case ac(percent: Int)
    }

    public struct Sample: Equatable, Sendable {
        public var now: Date
        public var deadline: Date
        public var cancelRequested: Bool
        public var thermal: Thermal
        public var power: Power

        public init(
            now: Date,
            deadline: Date,
            cancelRequested: Bool,
            thermal: Thermal,
            power: Power
        ) {
            self.now = now
            self.deadline = deadline
            self.cancelRequested = cancelRequested
            self.thermal = thermal
            self.power = power
        }
    }

    public enum StopReason: String, Codable, Equatable, Sendable {
        case timer
        case cancelled
        case heat
        case battery
    }

    public enum Decision: Equatable, Sendable {
        case continueTrip
        case stop(StopReason)
    }

    public struct Marker: Equatable, Sendable {
        public var pid: Int32
        public var deadline: Date

        public init(pid: Int32, deadline: Date) {
            self.pid = pid
            self.deadline = deadline
        }
    }

    public enum Repair: Equatable, Sendable {
        case idle
        case sessionRunning
        case askToRestoreSleep
        case leaveForeignSwitchAlone
    }

    public enum StartBlock: Equatable, Sendable {
        case alreadyRunning
        case restoreRequired
        case foreignSwitch
    }

    public enum SwitchError: Error, Equatable {
        case failed
    }

    public static func durationLabel(_ seconds: Int) -> String {
        "\(seconds / 60) min"
    }

    public static func isAllowedDuration(_ seconds: Int) -> Bool {
        durationChoices.contains(seconds)
    }

    /// Cancel wins, then heat, then a low battery, then the timer.
    public static func decide(_ sample: Sample) -> Decision {
        if sample.cancelRequested {
            return .stop(.cancelled)
        }
        switch sample.thermal {
        case .serious, .critical:
            return .stop(.heat)
        case .nominal, .fair:
            break
        }
        if case .battery(let percent) = sample.power, percent <= batteryCutoffPercent {
            return .stop(.battery)
        }
        if sample.now >= sample.deadline {
            return .stop(.timer)
        }
        return .continueTrip
    }

    /// A marker means this app turned sleep off. A live pid means that trip is still ours.
    public static func repair(marker: Marker?, pidAlive: Bool, sleepDisabled: Bool) -> Repair {
        if marker != nil, pidAlive {
            return .sessionRunning
        }
        if marker != nil, sleepDisabled {
            return .askToRestoreSleep
        }
        if marker == nil, sleepDisabled {
            return .leaveForeignSwitchAlone
        }
        return .idle
    }

    public static func startBlock(for repair: Repair) -> StartBlock? {
        switch repair {
        case .idle:
            nil
        case .sessionRunning:
            .alreadyRunning
        case .askToRestoreSleep:
            .restoreRequired
        case .leaveForeignSwitchAlone:
            .foreignSwitch
        }
    }

    public static func parseSleepDisabled(_ pmset: String) -> Bool? {
        for line in pmset.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard fields.count >= 2, fields[0] == "SleepDisabled" else { continue }
            switch fields[1] {
            case "1": return true
            case "0": return false
            default: return nil
            }
        }
        return nil
    }

    public static func parsePower(_ pmsetBatt: String) -> Power? {
        guard let percent = firstPercent(in: pmsetBatt) else { return nil }
        if pmsetBatt.contains("Battery Power") {
            return .battery(percent: percent)
        }
        if pmsetBatt.contains("AC Power") || pmsetBatt.contains("UPS Power") {
            return .ac(percent: percent)
        }
        return nil
    }

    /// Turns sleep off, polls until `decide` says stop, then turns sleep back on.
    /// A failed `disableSleep` leaves the switch untouched.
    public static func run(
        deadline: Date,
        now: () -> Date,
        isCancelled: () -> Bool,
        thermal: () -> Thermal,
        power: () -> Power,
        disableSleep: () throws -> Void,
        enableSleep: () -> Void,
        wait: (TimeInterval) -> Void
    ) throws -> StopReason {
        try disableSleep()
        defer { enableSleep() }
        while true {
            let decision = decide(
                Sample(
                    now: now(),
                    deadline: deadline,
                    cancelRequested: isCancelled(),
                    thermal: thermal(),
                    power: power()
                )
            )
            if case .stop(let reason) = decision {
                return reason
            }
            wait(pollInterval)
        }
    }

    public static let adminPrompt = "Burnrate keeps this Mac awake until the timer ends, then turns sleep back on."
    public static let restorePrompt = "Burnrate turns sleep back on after an interrupted trip."

    public struct SessionFile: Codable, Equatable, Sendable {
        public var pid: Int32
        public var deadline: Date
        public var phase: Phase
        public var stopReason: StopReason?

        public init(pid: Int32, deadline: Date, phase: Phase, stopReason: StopReason?) {
            self.pid = pid
            self.deadline = deadline
            self.phase = phase
            self.stopReason = stopReason
        }

        public enum Phase: String, Codable, Equatable, Sendable {
            case running
            case stopped
        }
    }

    public struct StopFile: Codable, Equatable, Sendable {
        public var stopReason: StopReason

        public init(stopReason: StopReason) {
            self.stopReason = stopReason
        }
    }

    public static func remainingLabel(until deadline: Date, now: Date) -> String {
        let seconds = Int(deadline.timeIntervalSince(now).rounded(.up))
        if seconds <= 0 { return "0m" }
        if seconds < 60 { return "\(seconds)s" }
        let minutes = Int((Double(seconds) / 60).rounded(.up))
        return "\(minutes)m"
    }

    public static func stopMessage(_ reason: StopReason) -> String {
        switch reason {
        case .timer:
            "Sleep is back on. The timer ended."
        case .cancelled:
            "Sleep is back on."
        case .heat:
            "Sleep is back on. The Mac got hot."
        case .battery:
            "Sleep is back on. The battery reached \(batteryCutoffPercent)%."
        }
    }

    /// The session directory is the only place the root process may write.
    public static func isSessionDirectory(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        return url.path.hasPrefix("/") && url.lastPathComponent == "awake"
    }

    public static func keepAwakeScript(executable: String, seconds: Int, directory: String) -> String {
        """
        do shell script quoted form of \(appleQuoted(executable)) & " --keep-awake --seconds \(seconds) --directory " & quoted form of \(appleQuoted(directory)) with administrator privileges with prompt \(appleQuoted(adminPrompt))
        """
    }

    public static func restoreSleepScript() -> String {
        """
        do shell script "/usr/bin/pmset -a disablesleep 0" with administrator privileges with prompt \(appleQuoted(restorePrompt))
        """
    }

    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(value)
    }

    public static func decodeSession(_ data: Data) -> SessionFile? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(SessionFile.self, from: data)
    }

    public static func decodeStop(_ data: Data) -> StopFile? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(StopFile.self, from: data)
    }

    private static func appleQuoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private static func firstPercent(in text: String) -> Int? {
        guard let range = text.range(of: #"\d+%"#, options: .regularExpression) else { return nil }
        let digits = text[range].dropLast()
        return Int(digits)
    }
}
