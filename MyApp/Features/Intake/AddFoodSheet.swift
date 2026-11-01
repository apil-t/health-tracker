import SwiftUI

struct AddFoodSheet: View {
    @Environment(HealthStore.self) private var store
    var day: Date = .now
    @State private var kind = Meal.Kind.snack
    @State private var food = ""
    @State private var kcal: Int?

    var body: some View {
        FormSheet(title: "Add food", canSave: !food.trimmingCharacters(in: .whitespaces).isEmpty && (kcal ?? 0) > 0) {
            store.addMeal(kind: kind, food: food, kcal: kcal ?? 0, on: day)
        } content: {
            Picker("Meal", selection: $kind) {
                ForEach(Meal.Kind.allCases, id: \.self) { Text($0.rawValue) }
            }
            TextField("What did you eat?", text: $food)
            TextField("Energy (kcal)", value: $kcal, format: .number)
                .keyboardType(.numberPad)
        }
    }
}
