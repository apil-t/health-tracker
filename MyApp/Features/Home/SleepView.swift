import SwiftUI

struct SleepView: View {
    @Environment(HealthStore.self) private var store
    @State private var period = TrendPeriod.week

    var body: some View {
        let lastNight = store.summary(on: .now)
        let goalMinutes = store.goalSleepHours * 60

        Screen {
            VStack(alignment: .leading, spacing: 10) {
                TintedLabel(title: "Last night", systemImage: "moon", tint: .sleep)
                    .font(.caption.weight(.semibold)).foregroundStyle(Color.sleep)
                Reading(value: Format.hoursMinutes(store.sleepMinutes), unit: "asleep", font: .system(size: 44), unitFont: .subheadline)
                if let bedtime = lastNight.bedtime, let wakeTime = lastNight.wakeTime {
                    Text("\((bedtime..<wakeTime).formatted(.interval.hour().minute())) in bed")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Meter(fraction: store.sleepFraction, color: .sleep, height: 8)
                Text(HealthRules.toGo(goalMinutes - store.sleepMinutes, unit: "min") + " · goal \(store.goalSleepHours)h")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .card(padding: 20)

            Picker("Period", selection: $period) {
                ForEach(TrendPeriod.allCases) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)

            TrendCard(days: store.summaries(lastDays: period.days), value: \.sleepMinutes, goal: goalMinutes, color: .sleep,
                      format: Format.hoursMinutes, axisFormat: { "\($0 / 60)h" })
        }
        .navigationTitle("Sleep")
        .navigationSubtitle(Format.todayHeading)
    }
}

#Preview {
    NavigationStack { SleepView() }.environment(HealthStore(storageURL: nil))
}
