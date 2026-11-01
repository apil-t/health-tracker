import SwiftUI
import Charts

struct WorkoutView: View {
    let workout: Workout
    @Environment(HealthStore.self) private var store

    var body: some View {
        Screen {
            HStack {
                TintedLabel(title: "\(workout.setting) \(workout.kind.rawValue.lowercased())", systemImage: workout.kind.symbol)
                    .font(.caption.weight(.medium))
                Spacer()
                Text(store.deviceName).font(.caption2).foregroundStyle(.secondary)
            }

            VStack(spacing: 15) {
                HStack {
                    Stat(label: "Distance", value: workout.distanceKm?.formatted(.number.precision(.fractionLength(2))) ?? "–", unit: "km")
                    Stat(label: "Duration", value: Format.minutesSeconds(workout.minutes * 60), unit: "min")
                }
                Divider()
                HStack {
                    Stat(label: "Active energy", value: "\(workout.kcal)", unit: "kcal")
                    Stat(label: "Average pace", value: workout.paceSeconds.map(Format.minutesSeconds) ?? "–", unit: "/km")
                }
            }
            .card(padding: 18)

            if !workout.heartRate.isEmpty { heartRateCard }
            if !workout.splits.isEmpty { splitsCard }
        }
        .navigationTitle(workout.name)
        .navigationSubtitle("\(workout.start.formatted(.dateTime.day().month(.wide))) · \(workout.timeRange)".uppercased())
    }

    private var heartRateCard: some View {
        let hr = workout.heartRate

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Heart rate").font(.headline)
                Spacer()
                Image(systemName: "heart").foregroundStyle(Color.heart)
            }
            HStack(spacing: 25) {
                Reading(value: "\(workout.averageHeartRate)", unit: "bpm avg")
                Reading(value: "\(workout.maxHeartRate)", unit: "bpm max")
            }
            Chart(hr.indices, id: \.self) { i in
                AreaMark(x: .value("Minute", workout.heartRateMinute(at: i)), yStart: .value("Floor", 80), yEnd: .value("BPM", hr[i]))
                    .foregroundStyle(Color.heart.opacity(0.12))
                LineMark(x: .value("Minute", workout.heartRateMinute(at: i)), y: .value("BPM", hr[i]))
                    .foregroundStyle(Color.heart)
            }
            .chartXScale(domain: 0...workout.minutes)
            .chartYScale(domain: 80...180)
            .chartYAxis { AxisMarks(values: [100, 140, 180]) { _ in AxisGridLine() } }
            .chartXAxis { AxisMarks(values: .stride(by: 8)) { _ in AxisValueLabel() } }
            .frame(height: 100)
        }
        .card(padding: 18)
    }

    private var splitsCard: some View {
        let slowest = workout.splits.max() ?? 1

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Kilometre splits").font(.headline)
                Spacer()
                Text("Pace /km").font(.caption2).foregroundStyle(.secondary)
            }
            ForEach(Array(workout.splits.enumerated()), id: \.offset) { i, pace in
                HStack(spacing: 12) {
                    Text("\(i + 1)").font(.caption2).foregroundStyle(.secondary).frame(width: 14, alignment: .leading)
                    Meter(fraction: 0.55 * Double(pace) / Double(slowest), color: .accentColor.opacity(0.2), height: 8, showsTrack: false)
                    Text(Format.minutesSeconds(pace)).font(.caption.weight(.medium)).monospacedDigit()
                }
            }
            if let final = workout.finalSplit {
                Text("Final \(final.km.formatted(.number.precision(.fractionLength(2)))) km · \(Format.minutesSeconds(final.seconds)) · \(Format.minutesSeconds(final.pace)) /km")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .card(padding: 18)
    }
}

#Preview {
    NavigationStack { WorkoutView(workout: HealthStore(storageURL: nil).workouts[0]) }.environment(HealthStore())
}
