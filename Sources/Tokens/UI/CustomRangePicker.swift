import SwiftUI

/// Popover content for picking the custom date range: two graphical calendars
/// (start / end), both capped at today, with a live summary of the selection.
struct CustomRangePicker: View {
    @Bindable var settings: SettingsStore
    @Bindable var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("Custom range", systemImage: "calendar")
                    .font(.headline)
                Spacer()
                Button("Last 7 days") {
                    settings.resetCustomRangeToLastSevenDays()
                    MenuBarPanelKeeper.keepOpen()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            HStack(alignment: .top, spacing: 14) {
                calendarColumn(
                    title: "Start",
                    selection: $settings.customRangeStart,
                    range: Date.distantPast...Date()
                )
                Divider()
                calendarColumn(
                    title: "End",
                    selection: $settings.customRangeEnd,
                    range: settings.customRangeStart...Date()
                )
            }

            Divider()

            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.tertiary)
                Text(summary)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .font(.caption)
        }
        .padding(16)
        .onChange(of: settings.customRangeStart) { _, _ in
            Task { await store.refresh() }
            MenuBarPanelKeeper.keepOpen()
        }
        .onChange(of: settings.customRangeEnd) { _, _ in
            Task { await store.refresh() }
            MenuBarPanelKeeper.keepOpen()
        }
    }

    private func calendarColumn(
        title: String,
        selection: Binding<Date>,
        range: ClosedRange<Date>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            DatePicker("", selection: selection, in: range, displayedComponents: [.date])
                .datePickerStyle(.graphical)
                .labelsHidden()
                .fixedSize()
        }
    }

    private var summary: String {
        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: settings.customRangeStart)
        let endDay = calendar.startOfDay(for: settings.customRangeEnd)
        let days = (calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0) + 1
        let count = days == 1 ? "1 day" : "\(days) days"
        return "\(count) selected · both dates included"
    }
}
