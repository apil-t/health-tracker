import SwiftUI

struct GoalsView: View {
    @Environment(HealthStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Form {
            Stepper("Active energy: \(store.goalActiveKcal) kcal", value: $store.goalActiveKcal, in: 100...2_000, step: 50)
            Stepper("Steps: \(store.goalSteps.formatted())", value: $store.goalSteps, in: 1_000...30_000, step: 500)
            Stepper("Sleep: \(store.goalSleepHours) hours", value: $store.goalSleepHours, in: 4...12)
            Stepper("Food: \(store.goalIntakeKcal.formatted()) kcal", value: $store.goalIntakeKcal, in: 1_000...5_000, step: 50)
            Stepper("Water: \(store.goalWaterGlasses) glasses", value: $store.goalWaterGlasses, in: 1...20)
        }
        .navigationTitle("Daily goals")
        .onDisappear { store.save() }
    }
}
