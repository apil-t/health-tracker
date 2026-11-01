import Foundation
import Observation

/// App state. Screens read from it and call its methods; they never mutate data directly.
/// What the user enters is saved on the device (see `SavedData`). Everything else starts as sample
/// data until `sync()` replaces it with Google Health values.
// ponytail: synced data isn't cached, so offline launches show sample values. Cache the last snapshot if that matters.
@Observable final class HealthStore {
    @ObservationIgnored private let api = GoogleHealthClient()
    @ObservationIgnored private let storageURL: URL?
    private(set) var isConnected: Bool
    private(set) var isSyncing = false
    private(set) var syncError: String?

    /// Pass `nil` to keep everything in memory (previews, checks).
    init(storageURL: URL? = LocalStorage.defaultURL) {
        self.storageURL = storageURL
        isConnected = api.auth.isSignedIn
        if let storageURL, let saved = LocalStorage.load(from: storageURL) { restore(saved) }
    }

    var name = "Apil"
    var memberSince = Calendar.current.date(from: DateComponents(year: 2026, month: 3))!
    var deviceName = "Fitbit"
    var lastSync: Date? = nil
    /// Today's totals from Google Health. Nil = derive them from `workouts`.
    var syncedActiveKcal: Int?
    var syncedActiveMinutes: Int?

    var steps = 8_246
    var sleepMinutes = 462
    var restingHeartRate = 58
    var restingHeartRate30Day = 61
    /// One reading every 30 minutes since midnight.
    var heartRateToday: [Double] = [
        60, 57, 62, 52, 56, 54, 58, 57, 55, 60, 64, 72,
        80, 95, 164, 118, 90, 78,
        72, 80, 74, 82, 76, 88, 70, 66,
        95, 88, 80, 70, 76, 66, 72, 70,
        78, 86, 74, 92, 84, 76, 72, 68,
    ]
    /// Active kcal for each earlier day this week, starting Monday.
    /// One summary per day, oldest first, ending today (sample until the first sync).
    var history = HealthStore.sampleHistory()

    var workouts = [
        Workout(name: "Morning run", kind: .run, start: .today(7, 0), minutes: 32, kcal: 324, distanceKm: 5.12,
                heartRate: [95, 105, 115, 122, 128, 132, 136, 134, 140, 138, 146, 142, 148, 144, 150, 146, 152,
                            150, 156, 152, 158, 154, 160, 156, 164, 158, 160, 156, 150, 138, 126, 114, 104],
                splits: [388, 378, 371, 368, 370]),
        Workout(name: "Lunch walk", kind: .walk, start: .today(12, 30), minutes: 28, kcal: 108),
        Workout(name: "Evening mobility", kind: .mobility, start: .today(18, 0), minutes: 16, kcal: 110, indoor: true),
    ]

    var meals = [
        Meal(kind: .breakfast, time: .today(8, 15), food: "Oats, yogurt & blueberries", kcal: 420),
        Meal(kind: .lunch, time: .today(13, 15), food: "Chicken & quinoa bowl", kcal: 610),
        Meal(kind: .snack, time: .today(16, 0), food: "Apple & almonds", kcal: 210),
        Meal(kind: .dinner, time: .today(19, 0), food: "Salmon & roasted vegetables", kcal: 400),
    ]
    var macros = [
        Nutrient(kind: .protein, eaten: 104, goal: 140),
        Nutrient(kind: .carbs, eaten: 180, goal: 245),
        Nutrient(kind: .fat, eaten: 56, goal: 73),
    ]
    var fiber = Nutrient(kind: .fiber, eaten: 23, goal: 30)
    var sodium = Nutrient(kind: .sodium, eaten: 1_480, goal: 2_300)
    /// Glasses of water per day, keyed by `Date.dayKey` ("2026-10-30").
    var waterLog = [Date.now.dayKey: 7]

    var heightCm = 178
    var age = 29
    var sex = Profile.Sex.male
    /// Weigh-ins over the last 6 weeks, oldest first.
    var weightHistory = [74.2, 74.1, 73.8, 73.9, 73.6, 73.5, 73.1, 73.2, 72.9, 72.8, 72.7, 72.5, 72.4]
    var weightHistoryStart = Calendar.current.date(byAdding: .day, value: -42, to: .now)!

    var goalActiveKcal = 650
    var goalSteps = 10_000
    var goalSleepHours = 8
    var goalIntakeKcal = 2_200
    var goalWaterGlasses = 10
    var goalWeightKg = 70.0

    // MARK: Actions

    func addWaterGlass(on day: Date = .now) {
        waterLog[day.dayKey, default: 0] += 1
        save()
    }

    func logWorkout(kind: Workout.Kind, minutes: Int, kcal: Int) {
        workouts.append(Workout(name: kind.rawValue, kind: kind, start: .now.addingTimeInterval(Double(-minutes * 60)),
                                minutes: minutes, kcal: kcal, indoor: kind == .mobility, isManual: true))
        save()
    }

    func addMeal(kind: Meal.Kind, food: String, kcal: Int, on day: Date = .now) {
        meals.append(Meal(kind: kind, time: .now(on: day), food: food, kcal: kcal))
        save()
    }

    func deleteMeal(_ meal: Meal) {
        meals.removeAll { $0.id == meal.id }
        save()
    }

    var profile: Profile {
        Profile(name: name, sex: sex, age: age, heightCm: heightCm,
                weightKg: weightHistory.last ?? 0, goalWeightKg: goalWeightKg)
    }

    /// A changed weight is recorded as today's weigh-in so the trend chart picks it up.
    func updateProfile(_ profile: Profile) {
        name = profile.name.trimmingCharacters(in: .whitespaces)
        sex = profile.sex
        age = profile.age
        heightCm = profile.heightCm
        goalWeightKg = profile.goalWeightKg
        if profile.weightKg != weightHistory.last { weightHistory.append(profile.weightKg) }
        save()
        // TODO: write back to Google Health (profile.writeonly / health_metrics_and_measurements scopes).
    }

    // MARK: Saving

    /// Writes the user's entries to disk. Actions call this; screens that bind directly (goals) call it on exit.
    func save() {
        guard let storageURL else { return }
        LocalStorage.save(SavedData(
            name: name, sex: sex, age: age, heightCm: heightCm,
            weightHistory: weightHistory, weightHistoryStart: weightHistoryStart,
            goalActiveKcal: goalActiveKcal, goalSteps: goalSteps, goalSleepHours: goalSleepHours,
            goalIntakeKcal: goalIntakeKcal, goalWaterGlasses: goalWaterGlasses, goalWeightKg: goalWeightKg,
            meals: meals, manualWorkouts: workouts.filter(\.isManual),
            waterLog: waterLog
        ), to: storageURL)
    }

    private func restore(_ saved: SavedData) {
        name = saved.name
        sex = saved.sex
        age = saved.age
        heightCm = saved.heightCm
        weightHistory = saved.weightHistory
        weightHistoryStart = saved.weightHistoryStart
        goalActiveKcal = saved.goalActiveKcal
        goalSteps = saved.goalSteps
        goalSleepHours = saved.goalSleepHours
        goalIntakeKcal = saved.goalIntakeKcal
        goalWaterGlasses = saved.goalWaterGlasses
        goalWeightKg = saved.goalWeightKg
        meals = saved.meals
        workouts = workouts.filter { !$0.isManual } + saved.manualWorkouts
        waterLog = saved.waterLog ?? [:]
    }

    // MARK: Google Health

    /// URL for the Google consent screen; open it in a web authentication session.
    func beginSignIn() -> URL { api.auth.beginSignIn() }

    func completeSignIn(callbackURL: URL) async {
        do {
            try await api.auth.completeSignIn(callbackURL: callbackURL)
            isConnected = true
            await sync()
        } catch {
            syncError = error.localizedDescription
        }
    }

    func sync() async {
        guard isConnected, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let snapshot = try await api.fetchSnapshot()
            apply(snapshot)
            lastSync = .now
            syncError = snapshot.problems.isEmpty ? nil : "Couldn’t load:\n" + snapshot.problems.joined(separator: "\n")
            #if DEBUG
            let days = snapshot.history ?? []
            func coverage(_ name: String, _ value: (DaySummary) -> Int?) -> String {
                let present = days.filter { value($0) != nil }
                return "\(name)=\(present.count)d from \(present.first?.day.dayKey ?? "-")"
            }
            print("[Sync] ok", coverage("steps", \.steps), coverage("energy", \.activeKcal), coverage("minutes", \.activeMinutes),
                  coverage("sleep", \.sleepMinutes), coverage("resting", \.restingHeartRate),
                  coverage("hrv", { $0.hrvMs.map(Int.init) }), coverage("breathing", { $0.breathingRate.map(Int.init) }),
                  coverage("temp", { $0.skinTempDeltaC.map { Int($0 * 10) } }),
                  "workouts=\(snapshot.workouts?.count ?? 0) problems=\(snapshot.problems)")
            #endif
        } catch {
            syncError = error.localizedDescription
            isConnected = api.auth.isSignedIn
        }
    }

    func disconnect() {
        api.auth.signOut()
        isConnected = false
        syncError = nil
    }

    /// Merges synced values; anything the snapshot lacks keeps its current value. Manually logged workouts are kept.
    func apply(_ snapshot: HealthSnapshot) {
        if let value = snapshot.steps { steps = value }
        if let value = snapshot.activeKcal { syncedActiveKcal = value }
        if let value = snapshot.activeMinutes { syncedActiveMinutes = value }
        if let value = snapshot.history, !value.isEmpty { history = value }
        if let value = snapshot.heartRate, !value.isEmpty { heartRateToday = value }
        if let value = snapshot.restingHeartRate { restingHeartRate = value }
        if let value = snapshot.restingHeartRate30Day { restingHeartRate30Day = value }
        if let value = snapshot.sleepMinutes { sleepMinutes = value }
        if let value = snapshot.workouts { workouts = value + workouts.filter(\.isManual) }
        if let weights = snapshot.weights, !weights.kg.isEmpty {
            weightHistory = weights.kg
            weightHistoryStart = weights.start
        }
        if let value = snapshot.heightCm { heightCm = value }
        if let value = snapshot.age { age = value }
        if let value = snapshot.memberSince { memberSince = value }
    }

    /// A year of plausible, deterministic values for the trend screens before the first sync.
    static func sampleHistory(endingOn today: Date = .now) -> [DaySummary] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: today)
        return (0..<365).map { i in
            let day = calendar.date(byAdding: .day, value: i - 364, to: start)!
            let bedtime = calendar.date(byAdding: .minute, value: -90 - (i * 17) % 60, to: day)!
            let sleep = 400 + (i * 37) % 110
            return DaySummary(day: day, steps: 5_500 + (i * 2_731) % 7_000, activeKcal: 380 + (i * 97) % 380,
                              activeMinutes: 35 + (i * 13) % 55, sleepMinutes: sleep, bedtime: bedtime,
                              wakeTime: bedtime.addingTimeInterval(Double(sleep + 25) * 60),
                              restingHeartRate: 56 + (i * 7) % 6, hrvMs: Double(38 + (i * 11) % 18),
                              breathingRate: 14 + Double((i * 3) % 10) / 10, skinTempDeltaC: Double((i * 5) % 7 - 3) / 10)
        }
    }
}
