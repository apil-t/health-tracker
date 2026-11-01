import Foundation

/// Everything one sync pulls from Google Health. Nil means "not available"; the store keeps its current value.
struct HealthSnapshot {
    var steps: Int?
    var activeKcal: Int?
    var activeMinutes: Int?
    /// 30-minute heart-rate averages since midnight.
    var heartRate: [Double]?
    var restingHeartRate: Int?
    var restingHeartRate30Day: Int?
    var sleepMinutes: Int?
    /// One entry per day, oldest first, ending today.
    var history: [DaySummary]?
    /// Synced workouts across the history window.
    var workouts: [Workout]?
    /// Weigh-ins in kg, oldest first, with the date of the first one.
    var weights: (start: Date, kg: [Double])?
    var heightCm: Int?
    var age: Int?
    var memberSince: Date?
    /// "Workouts: <error>" for each data type that failed to load.
    var problems: [String] = []
}

final class GoogleHealthClient {
    /// Days of steps, energy, active minutes, sleep and workouts to fetch.
    static let activityHistoryDays = 90
    /// Days of resting heart rate (feeds the Year chart).
    static let restingHistoryDays = 365

    let auth = GoogleAuth()
    private let base = "https://health.googleapis.com/v4/users/me/"

    /// Fetches today plus the history window. Fails only if the account itself is unusable; a missing
    /// scope or data type leaves that field nil, so the app keeps working with partial consent.
    // ponytail: refetches the full window on every sync (~20 requests). Fetch only days since the last sync if quota matters.
    func fetchSnapshot(now: Date = .now) async throws -> HealthSnapshot {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let activityStart = calendar.date(byAdding: .day, value: -(Self.activityHistoryDays - 1), to: today)!
        let restingStart = calendar.date(byAdding: .day, value: -(Self.restingHistoryDays - 1), to: today)!

        let _: [String: String] = try await get("identity") // throws accountNotLinked / signedOut early

        async let stepsResult = capture { try await self.dailyRollUp("steps", from: activityStart, to: today, maxDays: 90) }
        async let energyResult = capture { try await self.dailyRollUp("active-energy-burned", from: activityStart, to: today, maxDays: 90) }
        async let minutesResult = capture { try await self.dailyRollUp("active-minutes", from: activityStart, to: today, maxDays: 14) }
        async let heartRateResult = capture { try await self.rollUp("heart-rate", from: today, to: now, windowSeconds: 1800) }
        async let restingResult = capture { () -> [RestingHeartRatePoint] in
            try await self.list("daily-resting-heart-rate", pageSize: Self.restingHistoryDays)
        }
        async let sleepResult = capture { () -> [SleepPoint] in
            try await self.list("sleep", filter: "sleep.interval.end_time >= \"\(self.iso(activityStart))\"", pageSize: 25)
        }
        async let exerciseResult = capture { () -> [ExercisePoint] in
            try await self.list("exercise", filter: "exercise.interval.civil_start_time >= \"\(self.civilDate(activityStart).isoString)\"", pageSize: 25)
        }
        let since = "\"\(self.civilDate(activityStart).isoString)\""
        async let hrvResult = capture { () -> [DailyHRVPoint] in
            try await self.list("daily-heart-rate-variability", filter: "daily_heart_rate_variability.date >= \(since)", pageSize: 100)
        }
        async let breathingResult = capture { () -> [DailyRespiratoryRatePoint] in
            try await self.list("daily-respiratory-rate", filter: "daily_respiratory_rate.date >= \(since)", pageSize: 100)
        }
        async let temperatureResult = capture { () -> [SleepTemperaturePoint] in
            try await self.list("daily-sleep-temperature-derivations", filter: "daily_sleep_temperature_derivations.date >= \(since)", pageSize: 100)
        }
        async let weightsResult = capture { () -> [WeightPoint] in
            try await self.list("weight", filter: "weight.sample_time.physical_time >= \"\(self.iso(now - 42 * 86_400))\"", pageSize: 100)
        }
        async let heightResult = capture { () -> [HeightPoint] in try await self.list("height", pageSize: 1) }
        async let profileResult = capture { () -> ProfileResponse in try await self.get("profile") }

        var snapshot = HealthSnapshot()
        func value<T>(_ result: Result<T, Error>, _ label: String) -> T? {
            switch result {
            case .success(let value): return value
            case .failure(let error):
                snapshot.problems.append("\(label): \(error.localizedDescription)")
                return nil
            }
        }

        let steps = value(await stepsResult, "Steps")
        let energy = value(await energyResult, "Active energy")
        let minutes = value(await minutesResult, "Active minutes")
        let heartRate = value(await heartRateResult, "Heart rate")
        let resting = value(await restingResult, "Resting heart rate")
        let sleep = value(await sleepResult, "Sleep")
        let exercise = value(await exerciseResult, "Workouts")
        let hrv = value(await hrvResult, "HRV")
        let breathing = value(await breathingResult, "Breathing rate")
        let temperature = value(await temperatureResult, "Skin temperature")
        let weights = value(await weightsResult, "Weight")
        let height = value(await heightResult, "Height")
        let profile = value(await profileResult, "Profile")

        let days = (0..<Self.restingHistoryDays).map { calendar.date(byAdding: .day, value: $0, to: restingStart)! }
        let history = GoogleHealthMapping.history(days: days, steps: steps, energy: energy, minutes: minutes,
                                                  sleep: sleep, resting: resting, hrv: hrv, breathing: breathing,
                                                  temperature: temperature)
        snapshot.history = history
        // A request that succeeded but has nothing for today means 0, not "keep the old value".
        let todaySummary = history.last
        if steps != nil { snapshot.steps = todaySummary?.steps ?? 0 }
        if energy != nil { snapshot.activeKcal = todaySummary?.activeKcal ?? 0 }
        if minutes != nil { snapshot.activeMinutes = todaySummary?.activeMinutes ?? 0 }
        if sleep != nil { snapshot.sleepMinutes = todaySummary?.sleepMinutes ?? 0 }
        let restingValues = history.compactMap(\.restingHeartRate)
        snapshot.restingHeartRate = restingValues.last
        if !restingValues.isEmpty {
            let recent = restingValues.suffix(30)
            snapshot.restingHeartRate30Day = recent.reduce(0, +) / recent.count
        }

        if let points = heartRate {
            let samples = points.compactMap { p in p.startTime.flatMap { start in p.heartRate?.beatsPerMinuteAvg.map { (start, $0) } } }
            snapshot.heartRate = GoogleHealthMapping.halfHourSeries(samples, dayStart: today)
        }
        snapshot.workouts = exercise?.map { GoogleHealthMapping.workout(from: $0.exercise) }.sorted { $0.start < $1.start }
        if let points = weights?.sorted(by: { $0.weight.sampleTime.physicalTime < $1.weight.sampleTime.physicalTime }),
           let first = points.first {
            snapshot.weights = (first.weight.sampleTime.physicalTime, points.map { $0.weight.weightGrams / 1000 })
        }
        snapshot.heightCm = height?.first.flatMap { Int($0.height.heightMillimeters) }.map { $0 / 10 }
        if let profile {
            snapshot.age = profile.age
            snapshot.memberSince = profile.membershipStartDate.flatMap {
                calendar.date(from: DateComponents(year: $0.year, month: $0.month, day: $0.day))
            }
        }
        return snapshot
    }

    private func capture<T>(_ operation: () async throws -> T) async -> Result<T, Error> {
        do { return .success(try await operation()) } catch { return .failure(error) }
    }

    // MARK: Endpoints

    /// Follows `nextPageToken` until the list is complete (sleep and exercise return at most 25 per page).
    private func list<Point: Decodable>(_ dataType: String, filter: String? = nil, pageSize: Int) async throws -> [Point] {
        var points: [Point] = []
        var pageToken: String?
        repeat {
            var query = ["pageSize": "\(pageSize)"]
            query["filter"] = filter
            query["pageToken"] = pageToken
            let response: DataPointList<Point> = try await get("dataTypes/\(dataType)/dataPoints", query: query)
            points += response.dataPoints ?? []
            pageToken = response.nextPageToken.flatMap { $0.isEmpty ? nil : $0 }
        } while pageToken != nil
        return points
    }

    /// One value per day. Google caps the range per request (14 days for heart-rate and active-minutes,
    /// 90 for the rest), so longer ranges are fetched in consecutive chunks.
    private func dailyRollUp(_ dataType: String, from start: Date, to end: Date, maxDays: Int) async throws -> [RollupPoint] {
        struct Body: Encodable {
            struct Range: Encodable { let start: CivilDateTime; let end: CivilDateTime }
            let range: Range
            let windowSizeDays = 1
        }
        let calendar = Calendar.current
        var points: [RollupPoint] = []
        var chunkStart = start
        while chunkStart <= end {
            let chunkEnd = min(calendar.date(byAdding: .day, value: maxDays - 1, to: chunkStart)!, end)
            let body = Body(range: .init(start: CivilDateTime(date: civilDate(chunkStart)),
                                         end: CivilDateTime(date: civilDate(chunkEnd), time: .init(hours: 23, minutes: 59, seconds: 59))))
            let response: RollupResponse = try await send("dataTypes/\(dataType)/dataPoints:dailyRollUp", body: body)
            points += response.rollupDataPoints ?? []
            chunkStart = calendar.date(byAdding: .day, value: 1, to: chunkEnd)!
        }
        return points
    }

    private func rollUp(_ dataType: String, from start: Date, to end: Date, windowSeconds: Int) async throws -> [RollupPoint] {
        struct Body: Encodable {
            struct Range: Encodable { let startTime: String; let endTime: String }
            let range: Range
            let windowSize: String
        }
        let body = Body(range: .init(startTime: iso(start), endTime: iso(end)), windowSize: "\(windowSeconds)s")
        let response: RollupResponse = try await send("dataTypes/\(dataType)/dataPoints:rollUp", body: body)
        return response.rollupDataPoints ?? []
    }

    // MARK: Transport

    private func get<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        var url = URLComponents(string: base + path)!
        if !query.isEmpty { url.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        return try await perform(URLRequest(url: url.url!))
    }

    private func send<T: Decodable>(_ path: String, body: some Encodable) async throws -> T {
        var request = URLRequest(url: URL(string: base + path)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await perform(request)
    }

    /// Adds the bearer token; on a 401 refreshes once and retries.
    private func perform<T: Decodable>(_ request: URLRequest, isRetry: Bool = false) async throws -> T {
        var request = request
        request.setValue("Bearer \(try await auth.accessToken(forceRefresh: isRetry))", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data, response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: request) } catch { throw HealthAPIError.offline }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401, !isRetry { return try await perform(request, isRetry: true) }
        guard (200..<300).contains(status) else {
            let body = try? GoogleHealthMapping.decoder.decode(APIErrorBody.self, from: data)
            if body?.error.details?.contains(where: { $0.reason == "ACCOUNT_NOT_LINKED" }) == true { throw HealthAPIError.accountNotLinked }
            throw HealthAPIError.server(status: status, message: body?.error.message ?? "Request failed.")
        }
        return try GoogleHealthMapping.decoder.decode(T.self, from: data)
    }

    private func iso(_ date: Date) -> String { date.ISO8601Format() }

    private func civilDate(_ date: Date) -> CivilDate { CivilDate(date) }
}
