import Foundation
import Testing
@testable import TokensCore

private func sample(
    now: Date = Date(timeIntervalSince1970: 1_000),
    remaining: TimeInterval = 60,
    cancelRequested: Bool = false,
    thermal: AwakeTrip.Thermal = .fair,
    power: AwakeTrip.Power = .battery(percent: 80)
) -> AwakeTrip.Sample {
    AwakeTrip.Sample(
        now: now,
        deadline: now.addingTimeInterval(remaining),
        cancelRequested: cancelRequested,
        thermal: thermal,
        power: power
    )
}

@Test func awakeTripContinuesWhileTheLidTripIsHealthy() {
    #expect(AwakeTrip.decide(sample()) == .continueTrip)
}

@Test func awakeTripStopsWhenTheTimerEnds() {
    let now = Date(timeIntervalSince1970: 1_000)
    #expect(AwakeTrip.decide(sample(now: now, remaining: 0)) == .stop(.timer))
    #expect(AwakeTrip.decide(sample(now: now, remaining: -1)) == .stop(.timer))
}

@Test func awakeTripStopsWhenTheUserCancels() {
    #expect(AwakeTrip.decide(sample(cancelRequested: true)) == .stop(.cancelled))
}

@Test func awakeTripStopsWhenTheMacGetsHot() {
    #expect(AwakeTrip.decide(sample(thermal: .serious)) == .stop(.heat))
    #expect(AwakeTrip.decide(sample(thermal: .critical)) == .stop(.heat))
}

@Test func awakeTripKeepsGoingWhenTheMacIsOnlyWarm() {
    #expect(AwakeTrip.decide(sample(thermal: .nominal)) == .continueTrip)
    #expect(AwakeTrip.decide(sample(thermal: .fair)) == .continueTrip)
}

@Test func awakeTripStopsAtTwentyPercentOnBattery() {
    #expect(AwakeTrip.decide(sample(power: .battery(percent: 20))) == .stop(.battery))
    #expect(AwakeTrip.decide(sample(power: .battery(percent: 19))) == .stop(.battery))
    #expect(AwakeTrip.decide(sample(power: .battery(percent: 21))) == .continueTrip)
}

@Test func awakeTripKeepsGoingAtALowChargeWhilePluggedIn() {
    #expect(AwakeTrip.decide(sample(power: .ac(percent: 20))) == .continueTrip)
    #expect(AwakeTrip.decide(sample(power: .ac(percent: 5))) == .continueTrip)
}

@Test func awakeTripPrefersCancelOverHeatAndTheTimer() {
    let now = Date(timeIntervalSince1970: 1_000)
    let decision = AwakeTrip.decide(
        sample(now: now, remaining: 0, cancelRequested: true, thermal: .critical)
    )
    #expect(decision == .stop(.cancelled))
}

@Test func awakeTripRepairFollowsWhoOwnsTheSleepSwitch() {
    let marker = AwakeTrip.Marker(pid: 42, deadline: Date(timeIntervalSince1970: 2_000))

    #expect(AwakeTrip.repair(marker: marker, pidAlive: true, sleepDisabled: true) == .sessionRunning)
    #expect(AwakeTrip.repair(marker: marker, pidAlive: true, sleepDisabled: false) == .sessionRunning)
    #expect(AwakeTrip.repair(marker: marker, pidAlive: false, sleepDisabled: true) == .askToRestoreSleep)
    #expect(AwakeTrip.repair(marker: marker, pidAlive: false, sleepDisabled: false) == .idle)
    #expect(AwakeTrip.repair(marker: nil, pidAlive: false, sleepDisabled: true) == .leaveForeignSwitchAlone)
    #expect(AwakeTrip.repair(marker: nil, pidAlive: false, sleepDisabled: false) == .idle)
}

@Test func awakeTripStartGateBlocksASecondOwner() {
    #expect(AwakeTrip.startBlock(for: .idle) == nil)
    #expect(AwakeTrip.startBlock(for: .sessionRunning) == .alreadyRunning)
    #expect(AwakeTrip.startBlock(for: .askToRestoreSleep) == .restoreRequired)
    #expect(AwakeTrip.startBlock(for: .leaveForeignSwitchAlone) == .foreignSwitch)
}

@Test func awakeTripRestoreScriptNamesWhySleepComesBack() {
    #expect(AwakeTrip.restoreSleepScript().contains(AwakeTrip.restorePrompt))
    let foreign = AwakeTrip.restoreSleepScript(prompt: AwakeTrip.foreignRestorePrompt)
    #expect(foreign.contains("/usr/bin/pmset -a disablesleep 0"))
    #expect(foreign.contains(AwakeTrip.foreignRestorePrompt))
}

@Test func awakeTripReadsTheLivePmsetShapes() {
    let settings = """
    System-wide power settings:
     SleepDisabled\t\t0
    Currently in use:
     sleep                1 (sleep prevented by Cursor, powerd)
    """
    #expect(AwakeTrip.parseSleepDisabled(settings) == false)

    let disabled = settings.replacingOccurrences(of: "SleepDisabled\t\t0", with: "SleepDisabled\t\t1")
    #expect(AwakeTrip.parseSleepDisabled(disabled) == true)
    #expect(AwakeTrip.parseSleepDisabled("no sleep line") == nil)

    let charging = """
    Now drawing from 'AC Power'
     -InternalBattery-0 (id=25165923)\t29%; charging; 2:10 remaining present: true
    """
    #expect(AwakeTrip.parsePower(charging) == .ac(percent: 29))

    let battery = """
    Now drawing from 'Battery Power'
     -InternalBattery-0 (id=25165923)\t19%; discharging; 1:10 remaining present: true
    """
    #expect(AwakeTrip.parsePower(battery) == .battery(percent: 19))
    #expect(AwakeTrip.parsePower("no battery") == nil)
}

@Test func awakeTripLoopTurnsSleepBackOnWhenHeatStopsTheTrip() throws {
    var sleepDisabled = false
    var enableCount = 0
    var polls = 0
    let now = Date(timeIntervalSince1970: 1_000)
    let reason = try AwakeTrip.run(
        deadline: now.addingTimeInterval(600),
        now: { now },
        isCancelled: { false },
        thermal: {
            polls += 1
            return polls == 1 ? .fair : .serious
        },
        power: { .battery(percent: 80) },
        disableSleep: { sleepDisabled = true },
        enableSleep: {
            sleepDisabled = false
            enableCount += 1
        },
        wait: { _ in }
    )
    #expect(reason == .heat)
    #expect(sleepDisabled == false)
    #expect(enableCount == 1)
    #expect(polls == 2)
}

@Test func awakeTripLoopLeavesSleepAloneWhenTheSwitchFails() {
    var enableCount = 0
    #expect(throws: AwakeTrip.SwitchError.self) {
        try AwakeTrip.run(
            deadline: Date(timeIntervalSince1970: 2_000),
            now: { Date(timeIntervalSince1970: 1_000) },
            isCancelled: { false },
            thermal: { .nominal },
            power: { .battery(percent: 80) },
            disableSleep: { throw AwakeTrip.SwitchError.failed },
            enableSleep: { enableCount += 1 },
            wait: { _ in }
        )
    }
    #expect(enableCount == 0)
}

@Test func awakeTripPrefersHeatOverALowBattery() {
    let decision = AwakeTrip.decide(sample(thermal: .serious, power: .battery(percent: 10)))
    #expect(decision == .stop(.heat))
}

@Test func awakeTripLabelsTheTimeLeftAndTheReasonSleepReturned() {
    let deadline = Date(timeIntervalSince1970: 1_000)
    #expect(AwakeTrip.remainingLabel(until: deadline, now: deadline.addingTimeInterval(-125)) == "3m")
    #expect(AwakeTrip.remainingLabel(until: deadline, now: deadline.addingTimeInterval(-20)) == "20s")
    #expect(AwakeTrip.remainingLabel(until: deadline, now: deadline) == "0m")
    #expect(AwakeTrip.stopMessage(.heat) == "Sleep is back on. The Mac got hot.")
    #expect(AwakeTrip.stopMessage(.battery) == "Sleep is back on. The battery reached 20%.")
}

@Test func awakeTripScriptQuotesTheExecutableAndTheSessionDirectory() {
    let script = AwakeTrip.keepAwakeScript(
        executable: "/Applications/Burnrate.app/Contents/MacOS/Tokens",
        seconds: 1_800,
        directory: "/Users/tom/Library/Application Support/com.tomyweiss.burnrate/awake"
    )
    #expect(script.contains("quoted form of \"/Applications/Burnrate.app/Contents/MacOS/Tokens\""))
    #expect(script.contains("--seconds 1800"))
    #expect(script.contains("quoted form of \"/Users/tom/Library/Application Support/com.tomyweiss.burnrate/awake\""))
    #expect(script.contains("with administrator privileges"))

    let quoted = AwakeTrip.keepAwakeScript(executable: "/tmp/a\"b", seconds: 1_800, directory: "/tmp/awake")
    #expect(quoted.contains(#""/tmp/a\"b""#))
    #expect(AwakeTrip.isSessionDirectory("/tmp/awake"))
    #expect(AwakeTrip.isSessionDirectory("/tmp/foo/../awake"))
    #expect(!AwakeTrip.isSessionDirectory("/tmp/awake-extra"))
    #expect(!AwakeTrip.isSessionDirectory("/tmp/awake/../etc"))
}

@Test func awakeTripSessionFileRoundTrips() throws {
    let file = AwakeTrip.SessionFile(
        pid: 42,
        deadline: Date(timeIntervalSince1970: 1_700_000_000),
        phase: .running,
        stopReason: nil
    )
    let data = try AwakeTrip.encode(file)
    #expect(AwakeTrip.decodeSession(data) == file)
}

@Test func awakeTripOffersThirtyFortyFiveAndNinetyMinutes() {
    #expect(AwakeTrip.durationChoices == [1_800, 2_700, 5_400])
    #expect(AwakeTrip.durationLabel(1_800) == "30 min")
    #expect(AwakeTrip.durationLabel(2_700) == "45 min")
    #expect(AwakeTrip.durationLabel(5_400) == "90 min")
    #expect(AwakeTrip.isAllowedDuration(2_700))
    #expect(!AwakeTrip.isAllowedDuration(60))
}

@Test func awakeTripAllowsCustomTripsInWholeMinutesUpToEightHours() {
    #expect(AwakeTrip.isAllowedDuration(5 * 60))
    #expect(AwakeTrip.isAllowedDuration(8 * 60 * 60))
    #expect(!AwakeTrip.isAllowedDuration(4 * 60))
    #expect(!AwakeTrip.isAllowedDuration(8 * 60 * 60 + 60))
    #expect(!AwakeTrip.isAllowedDuration(10 * 60 + 30))
}

@Test func awakeTripReadsTypedDurations() {
    #expect(AwakeTrip.parseDuration("75") == 75 * 60)
    #expect(AwakeTrip.parseDuration("45m") == 45 * 60)
    #expect(AwakeTrip.parseDuration(" 45 min ") == 45 * 60)
    #expect(AwakeTrip.parseDuration("2h") == 2 * 3_600)
    #expect(AwakeTrip.parseDuration("1h30") == 90 * 60)
    #expect(AwakeTrip.parseDuration("1H 30M") == 90 * 60)
    #expect(AwakeTrip.parseDuration("1:05") == 65 * 60)
    #expect(AwakeTrip.parseDuration("1:75") == nil)
    #expect(AwakeTrip.parseDuration("1h75") == nil)
    #expect(AwakeTrip.parseDuration("0") == nil)
    #expect(AwakeTrip.parseDuration("") == nil)
    #expect(AwakeTrip.parseDuration("soon") == nil)
}

@Test func awakeTripShowsLongTripsInHours() {
    let deadline = Date(timeIntervalSince1970: 10_000)
    #expect(AwakeTrip.remainingLabel(until: deadline, now: deadline.addingTimeInterval(-3_600)) == "1h")
    #expect(AwakeTrip.remainingLabel(until: deadline, now: deadline.addingTimeInterval(-5_000)) == "1h 24m")
}
