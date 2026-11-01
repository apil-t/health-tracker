import Foundation

// Response shapes for the Google Health API v4, field names as in the reference docs
// (developers.google.com/health/reference/rest/v4). int64 values arrive as JSON strings.

nonisolated struct DataPointList<Point: Decodable>: Decodable {
    var dataPoints: [Point]?
    var nextPageToken: String?
}

nonisolated struct RollupResponse: Decodable {
    var rollupDataPoints: [RollupPoint]?
}

nonisolated struct APIInterval: Decodable {
    let startTime: Date
    let endTime: Date
}

nonisolated struct CivilDate: Codable, Hashable {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The local calendar day of `date`.
    init(_ date: Date) {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year!, month: c.month!, day: c.day!)
    }

    /// "2026-10-30": the civil-date literal used in filters such as `exercise.interval.civil_start_time`.
    var isoString: String { String(format: "%04d-%02d-%02d", year, month, day) }
}

nonisolated struct CivilDateTime: Codable {
    /// Google omits zero fields, so midnight arrives as `"time": {}`.
    struct Time: Codable {
        var hours: Int?, minutes: Int?, seconds: Int?, nanos: Int?
    }

    let date: CivilDate
    var time: Time? = Time()
}

nonisolated struct SleepPoint: Decodable {
    struct Sleep: Decodable {
        struct Metadata: Decodable { let main: Bool? }
        struct Summary: Decodable { let minutesAsleep: String? }
        let interval: APIInterval
        let metadata: Metadata?
        let summary: Summary?
    }
    let sleep: Sleep
}

nonisolated struct ExercisePoint: Decodable {
    struct Exercise: Decodable {
        struct Metrics: Decodable {
            let caloriesKcal: Double?
            let distanceMillimeters: Double?
        }
        let interval: APIInterval
        let exerciseType: String?
        let displayName: String?
        let metricsSummary: Metrics?
    }
    let exercise: Exercise
}

nonisolated struct WeightPoint: Decodable {
    struct Weight: Decodable {
        struct SampleTime: Decodable { let physicalTime: Date }
        let sampleTime: SampleTime
        let weightGrams: Double
    }
    let weight: Weight
}

nonisolated struct HeightPoint: Decodable {
    struct Height: Decodable { let heightMillimeters: String }
    let height: Height
}

nonisolated struct RestingHeartRatePoint: Decodable {
    struct Value: Decodable {
        let date: CivilDate?
        let beatsPerMinute: String
    }
    let dailyRestingHeartRate: Value
}

nonisolated struct DailyHRVPoint: Decodable {
    struct Value: Decodable {
        let date: CivilDate?
        let averageHeartRateVariabilityMilliseconds: Double?
    }
    let dailyHeartRateVariability: Value
}

nonisolated struct DailyRespiratoryRatePoint: Decodable {
    struct Value: Decodable {
        let date: CivilDate?
        let breathsPerMinute: Double
    }
    let dailyRespiratoryRate: Value
}

nonisolated struct SleepTemperaturePoint: Decodable {
    struct Value: Decodable {
        let date: CivilDate?
        let nightlyTemperatureCelsius: Double
        let baselineTemperatureCelsius: Double?
    }
    let dailySleepTemperatureDerivations: Value
}

nonisolated struct RollupPoint: Decodable {
    struct Steps: Decodable { let countSum: String? }
    struct Energy: Decodable { let kcalSum: Double? }
    struct HeartRate: Decodable { let beatsPerMinuteAvg: Double? }
    struct ActiveMinutes: Decodable {
        struct Level: Decodable { let activeMinutesSum: String? }
        let activeMinutesRollupByActivityLevel: [Level]?
    }

    let startTime: Date?
    let civilStartTime: CivilDateTime?
    let steps: Steps?
    let activeEnergyBurned: Energy?
    let heartRate: HeartRate?
    let activeMinutes: ActiveMinutes?
}

nonisolated struct ProfileResponse: Decodable {
    let age: Int?
    let membershipStartDate: CivilDate?
}

nonisolated struct APIErrorBody: Decodable {
    struct Detail: Decodable { let reason: String? }
    struct Body: Decodable {
        let message: String?
        let details: [Detail]?
    }
    let error: Body
}

// MARK: Mapping to app models

nonisolated enum GoogleHealthMapping {
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            for style in [Date.ISO8601FormatStyle(includingFractionalSeconds: true), Date.ISO8601FormatStyle()] {
                if let date = try? style.parse(text) { return date }
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognised date \(text)")
        }
        return decoder
    }()

    static func workout(from exercise: ExercisePoint.Exercise) -> Workout {
        let type = exercise.exerciseType ?? "WORKOUT"
        let name = exercise.displayName ?? type.replacingOccurrences(of: "_", with: " ").lowercased().capitalized
        return Workout(
            name: name,
            kind: kind(for: type),
            start: exercise.interval.startTime,
            minutes: Int(exercise.interval.endTime.timeIntervalSince(exercise.interval.startTime) / 60),
            kcal: Int(exercise.metricsSummary?.caloriesKcal ?? 0),
            indoor: type.hasPrefix("TREADMILL") || type.hasPrefix("INDOOR"),
            distanceKm: exercise.metricsSummary?.distanceMillimeters.map { $0 / 1_000_000 }
        )
    }

    static func kind(for exerciseType: String) -> Workout.Kind {
        switch exerciseType {
        case let t where t.contains("RUN"): .run
        case let t where t.contains("WALK") || t.contains("HIK"): .walk
        case let t where ["YOGA", "PILATES", "STRETCH", "MOBILITY"].contains(where: t.contains): .mobility
        default: .other
        }
    }

    /// One summary per entry in `days` (local midnights, oldest first). A night's sleep counts for the
    /// day it ends on; when there are several sessions the main one wins, then the longest.
    static func history(days: [Date], steps: [RollupPoint]?, energy: [RollupPoint]?, minutes: [RollupPoint]?,
                        sleep: [SleepPoint]?, resting: [RestingHeartRatePoint]?, hrv: [DailyHRVPoint]? = nil,
                        breathing: [DailyRespiratoryRatePoint]? = nil, temperature: [SleepTemperaturePoint]? = nil) -> [DaySummary] {
        func byDate<P, T>(_ points: [P]?, _ entry: (P) -> (CivilDate?, T?)) -> [CivilDate: T] {
            Dictionary((points ?? []).compactMap { p in
                let (date, value) = entry(p)
                return date.flatMap { d in value.map { (d, $0) } }
            }) { a, _ in a }
        }
        let hrvByDay = byDate(hrv) { ($0.dailyHeartRateVariability.date, $0.dailyHeartRateVariability.averageHeartRateVariabilityMilliseconds) }
        let breathingByDay = byDate(breathing) { ($0.dailyRespiratoryRate.date, $0.dailyRespiratoryRate.breathsPerMinute) }
        let tempByDay = byDate(temperature) { p -> (CivilDate?, Double?) in
            let v = p.dailySleepTemperatureDerivations
            return (v.date, v.baselineTemperatureCelsius.map { v.nightlyTemperatureCelsius - $0 })
        }

        func byDay<T>(_ points: [RollupPoint]?, _ value: (RollupPoint) -> T?) -> [CivilDate: T] {
            Dictionary((points ?? []).compactMap { p in p.civilStartTime.flatMap { civil in value(p).map { (civil.date, $0) } } }) { a, _ in a }
        }
        let stepsByDay = byDay(steps) { $0.steps?.countSum.flatMap { Int($0) } }
        let energyByDay = byDay(energy) { $0.activeEnergyBurned?.kcalSum.map { Int($0) } }
        let minutesByDay = byDay(minutes) { p in
            p.activeMinutes?.activeMinutesRollupByActivityLevel?.compactMap { $0.activeMinutesSum.flatMap { Int($0) } }.reduce(0, +)
        }
        let restingByDay = Dictionary((resting ?? []).compactMap { p in
            p.dailyRestingHeartRate.date.flatMap { date in Int(p.dailyRestingHeartRate.beatsPerMinute).map { (date, $0) } }
        }) { a, _ in a }

        func length(_ s: SleepPoint.Sleep) -> TimeInterval { s.interval.endTime.timeIntervalSince(s.interval.startTime) }
        let nights = Dictionary(grouping: (sleep ?? []).map(\.sleep)) { CivilDate($0.interval.endTime) }
            .mapValues { sessions in
                sessions.max { a, b in
                    (a.metadata?.main == true ? 1 : 0, length(a)) < (b.metadata?.main == true ? 1 : 0, length(b))
                }!
            }

        return days.map { day in
            let civil = CivilDate(day)
            let night = nights[civil]
            return DaySummary(
                day: day,
                steps: stepsByDay[civil],
                activeKcal: energyByDay[civil],
                activeMinutes: minutesByDay[civil],
                sleepMinutes: night.map { $0.summary?.minutesAsleep.flatMap { Int($0) } ?? Int(length($0) / 60) },
                bedtime: night?.interval.startTime,
                wakeTime: night?.interval.endTime,
                restingHeartRate: restingByDay[civil],
                hrvMs: hrvByDay[civil],
                breathingRate: breathingByDay[civil],
                skinTempDeltaC: tempByDay[civil]
            )
        }
    }

    /// Places 30-minute heart-rate averages on a since-midnight grid, carrying the last value across gaps.
    static func halfHourSeries(_ samples: [(start: Date, bpm: Double)], dayStart: Date) -> [Double] {
        let byIndex = Dictionary(samples.map { (Int($0.start.timeIntervalSince(dayStart) / 1800), $0.bpm) }) { first, _ in first }
        guard let last = byIndex.keys.max(), let firstValue = samples.min(by: { $0.start < $1.start })?.bpm else { return [] }
        var series: [Double] = []
        var current = firstValue
        for index in 0...last {
            current = byIndex[index] ?? current
            series.append(current)
        }
        return series
    }
}
