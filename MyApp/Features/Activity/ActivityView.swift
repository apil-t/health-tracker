import SwiftUI

struct ActivityView: View {
    @Environment(HealthStore.self) private var store
    @State private var dayOffset = 0
    @State private var isLogging = false

    private var day: Date { Calendar.current.date(byAdding: .day, value: dayOffset, to: .now)! }

    var body: some View {
        let workouts = store.workouts(on: day)

        Screen {
            DateSelector(dayOffset: $dayOffset)

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Stat(label: "Active energy", value: "\(store.activeKcal(on: day))", unit: "kcal")
                    Stat(label: "Exercise time", value: "\(store.activeMinutes(on: day))", unit: "min")
                }
                Divider()
                HStack {
                    Text(dayOffset > -7 && Calendar.current.isDate(day, equalTo: .now, toGranularity: .weekOfYear) ? "This week" : "That week")
                        .font(.caption.weight(.medium))
                    Spacer()
                    Text("Goal \(store.goalActiveKcal) kcal / day").font(.caption2).foregroundStyle(.secondary)
                }
                WeekChart(days: store.summaries(weekOf: day), selected: day, goal: store.goalActiveKcal)
            }
            .card(padding: 20)

            SectionHeading(title: dayOffset == 0 ? "Today’s workouts" : "Workouts",
                           trailing: workouts.count == 1 ? "1 activity" : "\(workouts.count) activities")

            if workouts.isEmpty {
                Text("No workouts recorded.").font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).card()
            }
            ForEach(workouts) { workout in
                NavigationLink { WorkoutView(workout: workout) } label: { WorkoutRow(workout: workout) }
                    .buttonStyle(.plain)
            }

            TintedLabel(title: "All activities synced from \(store.deviceName)", systemImage: "watch.analog", tint: .secondary)
                .font(.caption2).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
        .navigationTitle("Activity")
        .navigationSubtitle("Every move adds up.")
        .toolbar {
            Button("Log workout", systemImage: "plus") { isLogging = true }
        }
        .sheet(isPresented: $isLogging) { LogWorkoutSheet() }
    }
}

/// Mon–Sun active-energy bars; the selected day is highlighted.
private struct WeekChart: View {
    let days: [DaySummary]
    let selected: Date
    let goal: Int

    var body: some View {
        HStack(alignment: .bottom, spacing: 19) {
            ForEach(days, id: \.day) { day in
                let isSelected = Calendar.current.isDate(day.day, inSameDayAs: selected)
                VStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color(.tertiarySystemFill))
                        .frame(width: 23, height: 76)
                        .overlay(alignment: .bottom) {
                            if let kcal = day.activeKcal {
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(isSelected ? Color.accentColor : Color.accentColor.opacity(0.3))
                                    .frame(height: 76 * min(Double(kcal) / Double(goal), 1))
                            }
                        }
                    Text(day.day, format: .dateTime.weekday(.narrow))
                        .font(.caption2).fontWeight(isSelected ? .semibold : .regular)
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(day.day.formatted(.dateTime.weekday(.wide))), \(day.activeKcal.map { "\($0) kcal" } ?? "no data")")
            }
        }
    }
}

private struct WorkoutRow: View {
    let workout: Workout

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                WorkoutIcon(kind: workout.kind)
                VStack(alignment: .leading, spacing: 4) {
                    Text(workout.name).font(.subheadline).fontWeight(.semibold)
                    Text("\(workout.timeRange) · \(workout.setting)").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Chevron()
            }
            HStack(spacing: 22) {
                TintedLabel(title: "\(workout.kcal) kcal", systemImage: "flame", tint: .secondary)
                TintedLabel(title: "\(workout.minutes) min", systemImage: "clock", tint: .secondary)
            }
            .font(.caption)
        }
        .card()
    }
}

#Preview {
    NavigationStack { ActivityView() }.environment(HealthStore())
}
