import Foundation

/// Everything the user enters in the app, saved as one JSON file on the device.
/// Google Health data isn't saved here; it's re-fetched on every sync.
struct SavedData: Codable {
    var name: String
    var sex: Profile.Sex
    var age: Int
    var heightCm: Int
    var weightHistory: [Double]
    var weightHistoryStart: Date
    var goalActiveKcal: Int
    var goalSteps: Int
    var goalSleepHours: Int
    var goalIntakeKcal: Int
    var goalWaterGlasses: Int
    var goalWeightKg: Double
    var meals: [Meal]
    var manualWorkouts: [Workout]
    /// Optional so files saved before the per-day log still load.
    var waterLog: [String: Int]?
}

enum LocalStorage {
    static var defaultURL: URL { .applicationSupportDirectory.appending(path: "user-data.json") }

    static func load(from url: URL) -> SavedData? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SavedData.self, from: data)
    }

    /// Atomic write, so a crash mid-save never leaves a half-written file.
    static func save(_ saved: SavedData, to url: URL) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(saved).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            assertionFailure("Couldn’t save user data: \(error)")
        }
    }
}
