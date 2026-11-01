import SwiftUI

struct LogWorkoutSheet: View {
    @Environment(HealthStore.self) private var store
    @State private var kind = Workout.Kind.run
    @State private var minutes = 30
    @State private var kcal: Int?

    var body: some View {
        FormSheet(title: "Log workout", canSave: (kcal ?? 0) > 0) {
            store.logWorkout(kind: kind, minutes: minutes, kcal: kcal ?? 0)
        } content: {
            Picker("Type", selection: $kind) {
                ForEach(Workout.Kind.allCases, id: \.self) { Text($0.rawValue) }
            }
            Stepper("\(minutes) min", value: $minutes, in: 5...300, step: 5)
            TextField("Active energy (kcal)", value: $kcal, format: .number)
                .keyboardType(.numberPad)
        }
    }
}
