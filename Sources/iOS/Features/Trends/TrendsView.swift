import SwiftUI
import Charts

struct TrendsView: View {
    @EnvironmentObject var health: HealthStore
    @State private var count = 8
    @State private var revealCharts = false
    @State private var selectedWeekDate: Date?
    @State private var chartScrubbing = false
    private struct TrendPoint: Identifiable {
        let date: Date
        let amount: Double
        var id: Date { date }
    }
    private var weeks: [WeekSummary] { Array(RunMath.weeks(health.workouts).prefix(count).reversed()) }
    var body: some View {
        GeometryReader { geometry in
            let expanded = geometry.size.width >= 760
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Picker("Period", selection: $count) { Text("4W").tag(4); Text("8W").tag(8); Text("3M").tag(13); Text("6M").tag(26); Text("1Y").tag(52); Text("ALL").tag(Int.max) }.pickerStyle(.segmented)
                    distanceChart
                    if expanded {
                        HStack(alignment: .top, spacing: 20) {
                            paceChart.frame(maxWidth: .infinity, alignment: .topLeading)
                            heartRateChart.frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                    } else {
                        paceChart
                        heartRateChart
                    }
                }
                .frame(maxWidth: expanded ? 1500 : 760)
                .padding(.horizontal, expanded ? 32 : 16)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
            }
        }
        .background(AmbientBackdrop()).navigationTitle("Trends").onAppear { withAnimation(.easeOut(duration: 0.55)) { revealCharts = true } }
            .onChange(of: count) { selectedWeekDate = nil }
    }
    private var distanceChart: some View {
        chart("Weekly distance", symbol: "figure.run", unit: "km", explanation: "Each point is one calendar week. A higher point means more total running and walking distance; the current week may be incomplete.") { week in week.all.distance / 1000 }
    }
    private var paceChart: some View {
        chart("Running pace", symbol: "speedometer", unit: "sec/km", explanation: "Lower is faster. This is total running workout time divided by total running distance. Route, distance, and pauses may differ by week.") { week in week.pace(.running) }
    }
    private var heartRateChart: some View {
        chart("Running HR", symbol: "heart", unit: "bpm", explanation: "This is observed average heart rate for runs with HR samples. Missing samples are excluded. Compare it with pace and conditions, not alone.") { week in week.heartRate(.running) }
    }
    private func chart(_ title: String, symbol: String, unit: String, explanation: String, value: @escaping (WeekSummary) -> Double?) -> some View {
        let points = weeks.compactMap { week -> TrendPoint? in
            guard let amount = value(week), amount.isFinite else { return nil }
            return TrendPoint(date: week.start, amount: amount)
        }
        let selected = selectedWeekDate.flatMap { date in points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) } }
        return VStack(alignment: .leading, spacing: 12) {
            HStack { DetectiveBadge(symbol: symbol, tint: .teal); Text(title).font(.headline) }
            if let selected {
                HStack {
                    Text("Week of \(selected.date.formatted(date: .abbreviated, time: .omitted))")
                    Spacer()
                    Text(unit == "sec/km" ? Format.pace(selected.amount) : Format.number(selected.amount, unit: unit, digits: unit == "km" ? 2 : 0))
                        .fontWeight(.bold).monospacedDigit()
                }.font(.subheadline).foregroundStyle(.teal)
            } else { Text("Slide across the chart for exact weekly values").font(.footnote).foregroundStyle(.secondary) }
            Chart {
                ForEach(points) { point in
                    LineMark(x: .value("Week", point.date), y: .value(unit, point.amount)).foregroundStyle(.mint)
                    PointMark(x: .value("Week", point.date), y: .value(unit, point.amount)).foregroundStyle(.mint)
                }
                if let selected {
                    RuleMark(x: .value("Selected week", selected.date)).foregroundStyle(.teal.opacity(0.55))
                    PointMark(x: .value("Selected week", selected.date), y: .value("Selected value", selected.amount))
                        .symbolSize(100).foregroundStyle(.teal)
                }
            }
                .chartXSelection(value: $selectedWeekDate)
                .simultaneousGesture(DragGesture(minimumDistance: 4).onChanged { _ in chartScrubbing = true }.onEnded { _ in
                    Task { try? await Task.sleep(for: .milliseconds(250)); chartScrubbing = false }
                })
                .frame(height: 180)
                .opacity(revealCharts ? 1 : 0)
                .animation(.smooth(duration: 0.45), value: count)
            Text(explanation).font(.footnote).foregroundStyle(.secondary)
            CardClue(lines: ["This graph is a clue, not a confession.", "Look for repeats before naming a trend."])
        }.frame(maxWidth: .infinity, alignment: .leading).padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
            .caseMotion(tint: .teal, suppressTap: chartScrubbing)
    }
}
