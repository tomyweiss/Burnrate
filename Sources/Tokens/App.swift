import SwiftUI
import AppKit

@main
struct TokensApp: App {
    @State private var settings: SettingsStore
    @State private var store: UsageStore
    @State private var updates: UpdateManager
    @State private var community: CommunityStore
    @State private var interactionTracker: InteractionTracker

    init() {
        if CommandLine.arguments.contains("--status") {
            Self.runStatusAndExit()
        }

        let settings = SettingsStore()
        FailureReporter.isEnabled = { settings.sendDiagnostics }
        let interactionTracker = InteractionTracker()
        let store = UsageStore(settings: settings)
        let community = CommunityStore(settings: settings, interactionTracker: interactionTracker)
        store.setCommunityStore(community)
        community.setUsageStore(store)
        Task { await community.migrateNicknameToCursorDefaultIfNeeded() }
        _settings = State(initialValue: settings)
        _store = State(initialValue: store)
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
                .onAppear {
                    store.start()
                    updates.autoCheckIfNeeded()
                }
        } label: {
            Label {
                if let amount = store.menuAmountText {
                    Text(amount)
                        .monospacedDigit()
                }
            } icon: {
                Image(nsImage: store.menuBarIcon)
            }
            .labelStyle(.titleAndIcon)
        }
        .menuBarExtraStyle(.window)
    }
}
