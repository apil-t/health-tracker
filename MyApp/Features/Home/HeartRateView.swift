import SwiftUI
import Charts

struct HeartRateView: View {
    enum Period: String, CaseIterable, Identifiable {
        case day = "Day", week = "Week", month = "Month", year = "Year"
        var id: Self { self }
    }

    @Environment(HealthStore.self) private var store
    @State private var period = Period.day

    var body: some View {
        let insight = HealthRules.restingInsight(resting: store.restingHeartRate, average30Day: store.restingHeartRate30Day)

        Screen {
            Picker("Period", selection: $period) {
                ForEach(Period.allCases) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)

            switch period {
            case .day: latestCard
            case .week: restingTrendCard(days: TrendPeriod.week.days)
            case .month: restingTrendCard(days: TrendPeriod.month.days)
            case .year: restingTrendCard(days: TrendPeriod.year.days)
            }

            SectionHeading(title: "Today’s range")

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Stat(label: "Resting", value: "\(store.restingHeartRate)", unit: "bpm")
                    Stat(label: "Average", value: "\(store.heartRateAverage)", unit: "bpm")
                }
                Divider()
                HStack {
                    Text("Lowest \(store.heartRateLowest) bpm")
                    Spacer()
                    Text("Highest \(store.heartRateHighest) bpm")
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            .card(padding: 18)

            InsightCard(insight: insight, systemImage: insight.isPositive ? "chart.line.downtrend.xyaxis" : "chart.line.uptrend.xyaxis")
        }
        .navigationTitle("Heart rate")
        .navigationSubtitle(Format.todayHeading)
    }

    /// Resting heart rate per day: the usual long-term measure (lower generally means fitter).
    private func restingTrendCard(days count: Int) -> some View {
        let days = store.summaries(lastDays: count).filter { $0.restingHeartRate != nil }
        let values = days.compactMap(\.restingHeartRate)

        return VStack(alignment: .leading, spacing: 16) {
            TintedLabel(title: "Resting heart rate", systemImage: "heart", tint: .heart)
                .font(.caption.weight(.semibold)).foregroundStyle(Color.heart)
            if values.isEmpty {
                Text("No resting heart rate recorded in this period.").font(.caption).foregroundStyle(.secondary)
            } else {
                HStack {
                    Stat(label: "Average", value: "\(values.reduce(0, +) / values.count)", unit: "bpm")
                    Stat(label: "Lowest", value: "\(values.min()!)", unit: "bpm")
                    Stat(label: "Highest", value: "\(values.max()!)", unit: "bpm")
                }
                Chart(days, id: \.day) { day in
                    LineMark(x: .value("Day", day.day, unit: .day), y: .value("BPM", day.restingHeartRate ?? 0))
                        .interpolationMethod(.catmullRom)
                    if count <= 31 {
                        PointMark(x: .value("Day", day.day, unit: .day), y: .value("BPM", day.restingHeartRate ?? 0))
                            .symbolSize(20)
                    }
                }
                .foregroundStyle(Color.heart)
                .chartYScale(domain: .automatic(includesZero: false))
                .chartYAxis { AxisMarks(position: .trailing) }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: count <= 7 ? 7 : 5)) { _ in
                        AxisValueLabel(format: count <= 7 ? .dateTime.weekday(.narrow) : .dateTime.day().month(.abbreviated))
                    }
                }
                .frame(height: 163)
            }
        }
        .card(padding: 20)
    }

    private var latestCard: some View {
        let readings = store.heartRateToday
        let run = store.workoutsToday.first

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    TintedLabel(title: "Latest heart rate", systemImage: "heart", tint: .heart)
                        .font(.caption.weight(.semibold)).foregroundStyle(Color.heart)
                    Reading(value: "\(store.heartRate)", unit: "bpm", font: .system(size: 44), unitFont: .subheadline)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 5) {
                    Text(store.latestHeartRateTime, format: .dateTime.hour().minute())
                        .font(.caption2).foregroundStyle(.secondary)
                    Text(HealthRules.isAtRest(bpm: store.heartRate, resting: store.restingHeartRate) ? "At rest" : "Active")
                        .font(.caption2.weight(.medium)).foregroundStyle(.tint)
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(Color.accentColor.opacity(0.12), in: .rect(cornerRadius: 8))
                }
            }

            Chart {
                if let run {
                    RectangleMark(xStart: .value("Start", run.start.hourOfDay), xEnd: .value("End", run.end.hourOfDay))
                        .foregroundStyle(Color.heart.opacity(0.12))
                        .cornerRadius(4)
                }
                ForEach(readings.indices, id: \.self) { i in
                    LineMark(x: .value("Hour", store.heartRateHour(at: i)), y: .value("BPM", readings[i]))
                }
                .foregroundStyle(Color.heart)
                if let last = readings.last {
                    PointMark(x: .value("Hour", store.heartRateHour(at: readings.count - 1)), y: .value("BPM", last))
                        .foregroundStyle(Color.heart)
                        .symbolSize(30)
                }
            }
            .chartXScale(domain: 0...21)
            .chartYScale(domain: 40...180)
            .chartYAxis { AxisMarks(position: .trailing, values: [50, 110, 170]) }
            .chartXAxis {
                AxisMarks(values: [0, 6, 12, 18]) { value in
                    AxisValueLabel {
                        if let hour = value.as(Double.self) {
                            Text(Date.today(Int(hour), 0), format: .dateTime.hour())
                        }
                    }
                }
            }
            .frame(height: 163)

            if let run, !run.heartRate.isEmpty {
                TintedLabel(title: "\(run.start.formatted(date: .omitted, time: .shortened)) · \(run.name) · Peak \(run.maxHeartRate) bpm",
                            systemImage: run.kind.symbol, tint: .heart)
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .card(padding: 20)
    }
}

#Preview {
    NavigationStack { HeartRateView() }.environment(HealthStore())
}
