import SwiftUI
import AppKit

enum UsageTab: String, CaseIterable, Identifiable {
    case models
    case sessions
    case skills
    case feed
    case bench

    var id: String { rawValue }

    var title: String {
        switch self {
        case .models: "Models"
        case .sessions: "Sessions"
        case .skills: "Skills"
        case .feed: "Feed"
        case .bench: "Bench"
        }
    }
}

/// Which cost figure drives sorting and the row preview on Models/Skills tabs.
enum CostMetric: String, CaseIterable, Identifiable {
    case total
    case average
    case median

    var id: String { rawValue }

    var title: String {
        switch self {
        case .total: "Total $"
        case .average: "Avg $"
        case .median: "Med $"
        }
    }
}

/// Two columns: the included allowance pools as rings (percent of a fixed
/// cap) on the left; on the right the cycle's spend as one stacked bar
/// (included vs on-demand share of the total) with `timeline` filling the
/// remaining height so both columns end level with the rings.
/// Blue means covered by the plan; orange means paying.
private struct IncludedPoolsGauges<Timeline: View>: View {
    /// Nil until Cursor reports the pools. The rings stay on screen either way.
    let pools: IncludedPools?
    /// Team spend when calibrated. Matches the cycle caption.
    let spendSummary: SpendSummary?
    /// usage-summary totals, used until team spend is available.
    let cycleSpend: CycleSpend?
    /// Weekly Grok Bot allowance. Hidden when this account has none.
    let grokBot: GrokBotUsage?
    /// Rendered under the spend legend; should be vertically flexible.
    @ViewBuilder let timeline: () -> Timeline

    /// The Other Models ring stays up while pools are still loading. Once a
    /// period reports no separate bucket, the ring comes down.
    private var showsOtherModelsRing: Bool {
        pools?.hasOtherModelsBucket ?? true
    }

    private var ringCount: Int {
        var count = 1
        if showsOtherModelsRing { count += 1 }
        if grokBot != nil { count += 1 }
        return count
    }

    /// Three rings stay in the allowance column. Fewer rings keep the larger size.
    private var ringSize: CGFloat { ringCount >= 3 ? 72 : 100 }
    private var ringSpacing: CGFloat { ringCount >= 3 ? 8 : 24 }
    private static var ringWidth: CGFloat { 9 }
    private static var includedTint: Color { .accentColor }
    private static var onDemandTint: Color { .orange }

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            allowanceCluster
            spendCluster
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Allowance

    private var allowanceCluster: some View {
        VStack(alignment: .leading, spacing: 10) {
            clusterHeader("Included allowance")

            HStack(alignment: .top, spacing: ringSpacing) {
                percentGauge("Cursor models", percent: pools?.cursorModelsPercent)
                    .help("Share of the Cursor models pool used this billing cycle")
                if showsOtherModelsRing {
                    percentGauge("Other models", percent: pools?.otherModelsPercent)
                        .help("Share of the Other models pool used this billing cycle")
                }
                if let grokBot {
                    percentGauge(
                        "Grok Bot",
                        percent: grokBot.percentUsed,
                        detail: grokBot.resetCaption().map { "resets \($0)" }
                    )
                    .help("Share of the Grok Bot weekly included pool used")
                }
            }
        }
    }

    private func percentGauge(_ title: String, percent: Double?, detail: String? = nil) -> some View {
        let shown = percent.map(IncludedPools.displayPercent)
        let fill = shown.map { min(CGFloat($0), 100) / 100 } ?? 0
        let tint = percentTint(percent)

        return VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.25), lineWidth: Self.ringWidth)
                Circle()
                    .trim(from: 0, to: fill)
                    .stroke(tint, style: StrokeStyle(lineWidth: Self.ringWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text(shown.map { "\($0)%" } ?? "—")
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    if shown != nil {
                        Text("used")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, ringSize < 80 ? 4 : 12)
            }
            .frame(width: ringSize, height: ringSize)

            VStack(spacing: 1) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(width: ringSize)
        }
        .frame(width: ringSize)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(gaugeAccessibility(title: title, shown: shown, detail: detail))
    }

    private func gaugeAccessibility(title: String, shown: Int?, detail: String?) -> String {
        let base = shown.map { "\(title), \($0) percent used" } ?? "\(title), not loaded"
        guard let detail else { return base }
        return "\(base), \(detail)"
    }

    /// Orange once the pool is exhausted, because usage past that point
    /// flows into on-demand spend (also orange).
    private func percentTint(_ percent: Double?) -> Color {
        guard let percent else { return Color.secondary.opacity(0.45) }
        return percent >= 100 ? Self.onDemandTint : Self.includedTint
    }

    // MARK: Spend

    private var split: SpendSplit? {
        if let spendSummary {
            return SpendSplit(includedCents: spendSummary.includedCents, onDemandCents: spendSummary.onDemandCents)
        }
        if let cycleSpend {
            return SpendSplit(includedCents: cycleSpend.includedCents, onDemandCents: cycleSpend.onDemandCents)
        }
        return nil
    }

    private var spendCluster: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    clusterHeader("Spend this cycle")
                    Spacer(minLength: 8)
                    Text(split.map { MoneyFormat.dollars($0.totalCents / 100) } ?? "—")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .lineLimit(1)
                }

                spendBar

                HStack(spacing: 14) {
                    legendItem("Included", cents: split?.includedCents, tint: Self.includedTint)
                    legendItem("On-demand", cents: split?.onDemandCents, tint: Self.onDemandTint)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spendAccessibility)
            .help("How this cycle's spend splits between the included allowance and on-demand")

            timeline()
                .frame(maxHeight: .infinity)
        }
    }

    private var spendBar: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let included = width * (split?.includedFraction ?? 0)
            let onDemand = width * (split?.onDemandFraction ?? 0)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.25))
                HStack(spacing: included > 0 && onDemand > 0 ? 2 : 0) {
                    if included > 0 {
                        Rectangle().fill(Self.includedTint).frame(width: included)
                    }
                    if onDemand > 0 {
                        Rectangle().fill(Self.onDemandTint).frame(width: onDemand)
                    }
                }
                .clipShape(Capsule())
            }
        }
        .frame(height: 10)
    }

    private func legendItem(_ title: String, cents: Double?, tint: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(cents == nil ? Color.secondary.opacity(0.45) : tint)
                .frame(width: 7, height: 7)
            Text(title)
                .foregroundStyle(.secondary)
            Text(cents.map { MoneyFormat.dollars($0 / 100) } ?? "—")
                .fontWeight(.medium)
                .monospacedDigit()
        }
        .font(.caption)
        .lineLimit(1)
    }

    private var spendAccessibility: String {
        guard let split else { return "Spend this cycle, not loaded" }
        let total = MoneyFormat.dollars(split.totalCents / 100)
        let included = MoneyFormat.dollars(split.includedCents / 100)
        let onDemand = MoneyFormat.dollars(split.onDemandCents / 100)
        return "Spend this cycle \(total): \(included) included, \(onDemand) on-demand"
    }

    // MARK: Shared

    private func clusterHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

struct UsagePanel: View {
    @Bindable var store: UsageStore
    @Bindable var settings: SettingsStore
    var glassNamespace: Namespace.ID
    var onOpenSettings: () -> Void
    var onOpenCommunity: () -> Void
    var onOpenChangeLog: (_ highlightVersion: String?, _ releaseNotes: String?) -> Void
    var onUsageTabChange: (UsageTab) -> Void = { _ in }

    @AppStorage("panelTab") private var panelTabRaw = UsageTab.models.rawValue
    @State private var expandedModels: Set<String> = []
    /// Navigation stack for session → subagent drilldown.
    @State private var sessionPath: [SessionUsage] = []
    @State private var selectedSkill: SkillUsage?
    @AppStorage("modelsCostMetric") private var modelsMetricRaw = CostMetric.total.rawValue
    @AppStorage("skillsCostMetric") private var skillsMetricRaw = CostMetric.total.rawValue
    @AppStorage("sessionsSort") private var sessionsSortRaw = SessionPromptSort.newest.rawValue
    @State private var sectionSearchText = ""
    @State private var isSectionSearchPresented = false
    @State private var showCustomRangePicker = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var panelTab: Binding<UsageTab> {
        Binding(
            get: { UsageTab(rawValue: panelTabRaw) ?? .models },
            set: { panelTabRaw = $0.rawValue }
        )
    }

    private var visibleTabs: [UsageTab] {
        settings.orderedVisibleUsageTabs()
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            Group {
                if !store.hasCompletedFetch, store.isLoading {
                    UsageSkeletonView()
                } else {
                    content
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            footer
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
        .onDisappear {
            sessionPath = []
            selectedSkill = nil
        }
        .onAppear {
            panelTabRaw = settings.normalizedPanelTabSelection(panelTabRaw)
        }
        .onChange(of: settings.visibleUsageTabRawValues) { _, _ in
            panelTabRaw = settings.normalizedPanelTabSelection(panelTabRaw)
        }
    }

    private func openChangeLog(version: String? = nil, releaseNotes: String? = nil) {
        onOpenChangeLog(version, releaseNotes)
        MenuBarPanelKeeper.keepOpen()
    }

    private var headerFigures: StatusBarFigures.Header {
        StatusBarFigures.header(store.statusBarInput)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .center, spacing: 8) {
                        Text(headerFigures.hero)
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                            .contentTransition(reduceMotion ? .identity : .numericText())
                            .animation(reduceMotion ? nil : .snappy, value: headerFigures.hero)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(headerFigures.accessibilityLabel)

                        Color.clear
                            .frame(width: 16, height: 16)
                            .overlay {
                                if store.isLoading {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                            }
                            .accessibilityHidden(!store.isLoading)

                        if !headerFigures.showsTimelineSpendBelow, store.snapshot.recentDollars > 0 {
                            burnPill
                        }

                        if !headerFigures.companions.isEmpty {
                            Text(headerFigures.companions.joined(separator: " · "))
                                .font(.title3.weight(.semibold))
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.65)
                                .accessibilityHidden(true)
                        }
                    }

                    if let caption = headerFigures.caption {
                        Text(caption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if headerFigures.showsTimelineSpendBelow {
                        HStack(alignment: .center, spacing: 8) {
                            Text(headerFigures.timelineSpend)
                                .font(.title3.weight(.semibold))
                                .monospacedDigit()
                                .lineLimit(1)
                                .accessibilityLabel("Window spend \(headerFigures.timelineSpend)")
                            if store.snapshot.recentDollars > 0 {
                                burnPill
                            }
                        }
                    }
                }
                .layoutPriority(1)

                Spacer(minLength: 4)

                HStack(alignment: .center, spacing: 8) {
                    if AppIdentity.isDevBuild {
                        Text("DEV")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.orange))
                            .accessibilityLabel("Development build")
                    }

                    communityButton

                    timelinePicker
                }
                .layoutPriority(0)
            }

            if store.snapshot.window.preset == .thisBilling {
                Text("Since \(store.snapshot.window.sparklineStartLabel())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if settings.usageTimelinePreset == .custom {
                customRangeButton
            }

            IncludedPoolsGauges(
                pools: store.includedPools,
                spendSummary: store.spendSummary,
                cycleSpend: store.cycleSpend,
                grokBot: store.grokBotUsage
            ) {
                SparklineView(
                    sparklineCostCents: store.snapshot.sparklineCostCents,
                    window: store.snapshot.window,
                    now: Date(),
                    chartHeight: nil
                )
            }

            if let statusCaption {
                Text(statusCaption)
                    .font(.caption)
                    .foregroundStyle(store.isStale ? Color.orange : Color.secondary)
            }
        }
    }

    private var communityButton: some View {
        Button {
            onOpenCommunity()
            MenuBarPanelKeeper.keepOpen()
        } label: {
            Label("Community", systemImage: "trophy.fill")
                .labelStyle(.titleAndIcon)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.orange)
        .background(Capsule().fill(Color.orange.opacity(0.18)))
        .help("Community ranking")
    }

    private var timelinePicker: some View {
        Picker("Timeline", selection: $settings.usageTimelinePreset) {
            ForEach(UsageTimelinePreset.allCases) { preset in
                Text(preset.displayName).tag(preset)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.secondary)
        .fixedSize()
        .onChange(of: settings.usageTimelinePreset) { _, _ in
            Task { await store.refresh(reuseEventsIfPossible: true) }
            MenuBarPanelKeeper.keepOpen()
        }
    }

    private var customRangeButton: some View {
        Button {
            showCustomRangePicker.toggle()
            MenuBarPanelKeeper.keepOpen()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                Text(customRangeLabel)
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive())
        .clipShape(Capsule())
        .help("Pick a custom date range")
        .popover(isPresented: $showCustomRangePicker, arrowEdge: .bottom) {
            CustomRangePicker(settings: settings, store: store)
        }
    }

    private var customRangeLabel: String {
        let calendar = Calendar.current
        let start = settings.customRangeStart
        let end = settings.customRangeEnd
        let startYear = calendar.component(.year, from: start)
        let endYear = calendar.component(.year, from: end)
        let currentYear = calendar.component(.year, from: Date())
        let showYear = startYear != currentYear || endYear != currentYear
        let style: Date.FormatStyle = showYear
            ? .dateTime.month(.abbreviated).day().year()
            : .dateTime.month(.abbreviated).day()
        if calendar.isDate(start, inSameDayAs: end) {
            return start.formatted(style)
        }
        return "\(start.formatted(style)) – \(end.formatted(style))"
    }

    private var burnPill: some View {
        let tint = store.burnLevel.swiftUIColor

        return Text(
            "▲ \(MoneyFormat.dollars(store.snapshot.recentDollars)) · \(settings.anomalyWindowMinutes)m"
        )
        .font(.subheadline.weight(.semibold).monospacedDigit())
        .lineLimit(1)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .glassEffect(.regular.tint(tint))
        .clipShape(Capsule())
        .help("Spend in the last \(settings.anomalyWindowMinutes) minutes (your spike window)")
    }

    /// Only shown when the data needs a caveat; fresh data gets no caption.
    private var statusCaption: String? {
        if store.snapshot.fetchedAt == .distantPast {
            return "Not refreshed yet"
        }
        if store.isShowingCachedData {
            return "Offline · data from \(RelativeTimeFormat.clockTime(store.snapshot.fetchedAt))"
        }
        if store.isStale {
            return "Data from \(RelativeTimeFormat.clockTime(store.snapshot.fetchedAt)) (stale)"
        }
        return nil
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            if let error = store.lastError {
                ErrorBanner(message: error) {
                    Task { await store.refresh() }
                    MenuBarPanelKeeper.keepOpen()
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }

            if store.hasCompletedFetch,
               store.snapshot.windowCostCents == 0,
               store.snapshot.models.isEmpty,
               store.snapshot.rootSessions.isEmpty,
               store.lastError == nil {
                EmptySpendView(message: store.snapshot.window.emptyStateMessage)
            } else if let skill = selectedSkill {
                SkillDetailView(
                    // Prefer the freshest snapshot copy; fall back to the tapped one.
                    skill: store.snapshot.skills
                        .first { $0.skill == skill.skill } ?? skill,
                    prompts: store.snapshot.prompts
                        .filter { $0.skills.contains(skill.skill) },
                    onBack: {
                        selectedSkill = nil
                        MenuBarPanelKeeper.keepOpen()
                    }
                )
            } else if let selected = sessionPath.last {
                let session = store.snapshot.session(id: selected.conversationId) ?? selected
                SessionDetailView(
                    session: session,
                    prompts: store.snapshot.prompts(for: session),
                    subagents: store.snapshot.childSessions(of: session),
                    windowCostCents: store.snapshot.windowCostCents,
                    onBack: {
                        if !sessionPath.isEmpty {
                            sessionPath.removeLast()
                        }
                        MenuBarPanelKeeper.keepOpen()
                    },
                    onOpenSubagent: { child in
                        sessionPath.append(child)
                        MenuBarPanelKeeper.keepOpen()
                    }
                )
            } else {
                controlRow

                if panelTab.wrappedValue == .bench {
                    BenchView(snapshot: store.snapshot)
                } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        switch panelTab.wrappedValue {
                        case .models:
                            if filteredModels.isEmpty {
                                tabEmptyText(
                                    ListSearch.isActive(sectionSearchText)
                                        ? ListSearch.noMatchesMessage(sectionSearchText)
                                        : "No models in this window"
                                )
                            } else {
                                ForEach(filteredModels) { model in
                                    ModelRowView(
                                        model: model,
                                        windowCostCents: store.snapshot.windowCostCents,
                                        isExpanded: expandedModels.contains(model.id),
                                        reduceMotion: reduceMotion,
                                        showLocationSubtitle: settings.showLocationSubtitle,
                                        hideArchivedSessions: settings.hideArchivedSessions,
                                        metric: modelsMetric,
                                        metricMaxDollars: maxModelMetricDollars,
                                        sessionSearchQuery: sectionSearchText,
                                        onToggle: { toggleExpanded(model.id) },
                                        onOpenSession: openSession
                                    )
                                    Divider().opacity(0.35)
                                }
                            }
                        case .sessions:
                            if filteredSessions.isEmpty {
                                tabEmptyText(
                                    ListSearch.isActive(sectionSearchText)
                                        ? ListSearch.noMatchesMessage(sectionSearchText)
                                        : "No sessions in this window"
                                )
                            } else {
                                ForEach(filteredSessions) { session in
                                    SessionRowView(
                                        session: session,
                                        windowCostCents: store.snapshot.windowCostCents,
                                        showModelChips: true,
                                        showShareBar: true,
                                        showLocationSubtitle: settings.showLocationSubtitle,
                                        onOpen: { openSession(session) }
                                    )
                                    Divider().opacity(0.35)
                                }
                            }
                        case .skills:
                            if store.snapshot.skills.isEmpty {
                                tabEmptyText("No skill invocations in this window")
                            } else if filteredSkills.isEmpty {
                                tabEmptyText(ListSearch.noMatchesMessage(sectionSearchText))
                            } else {
                                ForEach(filteredSkills) { skill in
                                    SkillRowView(
                                        skill: skill,
                                        windowCostCents: store.snapshot.windowCostCents,
                                        metric: skillsMetric,
                                        metricMaxDollars: maxSkillMetricDollars,
                                        onOpen: {
                                            selectedSkill = skill
                                            MenuBarPanelKeeper.keepOpen()
                                        }
                                    )
                                    Divider().opacity(0.35)
                                }
                            }
                        case .feed:
                            if store.snapshot.prompts.isEmpty {
                                tabEmptyText("No prompts found for this window")
                            } else if filteredPrompts.isEmpty {
                                tabEmptyText(ListSearch.noMatchesMessage(sectionSearchText))
                            } else {
                                ForEach(filteredPrompts) { prompt in
                                    PromptRowView(prompt: prompt)
                                    Divider().opacity(0.35)
                                }
                            }
                        case .bench:
                            EmptyView()
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
                }
            }
        }
    }

    // MARK: - Tab + filter controls

    private var controlRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            PillPicker(
                selection: panelTab,
                options: visibleTabs.map { tab in
                    PillPicker.Option(value: tab, title: tab.title)
                },
                size: .controlBar,
                fillsWidth: true
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .onChange(of: panelTabRaw) { oldTab, newTab in
                MenuBarPanelKeeper.keepOpen()
                guard oldTab != newTab else { return }
                sectionSearchText = ""
                isSectionSearchPresented = false
                if let tab = UsageTab(rawValue: newTab) {
                    onUsageTabChange(tab)
                }
            }

            if showsSectionSearch {
                SectionSearchControl(
                    text: $sectionSearchText,
                    isPresented: $isSectionSearchPresented,
                    placeholder: searchPlaceholder,
                    reduceMotion: reduceMotion
                ) {
                    if hasTrailingControl {
                        trailingControlPicker
                            .fixedSize()
                    }
                }
            } else if hasTrailingControl {
                HStack {
                    Spacer()
                    trailingControlPicker
                        .fixedSize()
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .zIndex(1)
        .animation(reduceMotion ? nil : .snappy, value: panelTabRaw)
    }

    private var showsSectionSearch: Bool {
        panelTab.wrappedValue != .bench
    }

    private var hasTrailingControl: Bool {
        switch panelTab.wrappedValue {
        case .models, .sessions:
            return true
        case .skills:
            return !store.snapshot.skills.isEmpty
        case .feed:
            return false
        case .bench:
            return false
        }
    }

    private var searchPlaceholder: String {
        switch panelTab.wrappedValue {
        case .models: return "Search models or sessions"
        case .sessions: return "Search sessions"
        case .skills: return "Search skills"
        case .feed: return "Search prompts"
        case .bench: return ""
        }
    }

    private var filteredModels: [ModelUsage] {
        guard ListSearch.isActive(sectionSearchText) else { return displayedModels }
        return displayedModels.filter { ListSearch.model($0, query: sectionSearchText) }
    }

    private var filteredSessions: [SessionUsage] {
        guard ListSearch.isActive(sectionSearchText) else { return visibleSessions }
        return visibleSessions.filter { ListSearch.session($0, query: sectionSearchText) }
    }

    private var filteredSkills: [SkillUsage] {
        guard ListSearch.isActive(sectionSearchText) else { return displayedSkills }
        return displayedSkills.filter { ListSearch.skill($0, query: sectionSearchText) }
    }

    private var filteredPrompts: [PromptUsage] {
        guard ListSearch.isActive(sectionSearchText) else { return store.snapshot.prompts }
        return store.snapshot.prompts.filter { ListSearch.prompt($0, query: sectionSearchText) }
    }

    @ViewBuilder
    private var trailingControlPicker: some View {
        switch panelTab.wrappedValue {
        case .models:
            costMetricPicker(selection: $modelsMetricRaw)
        case .skills where !store.snapshot.skills.isEmpty:
            costMetricPicker(selection: $skillsMetricRaw)
        case .skills:
            EmptyView()
        case .sessions:
            sessionsSortPicker
        case .bench:
            EmptyView()
        case .feed:
            EmptyView()
        }
    }

    private func costMetricPicker(selection: Binding<String>) -> some View {
        PillPicker(
            selection: Binding(
                get: { CostMetric(rawValue: selection.wrappedValue) ?? .total },
                set: { selection.wrappedValue = $0.rawValue }
            ),
            options: [
                PillPicker.Option(
                    value: .total,
                    title: "Total",
                    icon: "sum",
                    help: "Total"
                ),
                PillPicker.Option(
                    value: .average,
                    title: "Avg",
                    icon: "divide",
                    help: "Average"
                ),
                PillPicker.Option(
                    value: .median,
                    title: "Med",
                    icon: "chart.bar.xaxis",
                    help: "Median"
                ),
            ],
            size: .compact,
            style: .flat
        )
        .fixedSize()
        .onChange(of: selection.wrappedValue) { _, _ in
            MenuBarPanelKeeper.keepOpen()
        }
    }

    private var sessionsSortPicker: some View {
        PillPicker(
            selection: Binding(
                get: { SessionPromptSort(rawValue: sessionsSortRaw) ?? .newest },
                set: { sessionsSortRaw = $0.rawValue }
            ),
            options: SessionPromptSort.pillPickerOptions,
            size: .compact,
            style: .flat
        )
        .fixedSize()
        .onChange(of: sessionsSortRaw) { _, _ in
            MenuBarPanelKeeper.keepOpen()
        }
    }

    // MARK: - Cost metric (Total vs Avg)

    private var modelsMetric: CostMetric {
        CostMetric(rawValue: modelsMetricRaw) ?? .total
    }

    private var skillsMetric: CostMetric {
        CostMetric(rawValue: skillsMetricRaw) ?? .total
    }

    private var displayedModels: [ModelUsage] {
        let models = store.snapshot.models
        switch modelsMetric {
        case .total:
            return models
        case .average:
            return models.sorted { $0.averageCostDollars > $1.averageCostDollars }
        case .median:
            return models.sorted { $0.medianCostDollars > $1.medianCostDollars }
        }
    }

    private var displayedSkills: [SkillUsage] {
        let skills = store.snapshot.skills
        let value: (SkillUsage) -> Double
        switch skillsMetric {
        case .total:
            return skills
        case .average:
            value = \.averageCostDollars
        case .median:
            value = \.medianCostDollars
        }
        return skills.sorted {
            value($0) == value($1)
                ? $0.lastUsedMs > $1.lastUsedMs
                : value($0) > value($1)
        }
    }

    /// Highest value of the selected per-unit metric; scales the share bars.
    private var maxModelMetricDollars: Double {
        let models = store.snapshot.models
        switch modelsMetric {
        case .total: return 0
        case .average: return models.map(\.averageCostDollars).max() ?? 0
        case .median: return models.map(\.medianCostDollars).max() ?? 0
        }
    }

    private var maxSkillMetricDollars: Double {
        let skills = store.snapshot.skills
        switch skillsMetric {
        case .total: return 0
        case .average: return skills.map(\.averageCostDollars).max() ?? 0
        case .median: return skills.map(\.medianCostDollars).max() ?? 0
        }
    }

    private func tabEmptyText(_ message: String) -> some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 24)
    }

    private var visibleSessions: [SessionUsage] {
        // Roots only — subagents live under their parent in session detail.
        var sessions = store.snapshot.rootSessions
        if settings.hideArchivedSessions {
            sessions = sessions.filter { !$0.isArchived }
        }
        switch SessionPromptSort(rawValue: sessionsSortRaw) ?? .newest {
        case .newest:
            return sessions.sorted {
                $0.lastTimestampMs == $1.lastTimestampMs
                    ? $0.costCents > $1.costCents
                    : $0.lastTimestampMs > $1.lastTimestampMs
            }
        case .cost:
            return sessions.sorted { $0.costCents > $1.costCents }
        }
    }

    private func openSession(_ session: SessionUsage) {
        let resolved = store.snapshot.session(id: session.conversationId) ?? session
        panelTabRaw = UsageTab.sessions.rawValue
        sectionSearchText = ""
        isSectionSearchPresented = false
        sessionPath = [resolved]
        onUsageTabChange(.sessions)
        MenuBarPanelKeeper.keepOpen()
    }

    private func toggleExpanded(_ modelID: String) {
        if reduceMotion {
            if expandedModels.contains(modelID) {
                expandedModels.remove(modelID)
            } else {
                expandedModels.insert(modelID)
            }
        } else {
            withAnimation(.snappy) {
                if expandedModels.contains(modelID) {
                    expandedModels.remove(modelID)
                } else {
                    expandedModels.insert(modelID)
                }
            }
        }
        MenuBarPanelKeeper.keepOpen()
    }

    private var footer: some View {
        GlassEffectContainer {
            HStack {
                Button {
                    onOpenSettings()
                    MenuBarPanelKeeper.keepOpen()
                } label: {
                    footerIcon("gearshape")
                }
                .buttonStyle(.borderless)
                .help("Settings")
                .glassEffect(.regular.interactive())
                .glassEffectID("settings-gear", in: glassNamespace)

                Spacer()

                signature

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        Task { await store.refresh() }
                        MenuBarPanelKeeper.keepOpen()
                    } label: {
                        footerIcon("arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .disabled(store.isLoading)
                    .keyboardShortcut("r")
                    .help("Refresh")
                    .glassEffect(.regular.interactive())

                    Button {
                        NSApplication.shared.terminate(nil)
                    } label: {
                        footerIcon("power")
                    }
                    .buttonStyle(.borderless)
                    .keyboardShortcut("q")
                    .help("Quit")
                    .glassEffect(.regular.interactive())
                }
            }
        }
        .foregroundStyle(.primary.opacity(0.9))
    }

    private var signature: some View {
        HStack(spacing: 3) {
            Text("Powered by")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Link(destination: URL(string: "https://getdrift.ai")!) {
                Text("Drift Security")
                    .font(.caption2.weight(.medium))
                    .underline()
                    .foregroundStyle(.secondary)
            }
            .help("getdrift.ai")
        }
    }

    private func footerIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.body.weight(.medium))
            .imageScale(.medium)
            .frame(width: 30, height: 30, alignment: .center)
            .contentShape(Rectangle())
    }
}
