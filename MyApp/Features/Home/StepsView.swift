import SwiftUI

struct StepsView: View {
    @Environment(HealthStore.self) private var store
    @State private var period = TrendPeriod.week

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: 10) {
                TintedLabel(title: "Today", systemImage: "shoeprints.fill")
                    .font(.caption.weight(.semibold)).foregroundStyle(.tint)
                Reading(value: store.steps.formatted(), unit: "steps", font: .system(size: 44), unitFont: .subheadline)
                Meter(fraction: store.stepsFraction, height: 8)
                Text(HealthRules.toGo(store.goalSteps - store.steps, unit: "steps") + " · goal \(store.goalSteps.formatted())")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .card(padding: 20)

            Picker("Period", selection: $period) {
                ForEach(TrendPeriod.allCases) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)

            TrendCard(days: store.summaries(lastDays: period.days), value: \.steps, goal: store.goalSteps, color: .accentColor,
                      format: { $0.formatted() }, axisFormat: { $0.formatted(.number.notation(.compactName)) })
        }
        .navigationTitle("Steps")
        .navigationSubtitle(Format.todayHeading)
    }
}

#Preview {
    NavigationStack { StepsView() }.environment(HealthStore(storageURL: nil))
}
