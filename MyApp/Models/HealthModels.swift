import Foundation

// Plain data types. Foundation only, no SwiftUI, so they map 1:1 to a Dart/TypeScript model.

struct Workout: Identifiable, Codable {
    enum Kind: String, CaseIterable, Codable {
        case run = "Run", walk = "Walk", mobility = "Mobility", other = "Workout"
    }

    var id = UUID()
    var name: String
    var kind: Kind
    var start: Date
    var minutes: Int
    var kcal: Int
    var indoor = false
    var distanceKm: Double? = nil
    /// bpm, evenly spaced across the workout.
    var heartRate: [Double] = []
    /// Seconds per completed kilometre.
    var splits: [Int] = []
    /// Logged in the app rather than synced from Google Health.
    var isManual = false
}

struct Meal: Identifiable, Codable {
    enum Kind: String, CaseIterable, Codable {
        case breakfast = "Breakfast", lunch = "Lunch", snack = "Snack", dinner = "Dinner"
    }

    var id = UUID()
    var kind: Kind
    var time: Date
    var food: String
    var kcal: Int
}

/// One day's totals. Nil means no data for that day.
struct DaySummary {
    var day: Date
    var steps: Int?
    var activeKcal: Int?
    var activeMinutes: Int?
    var sleepMinutes: Int?
    var bedtime: Date?
    var wakeTime: Date?
    var restingHeartRate: Int?
    /// Overnight HRV (RMSSD), milliseconds.
    var hrvMs: Double?
    /// Average breaths per minute during sleep.
    var breathingRate: Double?
    /// Nightly skin temperature minus the user's baseline, °C.
    var skinTempDeltaC: Double?
}

/// Stress estimated from overnight vitals against the user's own baseline. Not a medical measurement.
struct StressEstimate {
    /// 0–100, higher means more strain. About 30 on a typical day for this user.
    var score: Int
    var factors: [StressFactor]
}

/// One vital's contribution to the stress estimate.
struct StressFactor: Identifiable {
    var name: String
    var today: String
    var usual: String
    /// Standard deviations from usual, signed so positive = adds stress.
    var strain: Double
    var weight: Double

    var id: String { name }
}

/// Time span for the trend charts.
enum TrendPeriod: String, CaseIterable, Identifiable {
    case week = "Week", month = "Month", year = "Year"

    var days: Int {
        switch self {
        case .week: 7
        case .month: 30
        case .year: 365
        }
    }
    var id: Self { self }
}

/// Summary figures for a trend chart.
struct TrendStats: Equatable {
    var average: Int
    var best: Int
    var daysMeetingGoal: Int
    var daysWithData: Int
}

struct Nutrient: Identifiable {
    enum Kind: String {
        case protein, carbs, fat, fiber, sodium
    }

    var kind: Kind
    var eaten: Int
    var goal: Int

    var id: Kind { kind }
}

/// Editable personal details. Values mirror the Google Health profile fields.
struct Profile: Equatable {
    enum Sex: String, CaseIterable, Codable {
        case male = "Male", female = "Female", unspecified = "Prefer not to say"
    }

    var name: String
    var sex: Sex
    var age: Int
    var heightCm: Int
    var weightKg: Double
    var goalWeightKg: Double
}

/// Short title + body text shown in the soft "insight" cards.
struct Insight {
    let title: String
    let message: String
    let isPositive: Bool
}
