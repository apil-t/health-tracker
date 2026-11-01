import SwiftUI

struct HomeView: View {
    @Environment(HealthStore.self) private var store

    var body: some View {
        Screen {
            HStack {
                Text("\(HealthRules.greeting(hour: Calendar.current.component(.hour, from: .now))), \(store.firstName)")
                    .font(.subheadline)
                Spacer()
                Group {
                    if let lastSync = store.lastSync {
                        Label("Synced \(lastSync, format: .relative(presentation: .named))", systemImage: "checkmark")
                    } else {
                        Label("Sample data", systemImage: "info.circle")
                    }
                }
                .font(.caption2)
            }
            .foregroundStyle(.secondary)

            HStack(spacing: 23) {
                Ring(fraction: store.moveFraction) {
                    Text(Format.percent(store.moveFraction)).font(.title2).fontWeight(.semibold)
                    Text("of daily goal").font(.caption2).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 7) {
                    Text(store.moveFraction >= 1 ? "Goal reached, nice work" : "A little more goes a long way")
                        .font(.caption).fontWeight(.semibold).foregroundStyle(.tint)
                    Reading(value: "\(store.activeKcal)", unit: "/ \(store.goalActiveKcal) kcal", font: .largeTitle, unitFont: .caption)
                    Text("\(store.activeMinutes) active min · \(store.workoutsToday.count) workouts")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .card(.accentColor, padding: 20)

            SectionHeading(title: "Health at a glance", trailing: "Edit") { /* TODO: customise metrics */ }

            HStack(spacing: 12) {
                NavigationLink { HeartRateView() } label: {
                    MetricCard(icon: "heart", color: .heart, title: "Heart rate", value: "\(store.heartRate)", unit: "bpm",
                               footnote: "Latest at \(store.latestHeartRateTime.formatted(date: .omitted, time: .shortened))") {
                        Sparkline(values: Array(store.heartRateToday.suffix(16)), color: .heart)
                    }
                }
                NavigationLink { StressView() } label: {
                    let stress = store.stressEstimate()
                    MetricCard(icon: "camera.macro", color: .lavender, title: "Stress", value: stress.map { "\($0.score)" } ?? "–",
                               unit: "/ 100",
                               footnote: stress.map { HealthRules.stressLabel($0.score) } ?? "Calibrating") {
                        Sparkline(values: store.stressScores(lastDays: 14).compactMap { $0.score.map(Double.init) },
                                  color: .lavender, smooth: true)
                    }
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: 12) {
                NavigationLink { StepsView() } label: {
                    DailyCard(icon: "shoeprints.fill", title: "Steps", value: store.steps.formatted(),
                              fraction: store.stepsFraction, color: .accentColor,
                              footnote: "of \(store.goalSteps.formatted()) steps")
                }
                NavigationLink { SleepView() } label: {
                    DailyCard(icon: "moon", title: "Sleep", value: Format.hoursMinutes(store.sleepMinutes),
                              fraction: store.sleepFraction, color: .sleep,
                              footnote: "\(Format.percent(store.sleepFraction)) of your \(store.goalSleepHours)h goal")
                }
            }
            .buttonStyle(.plain)

            if let workout = store.workoutsToday.first {
                NavigationLink { WorkoutView(workout: workout) } label: {
                    HStack(spacing: 12) {
                        WorkoutIcon(kind: workout.kind)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(workout.name).font(.subheadline).fontWeight(.semibold)
                            Text(workout.summary).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Chevron()
                    }
                    .card()
                }
                .buttonStyle(.plain)
            }
        }
        .refreshable { await store.sync() }
        .navigationTitle("Your daily balance")
        .navigationSubtitle(Format.todayHeading)
        .toolbar {
            Button("Notifications", systemImage: "bell") { /* TODO: notifications */ }
        }
    }
}

private struct MetricCard<Trend: View>: View {
    let icon: String
    let color: Color
    let title: String
    let value: String
    let unit: String
    let footnote: String
    @ViewBuilder var trend: Trend

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon).foregroundStyle(color)
                Spacer()
                Chevron()
            }
            Text(title).font(.footnote).fontWeight(.medium)
            Reading(value: value, unit: unit, font: .title)
            trend.frame(height: 42)
            Text(footnote).font(.caption2).foregroundStyle(.secondary)
        }
        .card()
    }
}

private struct DailyCard: View {
    let icon: String
    let title: String
    let value: String
    let fraction: Double
    let color: Color
    let footnote: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TintedLabel(title: title, systemImage: icon, tint: color).font(.footnote.weight(.medium))
                Spacer()
                Chevron()
            }
            Text(value).font(.title).fontWeight(.semibold)
            Meter(fraction: fraction, color: color)
            Text(footnote).font(.caption2).foregroundStyle(.secondary)
        }
        .card()
    }
}

#Preview {
    NavigationStack { HomeView() }.environment(HealthStore())
}
