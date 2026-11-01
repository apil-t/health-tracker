import Foundation

// All health calculations and copy rules live here, UI-free (Foundation only).
// Views just display these values, so porting = re-implement this file + redraw the screens.

// MARK: Rules

nonisolated enum HealthRules {
    static let ageRange = 13...120
    static let heightRangeCm = 100...250
    static let weightRangeKg = 30.0...300.0

    /// Field-by-field problems with a profile; empty means it can be saved.
    static func profileErrors(_ profile: Profile) -> [String] {
        var errors: [String] = []
        if profile.name.trimmingCharacters(in: .whitespaces).isEmpty { errors.append("Enter your name.") }
        if !ageRange.contains(profile.age) { errors.append("Age must be \(ageRange.lowerBound)–\(ageRange.upperBound).") }
        if !heightRangeCm.contains(profile.heightCm) {
            errors.append("Height must be \(heightRangeCm.lowerBound)–\(heightRangeCm.upperBound) cm.")
        }
        if !weightRangeKg.contains(profile.weightKg) || !weightRangeKg.contains(profile.goalWeightKg) {
            errors.append("Weight must be \(Int(weightRangeKg.lowerBound))–\(Int(weightRangeKg.upperBound)) kg.")
        }
        return errors
    }

    /// Average and best over days that have data; days meeting `goal` (higher is better).
    static func trendStats(_ values: [Int?], goal: Int) -> TrendStats {
        let present = values.compactMap { $0 }
        return TrendStats(
            average: present.isEmpty ? 0 : present.reduce(0, +) / present.count,
            best: present.max() ?? 0,
            daysMeetingGoal: present.filter { $0 >= goal }.count,
            daysWithData: present.count
        )
    }

    // MARK: Stress estimate

    /// Nights of history a signal needs before it counts.
    static let stressBaselineNights = 7

    /// Stress from overnight vitals against the user's own previous nights (Google Health has no stress data type).
    /// Each signal becomes "standard deviations from usual, in the stressful direction", clamped to ±2.5,
    /// weighted, then mapped so a usual day scores about 30. Needs at least two signals with a baseline.
    // ponytail: heuristic weights (HRV-led, as in published HRV/stress research), not a validated model. Tune with feedback.
    static func stress(today: DaySummary, baseline: [DaySummary]) -> StressEstimate? {
        struct Signal {
            let name: String
            let weight: Double
            /// Floor for the spread, so a very steady baseline doesn't turn tiny changes into big swings.
            let minSpread: Double
            /// +1: higher than usual adds stress. -1: lower than usual adds stress.
            let direction: Double
            var onlyRaises = false
            let value: (DaySummary) -> Double?
            let format: (Double) -> String
        }
        let signals = [
            Signal(name: "HRV", weight: 0.35, minSpread: 3, direction: -1, value: \.hrvMs) { "\(Int($0.rounded())) ms" },
            Signal(name: "Resting heart rate", weight: 0.25, minSpread: 1.5, direction: 1,
                   value: { $0.restingHeartRate.map(Double.init) }) { "\(Int($0.rounded())) bpm" },
            Signal(name: "Sleep", weight: 0.2, minSpread: 30, direction: -1,
                   value: { $0.sleepMinutes.flatMap { $0 > 0 ? Double($0) : nil } }) { Format.hoursMinutes(Int($0.rounded())) },
            Signal(name: "Breathing rate", weight: 0.1, minSpread: 0.3, direction: 1,
                   value: \.breathingRate) { $0.formatted(.number.precision(.fractionLength(1))) + " /min" },
            Signal(name: "Skin temperature", weight: 0.1, minSpread: 0.15, direction: 1, onlyRaises: true,
                   value: \.skinTempDeltaC) { ($0 >= 0 ? "+" : "") + $0.formatted(.number.precision(.fractionLength(1))) + " °C" },
        ]

        var factors: [StressFactor] = []
        for signal in signals {
            guard let now = signal.value(today) else { continue }
            let past = baseline.compactMap(signal.value)
            guard past.count >= stressBaselineNights else { continue }
            let mean = past.reduce(0, +) / Double(past.count)
            let spread = max((past.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(past.count)).squareRoot(), signal.minSpread)
            var strain = min(max(signal.direction * (now - mean) / spread, -2.5), 2.5)
            if signal.onlyRaises { strain = max(strain, 0) }
            factors.append(StressFactor(name: signal.name, today: signal.format(now), usual: signal.format(mean),
                                        strain: strain, weight: signal.weight))
        }
        guard factors.count >= 2 else { return nil }

        let combined = factors.map { $0.strain * $0.weight }.reduce(0, +) / factors.map(\.weight).reduce(0, +)
        return StressEstimate(score: Int(min(max(30 + 20 * combined, 0), 100).rounded()),
                              factors: factors.sorted { $0.strain * $0.weight > $1.strain * $1.weight })
    }

    static let stressExplanation = """
        Estimated from your overnight HRV, resting heart rate, sleep, breathing rate and skin temperature, \
        compared with your previous 30 days. It isn’t a medical measurement: illness, alcohol, caffeine and \
        hard training move these numbers too.
        """

    static func strainLabel(_ strain: Double) -> String {
        strain >= 0.5 ? "Adds stress" : strain <= -0.5 ? "Easing" : "Usual"
    }

    static func stressSummary(_ estimate: StressEstimate) -> String {
        guard let top = estimate.factors.first, top.strain >= 0.5 else {
            return "Your vitals are at or better than your usual. Your body looks well recovered."
        }
        return "\(top.name) is the biggest push today: \(top.today) against your usual \(top.usual)."
    }

    /// "1,754 steps to go" or "Goal reached".
    static func toGo(_ remaining: Int, unit: String) -> String {
        remaining > 0 ? "\(remaining.formatted()) \(unit) to go" : "Goal reached"
    }

    static func greeting(hour: Int) -> String {
        switch hour {
        case ..<12: "Good morning"
        case ..<18: "Good afternoon"
        default: "Good evening"
        }
    }

    static func stressLabel(_ score: Int) -> String {
        switch score {
        case ..<33: "Low · feeling balanced"
        case ..<66: "Moderate"
        default: "High"
        }
    }

    static func bmiCategory(_ bmi: Double) -> String {
        switch bmi {
        case ..<18.5: "Underweight"
        case ..<25: "Healthy range"
        case ..<30: "Overweight"
        default: "Obese"
        }
    }

    static func isAtRest(bpm: Int, resting: Int) -> Bool { bpm <= resting + 15 }

    static func restingInsight(resting: Int, average30Day: Int) -> Insight {
        let diff = average30Day - resting
        return Insight(
            title: diff >= 0 ? "A steady resting rhythm" : "Resting rate is up",
            message: "Your resting heart rate is \(abs(diff)) bpm \(diff >= 0 ? "lower" : "higher") than your 30-day average of \(average30Day) bpm.",
            isPositive: diff >= 0
        )
    }

    static func fiberInsight(_ fiber: Nutrient) -> Insight {
        let gap = fiber.goal - fiber.eaten
        return gap > 0
            ? Insight(title: "A little more fiber",
                      message: "You’re \(gap) g from your fiber goal. Try berries, lentils or a slice of wholegrain toast.",
                      isPositive: false)
            : Insight(title: "Fiber goal reached", message: "Nice work, you’ve hit your fiber goal for today.", isPositive: true)
    }
}

// MARK: Derived values

extension HealthStore {
    var firstName: String { String(name.split(separator: " ").first ?? "") }
    var initials: String { name.split(separator: " ").compactMap(\.first).map(String.init).joined() }

    // MARK: Per day. Logs and history cover many days; screens pick one.

    func workouts(on day: Date) -> [Workout] { workouts.filter { Calendar.current.isDate($0.start, inSameDayAs: day) } }
    func meals(on day: Date) -> [Meal] { meals.filter { Calendar.current.isDate($0.time, inSameDayAs: day) }.sorted { $0.time < $1.time } }
    func waterGlasses(on day: Date) -> Int { waterLog[day.dayKey] ?? 0 }

    private func storedSummary(on day: Date) -> DaySummary? {
        history.last { Calendar.current.isDate($0.day, inSameDayAs: day) }
    }

    /// Recorded day total (or the sum of synced workouts) plus anything logged manually in the app.
    func activeKcal(on day: Date) -> Int {
        let dayWorkouts = workouts(on: day)
        let recorded = Calendar.current.isDateInToday(day) ? syncedActiveKcal : storedSummary(on: day)?.activeKcal
        return (recorded ?? dayWorkouts.filter { !$0.isManual }.map(\.kcal).reduce(0, +))
            + dayWorkouts.filter(\.isManual).map(\.kcal).reduce(0, +)
    }

    func activeMinutes(on day: Date) -> Int {
        let dayWorkouts = workouts(on: day)
        let recorded = Calendar.current.isDateInToday(day) ? syncedActiveMinutes : storedSummary(on: day)?.activeMinutes
        return (recorded ?? dayWorkouts.filter { !$0.isManual }.map(\.minutes).reduce(0, +))
            + dayWorkouts.filter(\.isManual).map(\.minutes).reduce(0, +)
    }

    /// History for one day; today uses the live values shown on Home.
    func summary(on day: Date) -> DaySummary {
        var summary = storedSummary(on: day) ?? DaySummary(day: Calendar.current.startOfDay(for: day))
        if Calendar.current.isDateInToday(day) {
            summary.steps = steps
            summary.sleepMinutes = sleepMinutes
            summary.restingHeartRate = restingHeartRate
        }
        summary.activeKcal = activeKcal(on: day)
        summary.activeMinutes = activeMinutes(on: day)
        return summary
    }

    /// The last `count` days, oldest first, ending today.
    func summaries(lastDays count: Int) -> [DaySummary] {
        let today = Calendar.current.startOfDay(for: .now)
        return (0..<count).reversed().map { summary(on: Calendar.current.date(byAdding: .day, value: -$0, to: today)!) }
    }

    /// Monday–Sunday of the week containing `day`; days after today have no values.
    func summaries(weekOf day: Date) -> [DaySummary] {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        let monday = calendar.dateInterval(of: .weekOfYear, for: day)?.start ?? calendar.startOfDay(for: day)
        return (0..<7).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: monday)!
            return date > .now ? DaySummary(day: date) : summary(on: date)
        }
    }

    // MARK: Stress

    /// Stress for `day`, against the 30 days before it. Nil while there isn't enough history.
    func stressEstimate(on day: Date = .now) -> StressEstimate? {
        let start = Calendar.current.startOfDay(for: day)
        let from = Calendar.current.date(byAdding: .day, value: -30, to: start)!
        return HealthRules.stress(today: summary(on: day), baseline: history.filter { $0.day < start && $0.day >= from })
    }

    func stressScores(lastDays count: Int) -> [(day: Date, score: Int?)] {
        summaries(lastDays: count).map { ($0.day, stressEstimate(on: $0.day)?.score) }
    }

    /// Nights with HRV in the last 30 days, for the "calibrating" message.
    var stressCalibrationNights: Int { history.suffix(31).filter { $0.hrvMs != nil }.count }

    // MARK: Today

    var workoutsToday: [Workout] { workouts(on: .now) }
    var activeKcal: Int { activeKcal(on: .now) }
    var activeMinutes: Int { activeMinutes(on: .now) }
    var moveFraction: Double { Double(activeKcal) / Double(goalActiveKcal) }
    var stepsFraction: Double { Double(steps) / Double(goalSteps) }
    var sleepFraction: Double { Double(sleepMinutes) / Double(goalSleepHours * 60) }

    var heartRate: Int { Int(heartRateToday.last ?? 0) }
    var latestHeartRateTime: Date { .today(0, (heartRateToday.count - 1) * 30) }
    var heartRateLowest: Int { Int(heartRateToday.min() ?? 0) }
    var heartRateHighest: Int { Int(heartRateToday.max() ?? 0) }
    var heartRateAverage: Int { average(heartRateToday) }
    /// Hour of day (0–24) for each reading in `heartRateToday`.
    func heartRateHour(at index: Int) -> Double { Double(index) / 2 }

    func eatenKcal(on day: Date = .now) -> Int { meals(on: day).map(\.kcal).reduce(0, +) }
    func remainingKcal(on day: Date = .now) -> Int { max(goalIntakeKcal - eatenKcal(on: day), 0) }
    func intakeFraction(on day: Date = .now) -> Double { Double(eatenKcal(on: day)) / Double(goalIntakeKcal) }

    static let litresPerGlass = 0.25
    func waterLitres(on day: Date = .now) -> Double { Double(waterGlasses(on: day)) * Self.litresPerGlass }
    var goalWaterLitres: Double { Double(goalWaterGlasses) * Self.litresPerGlass }

    var weightKg: Double { weightHistory.last ?? 0 }
    var weightChange: Double { (weightHistory.last ?? 0) - (weightHistory.first ?? 0) }
    var bmi: Double { weightKg / pow(Double(heightCm) / 100, 2) }
}

extension Workout {
    var end: Date { start.addingTimeInterval(Double(minutes) * 60) }
    var paceSeconds: Int? { distanceKm.map { Int((Double(minutes * 60) / $0).rounded()) } }
    var averageHeartRate: Int { average(heartRate) }
    var maxHeartRate: Int { Int(heartRate.max() ?? 0) }
    /// Minute into the workout for each `heartRate` sample.
    func heartRateMinute(at index: Int) -> Double { Double(index) * Double(minutes) / Double(max(heartRate.count - 1, 1)) }

    /// The partial kilometre after the last full split, if any.
    var finalSplit: (km: Double, seconds: Int, pace: Int)? {
        guard let distanceKm, !splits.isEmpty else { return nil }
        let km = distanceKm - Double(splits.count)
        let seconds = minutes * 60 - splits.reduce(0, +)
        return km > 0 ? (km, seconds, Int((Double(seconds) / km).rounded())) : nil
    }

    var summary: String {
        [distanceKm.map { "\($0.formatted()) km" }, "\(minutes) min", "\(kcal) kcal"].compactMap { $0 }.joined(separator: " · ")
    }
    var timeRange: String { (start..<end).formatted(.interval.hour().minute()) }
    var setting: String { indoor ? "Indoor" : "Outdoor" }
}

extension Nutrient {
    var name: String {
        switch kind {
        case .protein: "Protein"
        case .carbs: "Carbohydrates"
        case .fat: "Fat"
        case .fiber: "Dietary fiber"
        case .sodium: "Sodium"
        }
    }
    var shortName: String { kind == .carbs ? "Carbs" : name }
    var unit: String { kind == .sodium ? "mg" : "g" }
    var fraction: Double { Double(eaten) / Double(goal) }
}

private func average(_ values: [Double]) -> Int {
    values.isEmpty ? 0 : Int(values.reduce(0, +) / Double(values.count))
}

// MARK: Formatting

nonisolated enum Format {
    /// 0.83 → "83%"
    static func percent(_ fraction: Double) -> String { fraction.formatted(.percent.precision(.fractionLength(0))) }
    /// 72.44 → "72.4"
    static func oneDecimal(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(1))) }
    /// 375 → "6:15" (pace per km or a duration)
    static func minutesSeconds(_ seconds: Int) -> String { Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond)) }
    /// 462 → "7h 42m"
    static func hoursMinutes(_ minutes: Int) -> String {
        Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .narrow))
    }
    /// "THURSDAY, 29 OCTOBER"
    static var todayHeading: String { Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)).uppercased() }
}

extension Date {
    /// "2026-10-30" in the local calendar: the key for per-day logs.
    var dayKey: String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: self)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    /// `day`'s date at the current time of day, for entries logged on a past day.
    static func now(on day: Date) -> Date {
        let calendar = Calendar.current
        return calendar.date(byAdding: calendar.dateComponents([.hour, .minute], from: calendar.startOfDay(for: .now), to: .now),
                             to: calendar.startOfDay(for: day))!
    }

    static func today(_ hour: Int, _ minute: Int) -> Date {
        Calendar.current.startOfDay(for: .now).addingTimeInterval(Double(hour * 3600 + minute * 60))
    }

    var hourOfDay: Double { timeIntervalSince(Calendar.current.startOfDay(for: self)) / 3600 }
}
