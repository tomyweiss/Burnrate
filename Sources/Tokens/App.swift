import SwiftUI
import AppKit

@main
struct TokensApp: App {
    @State private var settings: SettingsStore
    @State private var store: UsageStore
    @State private var updates: UpdateManager

    init() {
        if CommandLine.arguments.contains("--status") {
            Self.runStatusAndExit()
        }

        let settings = SettingsStore()
        _settings = State(initialValue: settings)
        _store = State(initialValue: UsageStore(settings: settings))
        _updates = State(initialValue: UpdateManager(settings: settings))
    }

    private static func runStatusAndExit() -> Never {
        final class Box: @unchecked Sendable {
            var code: Int32 = 1
            var message = "ERROR Timed out fetching usage"
        }
        let box = Box()
        let group = DispatchGroup()
        group.enter()

        Task.detached {
            defer { group.leave() }
            do {
                let credentials = try TokenProvider.loadSessionCredentials()
                let api = CursorAPI()
                let now = Date()
                let midnight = Calendar.current.startOfDay(for: now)
                let startMs = Int64(midnight.timeIntervalSince1970 * 1000)
                let endMs = Int64(now.timeIntervalSince1970 * 1000)
                let events = try await api.fetchUsageEvents(
                    credentials: credentials,
                    startMs: startMs,
                    endMs: endMs
                )
                let snapshot = Aggregator.snapshot(
                    events: events,
                    now: now,
                    recentWindowMinutes: 10
                )
                box.message = String(
                    format: "OK %@ today (%d events)",
                    MoneyFormat.dollars(snapshot.todayDollars),
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
            RootPanel(store: store, settings: settings, updates: updates)
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
                Image(systemName: store.menuSymbolName)
            }
            .labelStyle(.titleAndIcon)
        }
        .menuBarExtraStyle(.window)
    }
}
