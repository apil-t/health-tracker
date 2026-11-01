import SwiftUI
import Charts

struct ProfileView: View {
    @Environment(HealthStore.self) private var store
    @State private var isManagingGoals = false
    @State private var isEditing = false

    var body: some View {
        Screen(spacing: 12) {
            HStack(spacing: 15) {
                Text(store.initials)
                    .font(.title2.weight(.medium)).foregroundStyle(.tint)
                    .frame(width: 62, height: 62)
                    .background(Color.accentColor.opacity(0.12), in: .circle)
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.name).font(.title2.weight(.semibold))
                    Text("Member since \(store.memberSince.formatted(.dateTime.month(.wide).year()))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Edit") { isEditing = true }
                    .font(.caption.weight(.semibold))
            }
            .padding(.vertical, 4)

            VStack(spacing: 16) {
                HStack {
                    Stat(label: "Weight", value: Format.oneDecimal(store.weightKg), unit: "kg")
                    Stat(label: "Height", value: "\(store.heightCm)", unit: "cm")
                    Stat(label: "Age", value: "\(store.age)", unit: "yrs")
                }
                Divider()
                HStack {
                    Text("Sex: \(store.sex.rawValue)")
                    Spacer()
                    Text("BMI: \(Format.oneDecimal(store.bmi)) · \(HealthRules.bmiCategory(store.bmi))")
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            .card(padding: 18)

            weightTrendCard

            SectionHeading(title: "Your daily goals", trailing: "Manage") { isManagingGoals = true }

            VStack(spacing: 13) {
                GoalRow(icon: "flame", title: "Active energy", value: "\(store.goalActiveKcal) kcal")
                Divider()
                GoalRow(icon: "shoeprints.fill", title: "Steps", value: "\(store.goalSteps.formatted()) steps")
                Divider()
                GoalRow(icon: "moon", title: "Sleep", value: "\(store.goalSleepHours) hours")
            }
            .card()

            GoogleHealthCard()
        }
        .navigationTitle("Profile")
        .navigationSubtitle("Your health, in perspective.")
        .toolbar {
            Button("Settings", systemImage: "slider.horizontal.3") { /* TODO: settings */ }
        }
        .navigationDestination(isPresented: $isManagingGoals) { GoalsView() }
        .sheet(isPresented: $isEditing) { EditProfileSheet(profile: store.profile) }
    }

    private var weightTrendCard: some View {
        let weights = store.weightHistory
        let since = store.weightHistoryStart.formatted(.dateTime.day().month())

        return VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("Weight trend").font(.headline)
                Spacer()
                Text("Last 6 weeks").font(.caption2).foregroundStyle(.secondary)
            }
            HStack {
                Text("\(store.weightChange <= 0 ? "↓" : "↑") \(Format.oneDecimal(abs(store.weightChange))) kg since \(since)")
                    .font(.caption).foregroundStyle(.tint)
                Spacer()
                Text("Goal \(store.goalWeightKg.formatted()) kg").font(.caption2).foregroundStyle(.secondary)
            }
            Chart(weights.indices, id: \.self) { i in
                LineMark(x: .value("Weigh-in", i), y: .value("kg", weights[i]))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }
            .foregroundStyle(Color.accentColor)
            .chartXAxis(.hidden)
            .chartYAxis { AxisMarks(values: .automatic(desiredCount: 3)) { _ in AxisGridLine() } }
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 87)
            HStack {
                Text("\(since) · \(Format.oneDecimal(weights.first ?? 0)) kg")
                Spacer()
                Text("\(Date.now.formatted(.dateTime.day().month())) · \(Format.oneDecimal(store.weightKg)) kg")
            }
            .font(.caption2).foregroundStyle(.secondary)
        }
        .card(padding: 18)
    }
}

private struct GoalRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        NavigationLink { GoalsView() } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).foregroundStyle(.tint).frame(width: 20)
                Text(title).font(.footnote)
                Spacer()
                Text(value).font(.caption).foregroundStyle(.secondary)
                Chevron()
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack { ProfileView() }.environment(HealthStore())
}
