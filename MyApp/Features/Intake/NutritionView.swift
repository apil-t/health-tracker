import SwiftUI

struct NutritionView: View {
    @Environment(HealthStore.self) private var store

    var body: some View {
        let meals = store.meals(on: .now)
        let biggest = meals.map(\.kcal).max() ?? 1

        Screen(spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Stat(label: "Energy eaten", value: store.eatenKcal().formatted(), unit: "kcal")
                    Stat(label: "Remaining", value: store.remainingKcal().formatted(), unit: "kcal")
                }
                Meter(fraction: store.intakeFraction())
                HStack {
                    Text("\(Format.percent(store.intakeFraction())) of daily goal")
                    Spacer()
                    Text("\(store.goalIntakeKcal.formatted()) kcal")
                }
                .font(.caption2).foregroundStyle(.secondary)
                Divider()
                HStack(alignment: .bottom, spacing: 7) {
                    ForEach(meals) { meal in
                        VStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(meal.kcal == biggest ? Color.accentColor : Color.accentColor.opacity(0.3))
                                .frame(width: 32, height: 56 * Double(meal.kcal) / Double(biggest))
                            Text("\(meal.kcal)").font(.caption2.weight(.medium))
                            Text(meal.kind.rawValue).font(.caption2).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .card()

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Macronutrients").font(.headline)
                    Spacer()
                    Text("Eaten / goal").font(.caption2).foregroundStyle(.secondary)
                }
                ForEach(store.macros) { nutrient in
                    VStack(spacing: 7) {
                        HStack {
                            Label {
                                Text(nutrient.name)
                            } icon: {
                                Circle().fill(nutrient.color).frame(width: 7, height: 7)
                            }
                            .font(.caption)
                            Spacer()
                            Text("\(nutrient.eaten) / \(nutrient.goal) \(nutrient.unit)").font(.caption2).foregroundStyle(.secondary)
                        }
                        Meter(fraction: nutrient.fraction, color: nutrient.color)
                    }
                }
            }
            .card()

            VStack(alignment: .leading, spacing: 10) {
                Text("Beyond calories").font(.headline)
                ForEach(Array([store.fiber, store.sodium].enumerated()), id: \.element.id) { i, nutrient in
                    if i > 0 { Divider() }
                    HStack {
                        Text(nutrient.name)
                        Spacer()
                        Text("\(nutrient.eaten.formatted()) / \(nutrient.goal.formatted()) \(nutrient.unit)").foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            }
            .card()

            InsightCard(insight: HealthRules.fiberInsight(store.fiber), systemImage: "leaf")
        }
        .navigationTitle("Daily nutrition")
        .navigationSubtitle(Format.todayHeading)
    }
}

#Preview {
    NavigationStack { NutritionView() }.environment(HealthStore())
}
