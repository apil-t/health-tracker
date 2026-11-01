import SwiftUI

struct IntakeView: View {
    @Environment(HealthStore.self) private var store
    @State private var dayOffset = 0
    @State private var isAddingFood = false

    private var day: Date { Calendar.current.date(byAdding: .day, value: dayOffset, to: .now)! }

    var body: some View {
        Screen {
            DateSelector(dayOffset: $dayOffset)
            calorieCard
            SectionHeading(title: "Food diary", trailing: "Add food") { isAddingFood = true }
            foodDiary
            waterCard
        }
        .navigationTitle("Intake")
        .navigationSubtitle("Fuel well. Feel good.")
        .toolbar {
            Button("Add food", systemImage: "plus") { isAddingFood = true }
        }
        .sheet(isPresented: $isAddingFood) { AddFoodSheet(day: day) }
    }

    private var calorieCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 20) {
                Ring(fraction: store.intakeFraction(on: day), size: 96) {
                    Text(store.eatenKcal(on: day).formatted()).font(.title2).fontWeight(.semibold)
                    Text("kcal eaten").font(.caption2).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Daily goal \(store.goalIntakeKcal.formatted()) kcal").font(.caption).foregroundStyle(.secondary)
                    Reading(value: store.remainingKcal(on: day).formatted(), unit: "kcal left", font: .title, unitFont: .caption)
                    NavigationLink { NutritionView() } label: {
                        HStack(spacing: 5) {
                            Text("Nutrition breakdown")
                            Image(systemName: "arrow.up.right")
                        }
                        .font(.caption.weight(.semibold))
                    }
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 15) {
                ForEach(store.macros) { nutrient in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 4) {
                            Text(nutrient.shortName).foregroundStyle(.secondary)
                            Text("\(nutrient.eaten) \(nutrient.unit)").fontWeight(.semibold)
                        }
                        .font(.caption2)
                        Meter(fraction: nutrient.fraction, color: nutrient.color)
                    }
                }
            }
        }
        .card(padding: 18)
    }

    private var foodDiary: some View {
        VStack(spacing: 13) {
            let meals = store.meals(on: day)
            if meals.isEmpty {
                Text(dayOffset == 0 ? "Nothing logged yet today. Tap Add food to start." : "Nothing logged this day.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
            ForEach(Array(meals.enumerated()), id: \.element.id) { i, meal in
                if i > 0 { Divider() }
                HStack(spacing: 10) {
                    Image(systemName: meal.kind.symbol).foregroundStyle(.secondary).frame(width: 20)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            Text(meal.kind.rawValue).font(.footnote.weight(.semibold))
                            Text(meal.time, format: .dateTime.hour().minute()).font(.caption2).foregroundStyle(.secondary)
                        }
                        Text(meal.food).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(meal.kcal)").font(.subheadline.weight(.semibold))
                        Text("kcal").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .contentShape(.rect)
                .contextMenu {
                    Button("Delete", systemImage: "trash", role: .destructive) { store.deleteMeal(meal) }
                }
            }
        }
        .card()
    }

    private var waterCard: some View {
        let litres = { (l: Double) in l.formatted(.number.precision(.fractionLength(0...2))) }

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: "drop").foregroundStyle(Color.sleep)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Water").font(.footnote.weight(.semibold))
                    Text("\(litres(store.waterLitres(on: day))) / \(litres(store.goalWaterLitres)) L · \(store.waterGlasses(on: day)) of \(store.goalWaterGlasses) glasses")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Add a glass", systemImage: "plus") { store.addWaterGlass(on: day) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                    .tint(Color.sleep)
            }
            HStack(spacing: 7) {
                ForEach(0..<store.goalWaterGlasses, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(i < store.waterGlasses(on: day) ? Color.sleep : .card)
                        .frame(height: 16)
                }
            }
            .accessibilityHidden(true)
        }
        .card(.sleep)
    }
}

#Preview {
    NavigationStack { IntakeView() }.environment(HealthStore())
}
