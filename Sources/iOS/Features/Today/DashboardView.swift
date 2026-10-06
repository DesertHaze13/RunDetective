import SwiftUI
import Charts
import MapKit

struct DashboardView: View {
    @EnvironmentObject var health: HealthStore
    @State private var showClue = false
    @State private var runnerHop = false
    @State private var chaseCount = 0
    @State private var revealComparison = false
    @State private var selectedRecentRunDate: Date?
    @State private var recentChartScrubbing = false
    @State private var clockTick = Date()
    @State private var selectedWeekOffset = 0
    @State private var baselineWeekOffset = 1
    @State private var draftWeekOffset = 0
    @State private var draftBaselineOffset = 1
    @State private var showingWeekPicker = false
    @State private var showingRunPicker = false
    @State private var selectedRunID: UUID?
    @State private var selectedPreviousRunID: UUID?
    @State private var draftRunID: UUID?
    @State private var draftPreviousRunID: UUID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var latestRun: RunWorkout? { health.workouts.filter { $0.kind == .running }.max { $0.start < $1.start } }
    private var allRuns: [RunWorkout] { health.workouts.filter { $0.kind == .running }.sorted { $0.start > $1.start } }
    private var selectedRun: RunWorkout? { allRuns.first { $0.id == selectedRunID } ?? allRuns.first }
    private var priorRuns: [RunWorkout] { guard let selectedRun else { return [] }; return allRuns.filter { $0.start < selectedRun.start } }
    private var selectedPreviousRun: RunWorkout? { priorRuns.first { $0.id == selectedPreviousRunID } ?? priorRuns.first }
    private var weeklyPair: RunningWeekComparison? { RunAnalytics.compareWeeks(selectedWeekOffset, baselineWeekOffset, workouts: health.workouts, now: clockTick) }
    private var rolling: (recent: ActivitySummary, previous: ActivitySummary) { RunAnalytics.rollingSevenDays(health.workouts, now: clockTick) }
    private var latestDay: ActivitySummary? { RunMath.days(health.workouts).first }
    private var week: WeekSummary? {
        let start = Calendar.current.dateInterval(of: .weekOfYear, for: clockTick)?.start ?? clockTick
        return WeekSummary(start: start, workouts: health.workouts.filter { $0.start >= start && $0.start <= clockTick })
    }
    private var recentRuns: [RunWorkout] {
        Array(health.workouts.filter { $0.kind == .running }.sorted { $0.start > $1.start }.prefix(5))
    }
    var body: some View {
        GeometryReader { geometry in
            let expanded = geometry.size.width >= 760
            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        caseHeader
                        sectionJumps(scrollProxy)
                        if expanded { bentoCards } else { compactCards }
                    }
                    .frame(maxWidth: expanded ? 1500 : 760)
                    .padding(.horizontal, expanded ? 32 : 22)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity)
                }
                .refreshable { await health.refresh() }
                .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: expanded)
            }
        }
        .background(AmbientBackdrop()).navigationTitle("Overview").toolbar(.hidden, for: .navigationBar)
            .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { clockTick = $0 }
            .sheet(isPresented: $showingWeekPicker) { weekPickerSheet }
            .sheet(isPresented: $showingRunPicker) { runPickerSheet }
    }
    private func sectionJumps(_ proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 10) {
            jumpButton("Runs", symbol: "figure.run", target: "runSection", proxy: proxy)
            jumpButton("Weeks", symbol: "calendar", target: "weekSection", proxy: proxy)
            if recentRuns.count > 1 {
                jumpButton("Chart", symbol: "chart.xyaxis.line", target: "trendSection", proxy: proxy)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .overlay(alignment: .bottomLeading) {
            Text("Run comparisons, weekly evidence, and trends continue below.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .offset(y: 19)
                .accessibilityHidden(true)
        }
        .padding(.bottom, 19)
    }
    private func jumpButton(_ title: String, symbol: String, target: String, proxy: ScrollViewProxy) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.4)) {
                proxy.scrollTo(target, anchor: .top)
            }
        } label: {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(.thinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Jump to \(title.lowercased()) cards")
    }
    private var caseHeader: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("RUN DETECTIVE").font(.caption.weight(.black)).tracking(2.6).foregroundStyle(.secondary)
                    Text("The case file").font(.system(size: 38, weight: .bold, design: .rounded)).tracking(-1.2)
                }
                Spacer()
                Button { withAnimation(.spring(response: 0.32, dampingFraction: 0.68)) { showClue.toggle() } } label: { Image(systemName: "sparkle.magnifyingglass").font(.title2).symbolEffect(.bounce, value: showClue).frame(width: 46, height: 46).background(.mint.opacity(0.15), in: Circle()) }.buttonStyle(AnimatedCardButtonStyle()).accessibilityLabel("Reveal a clue")
            }
            HStack(spacing: 7) {
                Image(systemName: health.loading ? "arrow.triangle.2.circlepath" : health.error != nil ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                Text(health.loading ? "SYNCING APPLE HEALTH" : health.error != nil ? "HEALTH SYNC FAILED" : health.lastSync.map { "HEALTH SYNCED · \($0.formatted(date: .omitted, time: .shortened))" } ?? "WAITING FOR HEALTH SYNC")
            }
            .font(.caption2.weight(.bold))
            .foregroundStyle(health.loading || health.error != nil ? Color.orange : Color.teal)
            .accessibilityLabel(health.loading ? "Syncing Apple Health" : health.error != nil ? "Health sync failed" : "Last successful Health sync: \(health.lastSync?.formatted(date: .abbreviated, time: .shortened) ?? "unavailable")")
            if let error = health.error, !health.loading { Text(error).font(.footnote).foregroundStyle(.orange) }
            if showClue { Label("One run is a clue. A pattern needs repeats.", systemImage: "quote.bubble").font(.subheadline).foregroundStyle(.secondary).transition(.opacity) }
        }
    }
    private var weekSelector: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Label("Week comparison", systemImage: "calendar.badge.clock")
                    .font(.headline)
                Spacer()
                Button("Change weeks") {
                    draftWeekOffset = selectedWeekOffset
                    draftBaselineOffset = baselineWeekOffset
                    showingWeekPicker = true
                }
                .font(.subheadline.weight(.semibold))
            }
            weekRow(offset: selectedWeekOffset)
            Label("compared with", systemImage: "arrow.down")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .padding(.leading, 3)
            weekRow(offset: baselineWeekOffset)
            if selectedWeekOffset == 0 {
                Text("Fair comparison: last week only counts through the same day and time as this week.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .contain)
    }
    private func weekRow(offset: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(weekName(offset)).font(.title3.weight(.semibold))
            Text(displayedWeekRange(offset)).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
    private func weekDateRange(_ offset: Int) -> String {
        guard let week = RunAnalytics.week(offset, workouts: health.workouts, now: clockTick),
              let end = Calendar.current.date(byAdding: .day, value: 6, to: week.start) else { return "Unavailable" }
        return "\(week.start.formatted(.dateTime.day().month(.abbreviated).year()))–\(end.formatted(.dateTime.day().month(.abbreviated).year()))"
    }
    private func displayedWeekRange(_ offset: Int) -> String {
        guard selectedWeekOffset == 0,
              let current = RunAnalytics.week(0, workouts: health.workouts, now: clockTick),
              let selected = RunAnalytics.week(offset, workouts: health.workouts, now: clockTick) else { return weekDateRange(offset) }
        let end: Date
        if offset == 0 { end = clockTick }
        else if offset == baselineWeekOffset { end = selected.start.addingTimeInterval(clockTick.timeIntervalSince(current.start)) }
        else { return weekDateRange(offset) }
        return "\(selected.start.formatted(.dateTime.day().month(.abbreviated).year()))–\(end.formatted(.dateTime.day().month(.abbreviated).year()))"
    }
    private func weekName(_ offset: Int) -> String {
        offset == 0 ? "This week" : offset == 1 ? "Last week" : "\(offset) weeks ago"
    }
    private var weekPickerSheet: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Week to review", selection: $draftWeekOffset) {
                        ForEach(0..<52, id: \.self) { offset in
                            Text("\(weekName(offset)) · \(weekDateRange(offset))").tag(offset)
                        }
                    }
                    Picker("Compare with", selection: $draftBaselineOffset) {
                        ForEach((draftWeekOffset + 1)..<53, id: \.self) { offset in
                            Text("\(weekName(offset)) · \(weekDateRange(offset))").tag(offset)
                        }
                    }
                } header: {
                    Text("Pick two weeks")
                } footer: {
                    Text("Choose a newer week first, then an earlier week. All weekly cards will use this choice.")
                }
                if draftWeekOffset != 0 || draftBaselineOffset != 1 {
                    Section {
                        Button("Use this week vs last week") {
                            draftWeekOffset = 0
                            draftBaselineOffset = 1
                        }
                    }
                }
                if draftWeekOffset == 0 {
                    Section { Text("This week is still in progress. The earlier week is counted only through the same day and time.") }
                }
            }
            .navigationTitle("Compare weeks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showingWeekPicker = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        selectedWeekOffset = draftWeekOffset
                        baselineWeekOffset = draftBaselineOffset
                        showingWeekPicker = false
                    }
                    .fontWeight(.semibold)
                    .disabled(draftWeekOffset >= draftBaselineOffset)
                }
            }
            .onChange(of: draftWeekOffset) {
                if draftBaselineOffset <= draftWeekOffset { draftBaselineOffset = draftWeekOffset + 1 }
            }
        }
        .presentationDetents([.medium, .large])
    }
    private func periodCaption(_ pair: RunningWeekComparison) -> String {
        let calendar = Calendar.current
        let recentEnd = selectedWeekOffset == 0 ? clockTick : (calendar.date(byAdding: .weekOfYear, value: 1, to: pair.recent.start)?.addingTimeInterval(-1) ?? clockTick)
        let previousEnd = selectedWeekOffset == 0 ? pair.previous.start.addingTimeInterval(clockTick.timeIntervalSince(pair.recent.start)) : (calendar.date(byAdding: .weekOfYear, value: 1, to: pair.previous.start)?.addingTimeInterval(-1) ?? clockTick)
        func range(_ start: Date, _ end: Date) -> String {
            "\(start.formatted(.dateTime.day().month(.abbreviated).year()))–\(end.formatted(.dateTime.day().month(.abbreviated).year()))"
        }
        return "\(range(pair.recent.start, recentEnd)) vs \(range(pair.previous.start, previousEnd))\(selectedWeekOffset == 0 ? " · matched elapsed time" : "")"
    }
    @ViewBuilder private var latestRunCards: some View {
        if let run = latestRun {
            latestCard(run).id("runSection")
            runSelector
            if let selectedRun, let selectedPreviousRun {
                comparison(selectedRun, selectedPreviousRun)
                runMetricCards(selectedRun, selectedPreviousRun)
            }
            else { noMatch(run) }
        } else { firstRunState.id("runSection") }
    }
    private var runSelector: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Run vs run", systemImage: "figure.run.circle").font(.headline)
                Spacer()
                Button("Change runs") {
                    draftRunID = selectedRun?.id
                    draftPreviousRunID = selectedPreviousRun?.id
                    showingRunPicker = true
                }.font(.subheadline.weight(.semibold))
            }
            if let selectedRun {
                Text("Newer: \(runLabel(selectedRun))").font(.subheadline)
            }
            if let selectedPreviousRun {
                Text("Earlier: \(runLabel(selectedPreviousRun))").font(.subheadline).foregroundStyle(.secondary)
            } else {
                Text("A second recorded run is needed for a comparison.").font(.subheadline).foregroundStyle(.secondary)
            }
            Text("Defaults to your two most recent Health runs and changes after each sync.").font(.caption).foregroundStyle(.secondary)
        }
        .padding(16).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
    private func runLabel(_ run: RunWorkout) -> String {
        "\(run.start.formatted(date: .complete, time: .shortened)) · \(Format.distance(run.distance))"
    }
    private func runPairDates(_ newer: RunWorkout, _ earlier: RunWorkout) -> String {
        "\(newer.start.formatted(date: .complete, time: .shortened)) vs \(earlier.start.formatted(date: .complete, time: .shortened))"
    }
    @ViewBuilder private func runMetricCards(_ newer: RunWorkout, _ earlier: RunWorkout, titlePrefix: String = "RUN VS RUN") -> some View {
        analyticsCard("\(titlePrefix) · PACE", symbol: "speedometer", tint: .teal,
                      trend: newer.pace.flatMap { pace in earlier.pace.map { metricTrend(pace, $0, epsilon: 5) } } ?? .unavailable,
                      trendTint: newer.distance.flatMap { distance in earlier.distance.map { abs(distance - $0) / max($0, 1) <= 0.25 } } == true ? (newer.pace.flatMap { pace in earlier.pace.map { pace < $0 - 5 ? .teal : pace > $0 + 5 ? .orange : .secondary } }) : nil) {
            Text(runPairDates(newer, earlier)).font(.footnote).foregroundStyle(.secondary)
            HStack { metric("NEWER", Format.pace(newer.pace)); Spacer(); metric("EARLIER", Format.pace(earlier.pace)) }
            HStack { metric("NEWER SPEED", Format.number(newer.speed.map { $0 * 3.6 }, unit: "km/h", digits: 1)); Spacer(); metric("EARLIER SPEED", Format.number(earlier.speed.map { $0 * 3.6 }, unit: "km/h", digits: 1)) }
            if let pace = newer.pace, let old = earlier.pace {
                Text(abs(pace - old) < 5 ? "Pace is roughly unchanged." : "\(Int(abs(pace - old).rounded())) sec/km \(pace < old ? "faster" : "slower") in the newer run.")
                    .font(.subheadline.weight(.semibold))
            } else { Text("Pace unavailable for one or both runs.").font(.subheadline) }
            Text("Lower pace means faster. Workout time includes pauses. Different routes and distances can change pace without reflecting fitness.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        analyticsCard("\(titlePrefix) · HEART RATE", symbol: "heart", tint: .pink,
                      trend: newer.averageHR.flatMap { hr in earlier.averageHR.map { metricTrend(hr, $0, epsilon: 4) } } ?? .unavailable) {
            Text(runPairDates(newer, earlier)).font(.footnote).foregroundStyle(.secondary)
            HStack { metric("NEWER AVG", Format.number(newer.averageHR, unit: "bpm")); Spacer(); metric("EARLIER AVG", Format.number(earlier.averageHR, unit: "bpm")) }
            if let hr = newer.averageHR, let old = earlier.averageHR {
                Text(abs(hr - old) < 4 ? "Sample-weighted averages were within 4 bpm." : "Sample-weighted average was \(Int(abs(hr - old).rounded())) bpm \(hr > old ? "higher" : "lower") in the newer run.")
                    .font(.subheadline.weight(.semibold))
            } else { Text("Heart-rate comparison unavailable.").font(.subheadline) }
            Text("The average is calculated from measured Health heart-rate samples. The arrow describes HR, not whether the run was better. Compare effort only when pace, distance, and sample coverage are similar.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        analyticsCard("\(titlePrefix) · DISTANCE", symbol: "point.topleft.down.to.point.bottomright.curvepath", tint: .indigo,
                      trend: newer.distance.flatMap { distance in earlier.distance.map { metricTrend(distance, $0, epsilon: 10) } } ?? .unavailable) {
            Text(runPairDates(newer, earlier)).font(.footnote).foregroundStyle(.secondary)
            HStack { metric("NEWER", Format.distance(newer.distance)); Spacer(); metric("EARLIER", Format.distance(earlier.distance)) }
            if let current = newer.distance, let before = earlier.distance {
                Text("\(Format.distance(abs(current - before))) \(abs(current - before) < 10 ? "apart" : current > before ? "farther" : "shorter") in the newer run.")
                    .font(.subheadline.weight(.semibold))
            }
            Text("A longer run is more volume, not automatically better performance.").font(.footnote).foregroundStyle(.secondary)
        }
        analyticsCard("\(titlePrefix) · ACTIVE ENERGY", symbol: "flame", tint: .orange,
                      trend: newer.energy.flatMap { energy in earlier.energy.map { metricTrend(energy, $0, epsilon: 1) } } ?? .unavailable) {
            Text(runPairDates(newer, earlier)).font(.footnote).foregroundStyle(.secondary)
            HStack { metric("NEWER", Format.number(newer.energy, unit: "kcal")); Spacer(); metric("EARLIER", Format.number(earlier.energy, unit: "kcal")) }
            Text("Health's recorded active energy reflects workload. Missing values stay unavailable; a higher number is not a fitness verdict.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
    private var runPickerSheet: some View {
        NavigationStack {
            Form {
                Section("Choose recorded runs") {
                    Picker("Newer run", selection: $draftRunID) {
                        ForEach(allRuns) { run in Text(runLabel(run)).tag(Optional(run.id)) }
                    }
                    Picker("Earlier run", selection: $draftPreviousRunID) {
                        ForEach(allRuns.filter { run in allRuns.first { $0.id == draftRunID }.map { run.start < $0.start } ?? false }) { run in
                            Text(runLabel(run)).tag(Optional(run.id))
                        }
                    }
                }
                Section { Button("Use latest two runs") { selectedRunID = nil; selectedPreviousRunID = nil; showingRunPicker = false } }
            }
            .navigationTitle("Compare runs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showingRunPicker = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { selectedRunID = draftRunID; selectedPreviousRunID = draftPreviousRunID; showingRunPicker = false }
                        .disabled(draftRunID == nil || draftPreviousRunID == nil)
                }
            }
            .onChange(of: draftRunID) {
                let newer = allRuns.first { $0.id == draftRunID }
                if !allRuns.contains(where: { candidate in candidate.id == draftPreviousRunID && newer.map { candidate.start < $0.start } == true }) {
                    draftPreviousRunID = newer.flatMap { selected in allRuns.first { $0.start < selected.start }?.id }
                }
            }
        }
    }
    private var signalLegend: some View {
        HStack(spacing: 9) {
            changeBadge("IMPROVED", symbol: "arrow.up.right", tone: .improved)
            changeBadge("CAUTION", symbol: "exclamationmark", tone: .caution)
            changeBadge("CONTEXT", symbol: "equal", tone: .context)
        }
        .accessibilityElement(children: .combine)
    }
    private var compactCards: some View {
        VStack(alignment: .leading, spacing: 25) {
            latestRunCards
            weekSelector.id("weekSection")
            rollingCard
            weekCard
            leadAnalysisCard
            signalLegend
            if let weeklyPair {
                findingsCard(weeklyPair)
                weekComparisonCard(weeklyPair)
                weeklySessionCards(weeklyPair)
                walkingCard(weeklyPair)
            } else { comparisonNeedsDataCard }
            if let latestDay { dailyCard(latestDay) }
            if recentRuns.count > 1 { recentChart(recentRuns).id("trendSection") }
        }
    }
    private var bentoCards: some View {
        VStack(alignment: .leading, spacing: 20) {
            latestRunCards
            weekSelector.id("weekSection")
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 20) {
                    rollingCard
                    if let weeklyPair {
                        weeklySessionCards(weeklyPair)
                        walkingCard(weeklyPair)
                    }
                    if recentRuns.count > 1 { recentChart(recentRuns).id("trendSection") }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                VStack(alignment: .leading, spacing: 20) {
                    leadAnalysisCard
                    signalLegend
                    weekCard
                    if let weeklyPair {
                        findingsCard(weeklyPair)
                        weekComparisonCard(weeklyPair)
                    } else { comparisonNeedsDataCard }
                    if let latestDay { dailyCard(latestDay) }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }
    private func latestCard(_ run: RunWorkout) -> some View {
        VStack(alignment: .leading, spacing: 18) {
                HStack { Label("LATEST RUN", systemImage: "figure.run").font(.caption.weight(.bold)).tracking(1.2); Spacer() }
                Text(Format.distance(run.distance)).font(.system(size: 52, weight: .bold, design: .rounded)).minimumScaleFactor(0.7).lineLimit(1)
                Text(run.start.formatted(date: .complete, time: .omitted)).font(.subheadline).foregroundStyle(.white.opacity(0.8))
                HStack(spacing: 24) { lightMetric("WORKOUT PACE", Format.pace(run.pace)); lightMetric("AVG HEART RATE", Format.number(run.averageHR, unit: "bpm")) }
                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.48, dampingFraction: 0.54)) { chaseCount += 1 }
                } label: {
                    HStack(spacing: 11) {
                        Image(systemName: "figure.run")
                            .font(.title2)
                            .offset(x: reduceMotion ? 0 : CGFloat(chaseCount % 4) * 13)
                            .symbolEffect(.bounce, value: chaseCount)
                            .frame(width: 78, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Tap to chase the clue").font(.subheadline.weight(.bold))
                            Text(chaseCount == 0 ? "The runner moves. The data stays honest." : chaseCount.isMultiple(of: 3) ? "Case closed? Nice try. Check the comparison." : "Caught a clue. Keep investigating.")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.75))
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "hand.tap")
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 15))
                }
                .buttonStyle(AnimatedCardButtonStyle())
                .sensoryFeedback(.selection, trigger: chaseCount)
                NavigationLink { WorkoutView(workout: run) } label: {
                    Label("Open workout details", systemImage: "arrow.up.right")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(AnimatedCardButtonStyle())
                Text("Workout pace includes pauses if Apple Health did not provide moving time.").font(.caption2).foregroundStyle(.white.opacity(0.7))
            }.foregroundStyle(.white).padding(23).frame(maxWidth: .infinity, alignment: .leading).background(Color(red: 0.09, green: 0.19, blue: 0.18), in: RoundedRectangle(cornerRadius: 28))
            .overlay(alignment: .topTrailing) { RunnerGlass(trigger: chaseCount).padding(18) }
            .caseMotion(tint: .mint)
    }
    private func comparison(_ latest: RunWorkout, _ match: RunWorkout) -> some View {
        let readout = RunReadout.make(latest: latest, previous: match)
        return VStack(alignment: .leading, spacing: 16) {
            HStack { DetectiveBadge(symbol: "waveform.path.ecg", tint: .teal); Text("RUN VS RUN · THE READOUT").font(.caption.weight(.bold)).tracking(1.6).foregroundStyle(.secondary); Spacer(); Text(readout.confidence).font(.caption2.weight(.semibold)).foregroundStyle(.secondary); statusDiamond(readout.tone == .improved ? .improved : readout.tone == .caution ? .caution : .context) }
            Label(readout.title, systemImage: readout.tone == .improved ? "arrow.up.right" : readout.tone == .caution ? "exclamationmark.circle" : "equal.circle").font(.title2.weight(.bold)).foregroundStyle(readout.tone == .caution ? .orange : .primary)
            Text(readout.detail).font(.body).fixedSize(horizontal: false, vertical: true)
            Button {
                withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.72)) { revealComparison.toggle() }
            } label: {
                Label(revealComparison ? "Hide the caveats" : "Tap for the caveats", systemImage: revealComparison ? "eye.slash" : "eye")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.orange.opacity(0.11), in: RoundedRectangle(cornerRadius: 13))
            }
            .buttonStyle(AnimatedCardButtonStyle())
            .sensoryFeedback(.selection, trigger: revealComparison)
            if revealComparison {
                Text(readout.caveat).font(.footnote).foregroundStyle(.secondary)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
            HStack { VStack(alignment: .leading) { Text(latest.start.formatted(date: .abbreviated, time: .shortened)).font(.caption2.weight(.bold)).foregroundStyle(.secondary); Text(Format.pace(latest.pace)).font(.headline.monospacedDigit()) }; Spacer(); Image(systemName: "arrow.left.arrow.right").foregroundStyle(.secondary); Spacer(); VStack(alignment: .trailing) { Text(match.start.formatted(date: .abbreviated, time: .shortened)).font(.caption2.weight(.bold)).foregroundStyle(.secondary); Text(Format.pace(match.pace)).font(.headline.monospacedDigit()) } }.padding(16).background(.mint.opacity(0.09), in: RoundedRectangle(cornerRadius: 16))
            Label(readout.suggestion, systemImage: "lightbulb").font(.subheadline.weight(.medium))
            DisclosureGroup("Why this comparison?") { Text(readout.caveat).font(.footnote).foregroundStyle(.secondary).padding(.top, 7) }.font(.footnote.weight(.semibold))
            CardClue(lines: ["The stopwatch has evidence, not opinions.", "One matched pair is a lead, not a verdict."])
        }.frame(maxWidth: .infinity, alignment: .leading).padding(20).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
            .caseMotion(tint: .orange)
    }
    private func noMatch(_ run: RunWorkout) -> some View {
        VStack(alignment: .leading, spacing: 10) { DetectiveBadge(symbol: "magnifyingglass", tint: .orange); Text("One run so far").font(.title3.weight(.bold)); Text("A run vs run comparison needs two recorded running workouts."); Text("Your next Health run will appear here automatically.").foregroundStyle(.secondary) }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
            .caseMotion(tint: .orange)
    }
    private var leadAnalysisCard: some View {
        analyticsCard("WEEKLY SIGNAL", symbol: "waveform.path", tint: .teal, signal: weeklyPair?.findings.first.map { signalTone($0.tone) }) {
            if let pair = weeklyPair, let lead = pair.findings.first {
                Text(periodCaption(pair))
                    .font(.footnote).foregroundStyle(.secondary)
                Label(lead.title, systemImage: findingSymbol(lead.tone))
                    .font(.title2.weight(.bold))
                    .foregroundStyle(findingColor(lead.tone))
                Text(lead.detail).font(.subheadline)
                HStack {
                    Text("\(pair.confidence) CONFIDENCE")
                    Spacer()
                    Text(selectedWeekOffset == 0 ? "CURRENT WEEK INCOMPLETE" : "SELECTED WEEKS")
                }
                .font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                DisclosureGroup("Why this signal?") {
                    Text(lead.why).font(.footnote).foregroundStyle(.secondary).padding(.top, 5)
                }.font(.footnote.weight(.semibold))
            } else {
                Text("Select two valid calendar weeks.").font(.title3.weight(.semibold))
                Text("Weekly values are recalculated from the latest Health snapshot.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
    private var rollingCard: some View {
        let window = rolling
        let recentRuns = window.recent.workouts.filter { $0.kind == .running }
        let previousRuns = window.previous.workouts.filter { $0.kind == .running }
        let runDistance = recentRuns.compactMap(\.distance).reduce(0,+)
        let previousDistance = previousRuns.compactMap(\.distance).reduce(0,+)
        return analyticsCard("THE LIVE 7 DAYS", symbol: "calendar.badge.clock", tint: .mint, trend: metricTrend(runDistance, previousDistance)) {
            Text("\(window.recent.date.formatted(date: .abbreviated, time: .shortened))–\(clockTick.formatted(date: .abbreviated, time: .shortened)) vs \(window.previous.date.formatted(date: .abbreviated, time: .shortened))–\(window.recent.date.formatted(date: .abbreviated, time: .shortened))")
                .font(.footnote).foregroundStyle(.secondary)
            HStack(spacing: 20) {
                metric("RUNNING", Format.distance(runDistance))
                Spacer()
                metric("WALKING", Format.distance(window.recent.workouts.filter { $0.kind == .walking }.compactMap(\.distance).reduce(0,+)))
                Spacer()
                metric("SESSIONS", "\(window.recent.workouts.count)")
            }
            if let change = RunMath.percent(runDistance, previousDistance) {
                changeBadge(abs(change) < 0.5 ? "STEADY VOLUME" : "\(Int(abs(change).rounded()))% \(change > 0 ? "MORE" : "LESS")", symbol: abs(change) < 0.5 ? "equal" : change > 0 ? "arrow.up.right" : "arrow.down.right", tone: .context)
                if abs(change) < 0.5 {
                    Label("Running distance was essentially unchanged from the preceding 7 days.", systemImage: "equal.circle")
                        .font(.subheadline.weight(.medium))
                } else {
                    Label("Running distance \(Int(abs(change).rounded()))% \(change > 0 ? "higher" : "lower") than the preceding 7 days.", systemImage: change > 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.subheadline.weight(.medium))
                }
            } else {
                Text(runDistance == 0 ? "No run in the last 7 days. Select earlier weeks above to inspect a previous comparison." : "No running distance in the preceding 7 days, so there is no percentage baseline.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Text("Why? Each window is seven days long. The current window includes today and can change tomorrow.").font(.footnote).foregroundStyle(.secondary)
        }
    }
    private func findingsCard(_ pair: RunningWeekComparison) -> some View {
        analyticsCard("WHAT THE DATA SAYS", symbol: "sparkle.magnifyingglass", tint: .orange, signal: pair.findings.contains { $0.tone == .caution } ? .caution : pair.findings.contains { $0.tone == .improved } ? .improved : .context) {
            Text("\(pair.confidence) CONFIDENCE · \(periodCaption(pair))")
                .font(.caption.weight(.bold)).foregroundStyle(.secondary)
            ForEach(pair.findings) { finding in
                VStack(alignment: .leading, spacing: 7) {
                    Label(finding.title, systemImage: findingSymbol(finding.tone))
                        .font(.headline).foregroundStyle(findingColor(finding.tone))
                    Text(finding.detail).font(.subheadline)
                    DisclosureGroup("Why this observation?") {
                        Text(finding.why).font(.footnote).foregroundStyle(.secondary).padding(.top, 5)
                    }.font(.footnote.weight(.semibold))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(findingColor(finding.tone).opacity(0.09), in: RoundedRectangle(cornerRadius: 16))
            }
            Text("No diagnosis. No victory lap from one number.").font(.footnote).foregroundStyle(.secondary)
        }
    }
    private func weekComparisonCard(_ pair: RunningWeekComparison) -> some View {
        analyticsCard("RUNNING WEEKS", symbol: "calendar.badge.magnifyingglass", tint: .indigo, trend: metricTrend(pair.recentDistance, pair.previousDistance)) {
            Text(periodCaption(pair)).font(.footnote).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline) {
                metric("RECENT · \(pair.recent.start.formatted(date: .abbreviated, time: .omitted))", Format.distance(pair.recentDistance))
                Spacer()
                Image(systemName: "arrow.left.arrow.right").foregroundStyle(.secondary)
                Spacer()
                metric("BEFORE · \(pair.previous.start.formatted(date: .abbreviated, time: .omitted))", Format.distance(pair.previousDistance))
            }
            if let change = RunMath.percent(pair.recentDistance, pair.previousDistance) {
                changeBadge(change > 30 ? "VOLUME JUMP" : abs(change) < 0.5 ? "STEADY VOLUME" : change > 0 ? "MORE VOLUME" : "LESS VOLUME", symbol: change > 30 ? "exclamationmark" : abs(change) < 0.5 ? "equal" : change > 0 ? "arrow.up.right" : "arrow.down.right", tone: change > 30 ? .caution : .context)
                if abs(change) < 0.5 {
                    Label("Running distance was essentially unchanged", systemImage: "equal.circle")
                        .font(.title3.weight(.semibold))
                } else {
                    Label("\(Int(abs(change).rounded()))% \(change > 0 ? "more" : "less") running distance", systemImage: change > 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.title3.weight(.semibold))
                }
            } else {
                Text("Distance change unavailable: the earlier week has no recorded running distance.").font(.subheadline).foregroundStyle(.secondary)
            }
            Text("\(pair.recentRuns.count) vs \(pair.previousRuns.count) runs · \(pair.recentDays) vs \(pair.previousDays) running days")
                .font(.subheadline).foregroundStyle(.secondary)
            Text("Running time: \(Format.duration(pair.recentRuns.reduce(0) { $0 + $1.duration })) vs \(Format.duration(pair.previousRuns.reduce(0) { $0 + $1.duration }))")
                .font(.subheadline).foregroundStyle(.secondary)
            if pair.skippedWeeks > 0 {
                Label("\(pair.skippedWeeks) inactive running week\(pair.skippedWeeks == 1 ? "" : "s") between them", systemImage: "calendar.badge.exclamationmark")
                    .font(.footnote).foregroundStyle(.orange)
            }
            Text("Why? These are the selected calendar weeks. The current week is partial; a skipped week is shown explicitly.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
    private func weeklySessionCards(_ pair: RunningWeekComparison) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if pair.recentRuns.isEmpty {
                analyticsCard("RUNS IN THE SELECTED WEEK", symbol: "figure.run", tint: .teal, trend: .unavailable) {
                    Text(periodCaption(pair)).font(.footnote).foregroundStyle(.secondary)
                    Text("No running sessions in this week.").font(.headline)
                    Text("Weekly distance can still be compared, but there is no per-run pace or heart-rate verdict.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            } else {
                ForEach(pair.recentRuns.sorted { $0.start > $1.start }) { run in
                    let match = pair.sessionMatches.first { $0.recent.id == run.id }?.previous
                    weeklySessionCard(run, match: match,
                                      reusedBaseline: match.map { baseline in pair.sessionMatches.filter { $0.previous?.id == baseline.id }.count > 1 } ?? false)
                    if let match { runMetricCards(run, match, titlePrefix: "WEEKLY RUN") }
                }
            }
        }
    }
    private func weeklySessionCard(_ run: RunWorkout, match: RunWorkout?, reusedBaseline: Bool) -> some View {
        let readout = match.map { RunReadout.make(latest: run, previous: $0) }
        return analyticsCard("WEEKLY RUN · \(run.start.formatted(date: .abbreviated, time: .omitted))", symbol: "figure.run", tint: .teal,
                             signal: readout.map { $0.tone == .improved ? .improved : $0.tone == .caution ? .caution : .context }) {
            Text("THIS RUN · \(run.start.formatted(date: .complete, time: .shortened))")
                .font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            if let match {
                Text("COMPARE WITH · \(match.start.formatted(date: .complete, time: .shortened))")
                    .font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            } else {
                Text("No similar-distance run in the earlier week.")
                    .font(.subheadline).foregroundStyle(.orange)
            }
            Text("\(Format.distance(run.distance)) · \(Format.pace(run.pace)) · \(Format.number(run.averageHR, unit: "bpm"))")
                .font(.title3.weight(.semibold)).monospacedDigit()
            if let readout {
                Label(readout.title, systemImage: findingSymbol(readout.tone == .improved ? .improved : readout.tone == .caution ? .caution : .observation))
                    .font(.headline).foregroundStyle(readout.tone == .improved ? .teal : readout.tone == .caution ? .orange : .primary)
                Text(readout.detail).font(.subheadline)
                DisclosureGroup("Why this conclusion?") { Text(readout.caveat).font(.footnote).foregroundStyle(.secondary).padding(.top, 5) }
                    .font(.footnote.weight(.semibold))
            }
            if reusedBaseline && match != nil {
                Text("The earlier week has fewer runs. This comparison run may also appear beside another session; these are not independent improvements.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Text("Goal: faster pace at similar or lower heart rate. The next cards show pace, HR, distance, and energy separately for this run.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
    private func walkingCard(_ pair: RunningWeekComparison) -> some View {
        let current = pair.recent.distance(.walking)
        let before = pair.previous.distance(.walking)
        return analyticsCard("WALKING DISTANCE", symbol: "figure.walk", tint: .mint, trend: metricTrend(current, before)) {
            Text(periodCaption(pair)).font(.footnote).foregroundStyle(.secondary)
            HStack { metric("RECENT", Format.distance(current)); Spacer(); metric("PREVIOUS", Format.distance(before)) }
            Text(current == before ? "Walking distance was unchanged." : "Walking distance was \(Format.distance(abs(current - before))) \(current > before ? "higher" : "lower").")
                .font(.subheadline)
            Text("This is walking only. It does not affect the running pace verdict.").font(.footnote).foregroundStyle(.secondary)
        }
    }
    private func dailyCard(_ day: ActivitySummary) -> some View {
        let runs = day.workouts.filter { $0.kind == .running }
        let walks = day.workouts.filter { $0.kind == .walking }
        return analyticsCard("LAST ACTIVE DAY", symbol: "calendar.day.timeline.left", tint: .mint) {
            Text(day.date.formatted(date: .complete, time: .omitted)).font(.title3.weight(.semibold))
            HStack(spacing: 20) {
                metric("DISTANCE", Format.distance(day.distance))
                Spacer()
                metric("DURATION", Format.duration(day.duration))
                Spacer()
                metric("SESSIONS", "\(day.workouts.count)")
            }
            Text("\(runs.count) run\(runs.count == 1 ? "" : "s") · \(walks.count) walk\(walks.count == 1 ? "" : "s") · \(Format.number(day.energy, unit: "kcal")) active energy")
                .font(.subheadline).foregroundStyle(.secondary)
            if day.workouts.count > 1 { Label("Separate workouts kept intact; daily distance and duration are summed.", systemImage: "square.stack.3d.up").font(.footnote).foregroundStyle(.secondary) }
            Text("Running and walking pace are kept separate. Tap History to inspect each original workout.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
    private var comparisonNeedsDataCard: some View {
        analyticsCard("WEEKLY ANALYSIS", symbol: "chart.bar.xaxis", tint: .orange) {
            Text("Choose two different weeks").font(.headline)
            Text("Choose two different calendar weeks. Each comparison card updates from the latest Health sync.")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }
    private func analyticsCard<Content: View>(_ title: String, symbol: String, tint: Color, signal: ChangeTone? = nil, trend: MetricTrend? = nil, trendTint: Color? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 12) { DetectiveBadge(symbol: symbol, tint: tint); Text(title).font(.caption.weight(.bold)).tracking(1.4).foregroundStyle(.secondary); Spacer(minLength: 4); if let trend { trendDiamond(trend, tint: trendTint) } else if let signal { statusDiamond(signal) } }
            content()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
        .caseMotion(tint: tint)
    }
    private func findingSymbol(_ tone: AnalysisFinding.Tone) -> String {
        switch tone { case .improved: "arrow.up.right.circle"; case .caution: "exclamationmark.circle"; case .observation: "eye.circle"; case .insufficient: "questionmark.circle" }
    }
    private func findingColor(_ tone: AnalysisFinding.Tone) -> Color {
        switch tone { case .improved: .teal; case .caution: .orange; case .observation: .indigo; case .insufficient: .secondary }
    }
    private enum ChangeTone { case improved, caution, context }
    private enum MetricTrend { case up, down, flat, unavailable }
    private func metricTrend(_ current: Double, _ previous: Double, epsilon: Double = 0.5) -> MetricTrend {
        let difference = current - previous
        return abs(difference) < epsilon ? .flat : difference > 0 ? .up : .down
    }
    private func trendDiamond(_ trend: MetricTrend, tint tintOverride: Color? = nil) -> some View {
        let symbol = switch trend { case .up: "arrow.up.right"; case .down: "arrow.down.right"; case .flat: "equal"; case .unavailable: "questionmark" }
        let label = switch trend { case .up: "Value increased"; case .down: "Value decreased"; case .flat: "Value steady"; case .unavailable: "Change unavailable" }
        let tint: Color = trend == .unavailable ? .secondary : (tintOverride ?? .indigo)
        return ZStack {
            RoundedRectangle(cornerRadius: 7).fill(tint.opacity(0.14))
                .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(tint.opacity(0.5), lineWidth: 1.5) }
                .frame(width: 31, height: 31).rotationEffect(.degrees(45))
            Image(systemName: symbol).font(.caption.weight(.black)).foregroundStyle(tint)
        }.frame(width: 44, height: 44).accessibilityLabel(label).allowsHitTesting(false)
    }
    private func signalTone(_ tone: AnalysisFinding.Tone) -> ChangeTone {
        switch tone { case .improved: .improved; case .caution: .caution; case .observation, .insufficient: .context }
    }
    private func statusDiamond(_ tone: ChangeTone) -> some View {
        let tint: Color = switch tone { case .improved: .teal; case .caution: .orange; case .context: .secondary }
        let symbol = switch tone { case .improved: "arrow.up.right"; case .caution: "exclamationmark"; case .context: "equal" }
        let meaning = switch tone { case .improved: "Improvement"; case .caution: "Caution"; case .context: "Context only" }
        return ZStack {
            RoundedRectangle(cornerRadius: 7)
                .fill(tint.opacity(0.15))
                .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(tint.opacity(0.55), lineWidth: 1.5) }
                .frame(width: 31, height: 31)
                .rotationEffect(.degrees(45))
            Image(systemName: symbol).font(.caption.weight(.black)).foregroundStyle(tint)
        }
        .frame(width: 44, height: 44)
        .accessibilityLabel("\(meaning) signal")
        .allowsHitTesting(false)
    }
    private func changeBadge(_ title: String, symbol: String, tone: ChangeTone) -> some View {
        let tint: Color = switch tone { case .improved: .teal; case .caution: .orange; case .context: .secondary }
        return Label(title, systemImage: symbol)
            .font(.caption2.weight(.heavy))
            .tracking(0.4)
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(tint.opacity(0.12), in: Capsule())
            .accessibilityLabel("\(title), \(tone == .improved ? "improvement" : tone == .caution ? "caution" : "context only")")
    }
    private var weekCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { DetectiveBadge(symbol: "calendar", tint: .indigo); Text("THIS WEEK · LIVE").font(.caption.weight(.bold)).tracking(1.6).foregroundStyle(.secondary); Spacer(); Text("IN PROGRESS").font(.caption2.weight(.bold)).foregroundStyle(.secondary) }
            if let week { Text("\(week.start.formatted(date: .abbreviated, time: .omitted))–\(clockTick.formatted(date: .abbreviated, time: .omitted))").font(.footnote).foregroundStyle(.secondary) }
            Text(Format.distance(week?.all.distance ?? 0)).font(.system(size: 31, weight: .semibold, design: .rounded))
            HStack { metric("Running", Format.distance(week?.distance(.running) ?? 0)); Spacer(); metric("Walking", Format.distance(week?.distance(.walking) ?? 0)); Spacer(); metric("Sessions", "\(week?.workouts.count ?? 0)") }
            if week?.workouts.isEmpty == true {
                Text(latestRun == nil ? "No sessions logged this week. The first Health workout will open the case." : "No sessions logged this week. Your latest run readout above stays available.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            CardClue(lines: ["The week is still unfolding. The calendar has an alibi.", "A quiet week is a blank page, not a verdict."])
        }.padding(20).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
            .caseMotion(tint: .indigo)
    }
    private func recentChart(_ runs: [RunWorkout]) -> some View {
        let plotted = runs.filter { $0.pace != nil }.sorted { $0.start < $1.start }
        let selected = selectedRecentRunDate.flatMap { date in plotted.min { abs($0.start.timeIntervalSince(date)) < abs($1.start.timeIntervalSince(date)) } }
        return VStack(alignment: .leading, spacing: 10) {
            HStack { DetectiveBadge(symbol: "chart.xyaxis.line", tint: .mint); Text("RECENT RUN PACE").font(.caption.weight(.bold)).tracking(1.5).foregroundStyle(.secondary) }
            if let first = plotted.first, let last = plotted.last {
                Text("\(first.start.formatted(date: .abbreviated, time: .omitted))–\(last.start.formatted(date: .abbreviated, time: .omitted)) · \(plotted.count) runs")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let selected {
                HStack {
                    Text(selected.start.formatted(date: .abbreviated, time: .omitted))
                    Spacer()
                    Text(Format.pace(selected.pace)).fontWeight(.bold).monospacedDigit()
                }.font(.subheadline).foregroundStyle(.teal)
            } else { Text("Slide across the chart to inspect a run").font(.footnote).foregroundStyle(.secondary) }
            Chart {
                ForEach(plotted) { run in
                    if let pace = run.pace {
                        LineMark(x: .value("Date", run.start), y: .value("Pace", pace)).foregroundStyle(.mint)
                        PointMark(x: .value("Date", run.start), y: .value("Pace", pace)).foregroundStyle(.mint)
                    }
                }
                if let selected, let pace = selected.pace {
                    RuleMark(x: .value("Selected run", selected.start)).foregroundStyle(.teal.opacity(0.55))
                    PointMark(x: .value("Selected run", selected.start), y: .value("Selected pace", pace))
                        .symbolSize(100).foregroundStyle(.teal)
                }
            }
            .chartXSelection(value: $selectedRecentRunDate)
            .simultaneousGesture(DragGesture(minimumDistance: 4).onChanged { _ in recentChartScrubbing = true }.onEnded { _ in
                Task { try? await Task.sleep(for: .milliseconds(250)); recentChartScrubbing = false }
            })
            .frame(height: 155)
            Text("Lower means faster. These runs may differ in distance, elevation, and intent; use the matched readout for a fairer comparison.").font(.footnote).foregroundStyle(.secondary)
            CardClue(lines: ["Plot twist: lower pace means faster running.", "The line can zigzag. Routes have opinions too."])
        }.padding(20).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
            .caseMotion(tint: .mint, suppressTap: recentChartScrubbing)
    }
    private var firstRunState: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.5)) { runnerHop.toggle() }
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "figure.run")
                        .font(.system(size: 38, weight: .medium))
                        .offset(x: runnerHop ? 20 : 0, y: runnerHop ? -7 : 0)
                        .rotationEffect(.degrees(runnerHop ? -8 : 0))
                    VStack(alignment: .leading) { Text("Tap the runner").font(.headline); Text(runnerHop ? "He's still looking for evidence." : "See if he finds a clue.").font(.caption) }
                    Spacer()
                    Image(systemName: "hand.tap")
                }
                .foregroundStyle(.teal)
                .padding(16)
                .background(.teal.opacity(0.11), in: RoundedRectangle(cornerRadius: 18))
            }.buttonStyle(AnimatedCardButtonStyle()).sensoryFeedback(.selection, trigger: runnerHop)
            Text("The case starts with a run.").font(.title2.weight(.bold))
            Text("Once Apple Health has a recorded run, this page will show what happened and find a fair comparison. Walking activity still appears in History.").foregroundStyle(.secondary)
            CardClue(lines: ["The detective is waiting for a first clue.", "No fabricated evidence in this case file."])
        }.padding(25).frame(maxWidth: .infinity, alignment: .leading).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 26))
            .caseMotion(tint: .teal)
    }
}
private func lightMetric(_ title: String, _ value: String) -> some View { VStack(alignment: .leading, spacing: 4) { Text(title).font(.caption2.weight(.bold)).foregroundStyle(.white.opacity(0.7)); Text(value).font(.headline.monospacedDigit()) } }
