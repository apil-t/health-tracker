// Logic checks for the UI-free layers (Models, Data, Domain). Also proves they build without SwiftUI.
// Run from the repo root:
//   xcrun swiftc -swift-version 5 MyApp/Models/*.swift MyApp/Data/*.swift MyApp/Data/GoogleHealth/*.swift MyApp/Domain/*.swift Checks/main.swift -o /tmp/checks && /tmp/checks

let s = HealthStore(storageURL: nil)
assert(s.activeKcal == 542 && s.activeMinutes == 76, "activity totals")
assert(s.eatenKcal() == 1640 && s.remainingKcal() == 560, "intake totals")
assert(Format.percent(s.moveFraction) == "83%", "move %")
assert(Format.oneDecimal(s.bmi) == "22.9" && HealthRules.bmiCategory(s.bmi) == "Healthy range", "bmi")
assert(Format.minutesSeconds(s.workouts[0].paceSeconds!) == "6:15", "pace")
let f = s.workouts[0].finalSplit!
assert(f.seconds == 45 && Format.minutesSeconds(f.pace) == "6:15", "final split")
assert(s.heartRateLowest == 52 && s.heartRateHighest == 164, "hr range")
assert(HealthRules.restingInsight(resting: 58, average30Day: 61).isPositive, "resting insight")
assert(HealthRules.fiberInsight(s.fiber).message.contains("7 g"), "fiber insight")
assert(HealthRules.greeting(hour: 20) == "Good evening" && HealthRules.stressLabel(24).hasPrefix("Low"), "rules")
print("all checks passed")

// Profile editing
var p = s.profile
assert(HealthRules.profileErrors(p).isEmpty, "sample profile valid")
p.name = "  "; p.age = 5; p.heightCm = 20; p.weightKg = 10
assert(HealthRules.profileErrors(p).count == 4, "each invalid field reported")
p = s.profile; p.name = " Sam Lee "; p.weightKg = 71.9
s.updateProfile(p)
assert(s.name == "Sam Lee" && s.initials == "SL", "name trimmed")
assert(s.weightKg == 71.9 && s.weightHistory.count == 14, "new weight logged as weigh-in")
s.updateProfile(s.profile)
assert(s.weightHistory.count == 14, "unchanged weight not duplicated")
print("profile checks passed")

// Google Health: decode the example responses from the API reference.
import Foundation
let rollupJSON = #"{"rollupDataPoints":[{"civilStartTime":{"date":{"year":2026,"month":2,"day":26},"time":{}},"civilEndTime":{"date":{"year":2026,"month":2,"day":26},"time":{"hours":23,"minutes":59,"seconds":59}},"steps":{"countSum":"3822"}}]}"#
let rollup = try! GoogleHealthMapping.decoder.decode(RollupResponse.self, from: Data(rollupJSON.utf8))
assert(rollup.rollupDataPoints?.first?.steps?.countSum == "3822", "steps rollup")
assert(rollup.rollupDataPoints?.first?.civilStartTime?.date == CivilDate(year: 2026, month: 2, day: 26), "civil date")

let exerciseJSON = #"{"dataPoints":[{"name":"users/1/dataTypes/exercise/dataPoints/7","exercise":{"interval":{"startTime":"2026-09-03T11:20:00Z","endTime":"2026-09-03T11:50:00Z"},"exerciseType":"RUNNING","metricsSummary":{"caloriesKcal":380.0,"distanceMillimeters":5000000.0,"steps":"6200"}}}]}"#
let exercises = try! GoogleHealthMapping.decoder.decode(DataPointList<ExercisePoint>.self, from: Data(exerciseJSON.utf8))
let run = GoogleHealthMapping.workout(from: exercises.dataPoints![0].exercise)
assert(run.kind == .run && run.name == "Running" && run.minutes == 30 && run.kcal == 380 && run.distanceKm == 5, "exercise mapping")
assert(GoogleHealthMapping.kind(for: "TREADMILL_WALK") == .walk && GoogleHealthMapping.kind(for: "BIKING") == .other, "exercise kinds")

let sleepJSON = #"{"dataPoints":[{"name":"x","sleep":{"interval":{"startTime":"2026-03-03T20:57:30Z","startUtcOffset":"0s","endTime":"2026-03-04T04:41:30Z","endUtcOffset":"0s"},"type":"STAGES","metadata":{"stagesStatus":"SUCCEEDED","processed":true,"main":true},"summary":{"minutesInSleepPeriod":"464","minutesAsleep":"407"}}}],"nextPageToken":""}"#
let sleep = try! GoogleHealthMapping.decoder.decode(DataPointList<SleepPoint>.self, from: Data(sleepJSON.utf8))
assert(sleep.dataPoints?.first?.sleep.summary?.minutesAsleep == "407" && sleep.dataPoints?.first?.sleep.metadata?.main == true, "sleep")

let fractional = #"{"dataPoints":[{"weight":{"sampleTime":{"physicalTime":"2026-10-01T07:00:00.123Z"},"weightGrams":72400}}]}"#
assert(try! GoogleHealthMapping.decoder.decode(DataPointList<WeightPoint>.self, from: Data(fractional.utf8)).dataPoints?.first?.weight.weightGrams == 72400, "fractional-second dates")

// Heart-rate grid: gaps carry the last value, leading gap takes the first value.
let midnight = Date(timeIntervalSince1970: 0)
let series = GoogleHealthMapping.halfHourSeries([(midnight + 3600, 70), (midnight + 7200, 90)], dayStart: midnight)
assert(series == [70, 70, 70, 70, 90], "half-hour series \(series)")

// Syncing replaces synced workouts but keeps ones logged in the app.
let store = HealthStore(storageURL: nil)
store.logWorkout(kind: .walk, minutes: 10, kcal: 40)
store.apply(HealthSnapshot(activeKcal: 500, workouts: [run]))
assert(store.workouts.count == 2 && store.workouts.last?.isManual == true, "manual workout kept")
assert(store.activeKcal == 540, "synced total + manual")
print("google health checks passed")

// Saving: user entries survive a relaunch; synced-only data doesn't need to.
let file = FileManager.default.temporaryDirectory.appending(path: "myapp-check-\(UUID()).json")
let first = HealthStore(storageURL: file)
assert(first.name == "Apil", "default name")
var edited = first.profile
edited.name = "Apil Thapa"
first.updateProfile(edited)
first.addMeal(kind: .snack, food: "Banana", kcal: 100)
first.logWorkout(kind: .walk, minutes: 20, kcal: 80)
first.goalSteps = 12_000
first.save()
let relaunched = HealthStore(storageURL: file)
assert(relaunched.name == "Apil Thapa" && relaunched.goalSteps == 12_000, "profile and goals restored")
assert(relaunched.meals.contains { $0.food == "Banana" }, "meal restored")
assert(relaunched.workouts.filter(\.isManual).count == 1, "manual workout restored once")
relaunched.deleteMeal(relaunched.meals.first { $0.food == "Banana" }!)
assert(!HealthStore(storageURL: file).meals.contains { $0.food == "Banana" }, "delete persisted")
try? FileManager.default.removeItem(at: file)

// A new day: yesterday's meals and water don't count today.
let day = HealthStore(storageURL: nil)
day.waterLog = [Date.now.addingTimeInterval(-86_400).dayKey: 5]
assert(day.waterGlasses(on: .now) == 0, "water resets on a new day")
day.addWaterGlass()
assert(day.waterGlasses(on: .now) == 1 && day.waterGlasses(on: Date.now.addingTimeInterval(-86_400)) == 5, "water kept per day")
day.meals = [Meal(kind: .dinner, time: Date.now.addingTimeInterval(-86_400), food: "Old", kcal: 500)]
assert(day.eatenKcal() == 0 && day.meals(on: .now).isEmpty, "yesterday's meals excluded")
assert(day.eatenKcal(on: Date.now.addingTimeInterval(-86_400)) == 500, "yesterday's meals on yesterday")
print("saving checks passed")

// History: one summary per day, built from Google's rollups and sessions.
let cal = Calendar.current
let todayStart = cal.startOfDay(for: .now)
let yesterday = cal.date(byAdding: .day, value: -1, to: todayStart)!
func civilJSON(_ d: Date) -> String { let c = CivilDate(d); return #"{"date":{"year":\#(c.year),"month":\#(c.month),"day":\#(c.day)},"time":{}}"# }
let stepsRollup = try! GoogleHealthMapping.decoder.decode(RollupResponse.self, from: Data(#"{"rollupDataPoints":[{"civilStartTime":\#(civilJSON(yesterday)),"steps":{"countSum":"9000"}},{"civilStartTime":\#(civilJSON(todayStart)),"steps":{"countSum":"374"}}]}"#.utf8)).rollupDataPoints
let minutesRollup = try! GoogleHealthMapping.decoder.decode(RollupResponse.self, from: Data(#"{"rollupDataPoints":[{"civilStartTime":\#(civilJSON(yesterday)),"activeMinutes":{"activeMinutesRollupByActivityLevel":[{"activityLevel":"LIGHT","activeMinutesSum":"30"},{"activityLevel":"VIGOROUS","activeMinutesSum":"12"}]}}]}"#.utf8)).rollupDataPoints
let wake = yesterday.addingTimeInterval(7 * 3600)
let nap = SleepPoint(sleep: .init(interval: .init(startTime: wake.addingTimeInterval(6 * 3600), endTime: wake.addingTimeInterval(7 * 3600)), metadata: .init(main: false), summary: nil))
let night = SleepPoint(sleep: .init(interval: .init(startTime: wake.addingTimeInterval(-8 * 3600), endTime: wake), metadata: .init(main: true), summary: .init(minutesAsleep: "450")))
let restingJSON = #"{"dataPoints":[{"dailyRestingHeartRate":{"date":{"year":\#(CivilDate(yesterday).year),"month":\#(CivilDate(yesterday).month),"day":\#(CivilDate(yesterday).day)},"beatsPerMinute":"57"}}]}"#
let restingPoints = try! GoogleHealthMapping.decoder.decode(DataPointList<RestingHeartRatePoint>.self, from: Data(restingJSON.utf8)).dataPoints
let history = GoogleHealthMapping.history(days: [yesterday, todayStart], steps: stepsRollup, energy: nil, minutes: minutesRollup,
                                          sleep: [nap, night], resting: restingPoints)
assert(history.count == 2 && history[0].steps == 9000 && history[1].steps == 374, "steps by day")
assert(history[0].activeMinutes == 42, "active minutes summed across levels")
assert(history[0].sleepMinutes == 450 && history[0].wakeTime == wake, "main sleep session wins over a longer-looking nap")
assert(history[0].restingHeartRate == 57 && history[1].restingHeartRate == nil, "resting by date")
assert(history[0].activeKcal == nil, "missing data stays nil")

// Store: past days read from history, today from live values.
let hs = HealthStore(storageURL: nil)
hs.history = history
hs.syncedActiveKcal = 49
hs.workouts = []
assert(hs.summary(on: yesterday).steps == 9000 && hs.summary(on: .now).steps == hs.steps, "summary by day")
assert(hs.activeKcal(on: .now) == 49 && hs.activeMinutes(on: yesterday) == 42, "per-day activity")
assert(hs.summaries(lastDays: 7).count == 7 && cal.isDateInToday(hs.summaries(lastDays: 7).last!.day), "last 7 days end today")
let week = hs.summaries(weekOf: .now)
assert(week.count == 7 && cal.component(.weekday, from: week[0].day) == 2, "week starts Monday")
assert(HealthStore.sampleHistory().count == 365, "sample year")
assert(HealthRules.trendStats([8000, nil, 12000, 10000], goal: 10000) == TrendStats(average: 10000, best: 12000, daysMeetingGoal: 2, daysWithData: 3), "trend stats")
assert(HealthRules.toGo(1754, unit: "steps") == "1,754 steps to go" && HealthRules.toGo(-5, unit: "min") == "Goal reached", "to go")
print("history checks passed")

// Stress estimate: own-baseline z-scores, HRV-led.
func night(_ i: Int, hrv: Double?, rhr: Int?, sleep: Int? = 450, breathing: Double? = nil, temp: Double? = nil) -> DaySummary {
    DaySummary(day: Date(timeIntervalSince1970: Double(i) * 86_400), sleepMinutes: sleep, restingHeartRate: rhr,
               hrvMs: hrv, breathingRate: breathing, skinTempDeltaC: temp)
}
let usual = (0..<10).map { night($0, hrv: [48, 52, 50, 49, 51, 50, 52, 48, 50, 50][$0], rhr: [57, 59, 58, 58, 57, 59, 58, 58, 57, 59][$0],
                                  breathing: 14.5, temp: 0) }
let calm = HealthRules.stress(today: night(10, hrv: 50, rhr: 58, breathing: 14.5, temp: 0), baseline: usual)!
assert((28...32).contains(calm.score), "usual day scores about 30, got \(calm.score)")
let strained = HealthRules.stress(today: night(10, hrv: 38, rhr: 64, sleep: 300, breathing: 15.5, temp: 0.6), baseline: usual)!
assert(strained.score >= 70 && HealthRules.stressLabel(strained.score) == "High", "low HRV + high RHR + short sleep is high, got \(strained.score)")
assert(strained.factors.first?.name == "HRV" && HealthRules.strainLabel(strained.factors[0].strain) == "Adds stress", "HRV leads")
let recovered = HealthRules.stress(today: night(10, hrv: 60, rhr: 55, breathing: 14.5, temp: -0.5), baseline: usual)!
assert(recovered.score < calm.score, "better than usual scores lower")
assert(recovered.factors.first { $0.name == "Skin temperature" }!.strain == 0, "cool skin never lowers stress")
assert(HealthRules.stress(today: night(10, hrv: 40, rhr: 60), baseline: Array(usual.prefix(6))) == nil, "needs 7 nights")
assert(HealthRules.stress(today: night(10, hrv: 50, rhr: 58, sleep: 0), baseline: usual)!.factors.allSatisfy { $0.name != "Sleep" }, "no-sleep-data night ignored")
let sampleStore = HealthStore(storageURL: nil)
assert(sampleStore.stressEstimate() != nil && sampleStore.stressScores(lastDays: 7).allSatisfy { $0.score != nil }, "sample data yields stress")
print("stress checks passed")
