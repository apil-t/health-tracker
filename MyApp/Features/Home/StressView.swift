import SwiftUI
import Charts

struct StressView: View {
    @Environment(HealthStore.self) private var store
    @State private var period = TrendPeriod.week

    var body: some View {
        let estimate = store.stressEstimate()

        Screen {
            if let estimate {
                VStack(alignment: .leading, spacing: 10) {
                    TintedLabel(title: "Today", systemImage: "camera.macro", tint: .lavender)
                        .font(.caption.weight(.semibold)).foregroundStyle(Color.lavender)
                    HStack(alignment: .firstTextBaseline) {
                        Reading(value: "\(estimate.score)", unit: "/ 100", font: .system(size: 44), unitFont: .subheadline)
                        Spacer()
                        Text(HealthRules.stressLabel(estimate.score))
                            .font(.caption2.weight(.medium)).foregroundStyle(Color.lavender)
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(Color.lavender.opacity(0.15), in: .rect(cornerRadius: 8))
                    }
                    Meter(fraction: Double(estimate.score) / 100, color: .lavender, height: 8)
                    Text(HealthRules.stressSummary(estimate)).font(.caption).foregroundStyle(.secondary)
                }
                .card(padding: 20)

                SectionHeading(title: "What’s driving it")
                VStack(spacing: 13) {
                    ForEach(Array(estimate.factors.enumerated()), id: \.element.id) { i, factor in
                        if i > 0 { Divider() }
                        FactorRow(factor: factor)
                    }
                }
                .card()
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    TintedLabel(title: "Calibrating", systemImage: "hourglass", tint: .lavender)
                        .font(.footnote.weight(.semibold))
                    Text("Stress needs \(HealthRules.stressBaselineNights) nights of HRV and resting heart rate to learn your usual. "
                         + "\(min(store.stressCalibrationNights, HealthRules.stressBaselineNights)) of \(HealthRules.stressBaselineNights) so far. Keep wearing your Fitbit to bed.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .card(.lavender)
            }

            Picker("Period", selection: $period) {
                ForEach(TrendPeriod.allCases) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)

            trendCard

            InsightCard(insight: Insight(title: "How this is worked out", message: HealthRules.stressExplanation, isPositive: true),
                        systemImage: "info.circle")
        }
        .navigationTitle("Stress")
        .navigationSubtitle(Format.todayHeading)
    }

    private var trendCard: some View {
        let points = store.stressScores(lastDays: period.days).compactMap { p in p.score.map { (day: p.day, score: $0) } }

        return VStack(alignment: .leading, spacing: 14) {
            if points.isEmpty {
                Text("No stress estimates in this period yet.").font(.caption).foregroundStyle(.secondary)
            } else {
                HStack {
                    Stat(label: "Average", value: "\(points.map(\.score).reduce(0, +) / points.count)", unit: "/ 100")
                    Stat(label: "Calmest", value: "\(points.map(\.score).min()!)", unit: "/ 100")
                    Stat(label: "Highest", value: "\(points.map(\.score).max()!)", unit: "/ 100")
                }
                Chart(points, id: \.day) { point in
                    LineMark(x: .value("Day", point.day, unit: .day), y: .value("Stress", point.score))
                        .interpolationMethod(.catmullRom)
                    if points.count <= 31 {
                        PointMark(x: .value("Day", point.day, unit: .day), y: .value("Stress", point.score)).symbolSize(20)
                    }
                }
                .foregroundStyle(Color.lavender)
                .chartYScale(domain: 0...100)
                .chartYAxis { AxisMarks(position: .trailing, values: [0, 33, 66, 100]) }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: period == .week ? 7 : 5)) { _ in
                        AxisValueLabel(format: period == .week ? .dateTime.weekday(.narrow) : .dateTime.day().month(.abbreviated))
                    }
                }
                .frame(height: 163)
            }
        }
        .card(padding: 18)
    }
}

private struct FactorRow: View {
    let factor: StressFactor

    var body: some View {
        let color: Color = factor.strain >= 0.5 ? .heart : factor.strain <= -0.5 ? .accentColor : .secondary

        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(factor.name).font(.footnote.weight(.semibold))
                Text("\(factor.today) · usual \(factor.usual)").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Text(HealthRules.strainLabel(factor.strain))
                .font(.caption2.weight(.medium)).foregroundStyle(color)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(color.opacity(0.12), in: .rect(cornerRadius: 7))
        }
    }
}

#Preview {
    NavigationStack { StressView() }.environment(HealthStore(storageURL: nil))
}
