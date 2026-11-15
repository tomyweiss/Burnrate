import SwiftUI
import AppKit

@main
struct TokensApp: App {
    @State private var settings: SettingsStore
    @State private var store: UsageStore
    @State private var claudeCodeStore: ClaudeCodeStore
    @State private var updates: UpdateManager
    @State private var community: CommunityStore
    @State private var interactionTracker: InteractionTracker

    init() {
        if CommandLine.arguments.contains("--status") {
            Self.runStatusAndExit()
        }

        let settings = SettingsStore()
        FailureReporter.isEnabled = { true }
        let interactionTracker = InteractionTracker()
        let anomalyMonitor = AnomalyMonitor()
        let store = UsageStore(settings: settings, anomalyMonitor: anomalyMonitor)
        let claudeCodeStore = ClaudeCodeStore(settings: settings, anomalyMonitor: anomalyMonitor)
        claudeCodeStore.setInstalledObserver { installed in
            store.noteClaudeCodeInstalled(installed)
        }
        let community = CommunityStore(settings: settings, interactionTracker: interactionTracker)
        store.setCommunityStore(community)
        community.setUsageStore(store)
        Task { await community.migrateNicknameToCursorDefaultIfNeeded() }
        store.start()
        claudeCodeStore.start()
        _settings = State(initialValue: settings)
        _store = State(initialValue: store)
        _claudeCodeStore = State(initialValue: claudeCodeStore)
        _updates = State(initialValue: UpdateManager(settings: settings))
        _community = State(initialValue: community)
        _interactionTracker = State(initialValue: interactionTracker)
    }

    private static func runStatusAndExit() -> Never {
        final class Box: @unchecked Sendable {
            var code: Int32 = 1
            var message = "ERROR Timed out fetching usage"
        }
        let box = Box()
        let group = DispatchGroup()
        group.enter()
        let settings = SettingsStore()

        Task.detached {
            defer { group.leave() }
            do {
                let credentials = try TokenProvider.loadSessionCredentials()
                let api = CursorAPI()
                let now = Date()
                let window = settings.usageWindow
                let range = window.dateRange(now: now)
                let startMs = Int64(range.start.timeIntervalSince1970 * 1000)
                let endMs = Int64(range.end.timeIntervalSince1970 * 1000)
                let events = try await api.fetchUsageEvents(
                    credentials: credentials,
                    startMs: startMs,
                    endMs: endMs
                )
                let snapshot = Aggregator.snapshot(
                    events: events,
                    now: now,
                    window: window,
                    recentWindowMinutes: settings.anomalyWindowMinutes
                )
                box.message = String(
                    format: "OK %@ %@ (%d events)",
                    MoneyFormat.dollars(snapshot.windowDollars),
                    window.displayName.lowercased(),
                    snapshot.eventCount
                )
                box.code = 0
            } catch {
                box.message = "ERROR \(error.localizedDescription)"
                box.code = 1
            }
        }

        _ = group.wait(timeout: .now() + 30)
        print(box.message)
        exit(box.code)
    }

    var body: some Scene {
        MenuBarExtra {
            RootPanel(
                store: store,
                settings: settings,
                updates: updates,
                community: community,
                interactionTracker: interactionTracker
            )
                .environment(claudeCodeStore)
                .onAppear {
                    store.start()
                    claudeCodeStore.start()
                    updates.autoCheckIfNeeded()
                }
        } label: {
            menuBarLabel
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarLabel: some View {
        let bar = menuBarPresentation
        return Label {
            if let amount = bar.statusText {
                Text(amount)
                    .monospacedDigit()
                    .accessibilityLabel(bar.accessibilityText ?? amount)
            }
        } icon: {
            Image(nsImage: menuBarImage(bar.burnLevel))
        }
        .labelStyle(.titleAndIcon)
    }

    private var menuBarPresentation: MenuBarState.Presentation {
        MenuBarState.presentation(
            cursor: MenuBarState.Cursor(
                enabled: settings.cursorEnabled,
                burnLevel: store.burnLevel,
                showsWindowSpend: settings.statusBarShowsWindowSpend,
                showsCursorModels: settings.statusBarShowsCursorModels,
                showsOtherModels: settings.statusBarShowsOtherModels,
                showsGrokBot: settings.statusBarShowsGrokBot,
                windowDollars: store.snapshot.windowDollars,
                spendIsPlaceholder: !store.hasCompletedFetch && store.lastError == nil,
                cursorModelsPercent: store.includedPools?.cursorModelsPercent,
                otherModelsPercent: store.includedPools?.otherModelsPercent,
                grokBotPercent: store.grokBotUsage?.percentUsed
            ),
            claude: MenuBarState.Claude(
                installed: claudeCodeStore.isInstalled,
                enabled: settings.claudeCodeEnabled,
                burnLevel: claudeCodeStore.burnLevel,
                showsSpend: settings.showsClaudeSpend(
                    cursorAvailable: store.isCursorAvailable,
                    claudeInstalled: claudeCodeStore.isInstalled
                ),
                dollars: claudeCodeStore.snapshot.windowDollars,
                spendIsPlaceholder: !claudeCodeStore.hasCompletedFetch && claudeCodeStore.lastError == nil,
                showsFiveHour: settings.statusBarShowsClaudeFiveHour,
                fiveHourPercent: nil,
                showsWeekly: settings.statusBarShowsClaudeWeekly,
                weeklyPercent: nil,
                limitsEnabled: settings.claudeLimitsEnabled
            )
        )
    }

    private func menuBarImage(_ level: BurnLevel) -> NSImage {
        if AppIdentity.isDevBuild {
            return level.menuBarImageWithDevDot()
        }
        return level.menuBarImage()
    }
}
