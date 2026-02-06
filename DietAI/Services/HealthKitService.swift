import Foundation
import HealthKit

// MARK: - HealthKit Service
@MainActor
@Observable
final class HealthKitService {
    static let shared = HealthKitService()

    private let healthStore = HKHealthStore()

    private(set) var isAuthorized = false
    private(set) var authorizationStatus: HKAuthorizationStatus = .notDetermined

    // Read types
    private let readTypes: Set<HKObjectType> = {
        var types: Set<HKObjectType> = []
        if let bodyMass = HKObjectType.quantityType(forIdentifier: .bodyMass) {
            types.insert(bodyMass)
        }
        if let height = HKObjectType.quantityType(forIdentifier: .height) {
            types.insert(height)
        }
        if let activeEnergy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) {
            types.insert(activeEnergy)
        }
        if let basalEnergy = HKObjectType.quantityType(forIdentifier: .basalEnergyBurned) {
            types.insert(basalEnergy)
        }
        if let stepCount = HKObjectType.quantityType(forIdentifier: .stepCount) {
            types.insert(stepCount)
        }
        types.insert(HKObjectType.workoutType())
        // Date of birth is a characteristic type, added separately
        if let dob = HKObjectType.characteristicType(forIdentifier: .dateOfBirth) {
            types.insert(dob)
        }
        // Analytics: Sleep data
        if let sleepAnalysis = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleepAnalysis)
        }
        // Analytics: Resting heart rate
        if let restingHR = HKObjectType.quantityType(forIdentifier: .restingHeartRate) {
            types.insert(restingHR)
        }
        // Analytics: Heart rate variability
        if let hrv = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) {
            types.insert(hrv)
        }
        // Analytics: Distance walking/running
        if let distance = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning) {
            types.insert(distance)
        }
        // Analytics: Body fat percentage (optional)
        if let bodyFat = HKObjectType.quantityType(forIdentifier: .bodyFatPercentage) {
            types.insert(bodyFat)
        }
        return types
    }()

    // Write types
    private let writeTypes: Set<HKSampleType> = {
        var types: Set<HKSampleType> = []
        if let energy = HKObjectType.quantityType(forIdentifier: .dietaryEnergyConsumed) {
            types.insert(energy)
        }
        if let protein = HKObjectType.quantityType(forIdentifier: .dietaryProtein) {
            types.insert(protein)
        }
        if let carbs = HKObjectType.quantityType(forIdentifier: .dietaryCarbohydrates) {
            types.insert(carbs)
        }
        if let fat = HKObjectType.quantityType(forIdentifier: .dietaryFatTotal) {
            types.insert(fat)
        }
        return types
    }()

    private static let authorizationRequestedKey = "HealthKitAuthorizationRequested"

    private init() {
        // Restore authorization state from persisted flag
        // HealthKit doesn't expose read status, so we track if authorization was ever requested
        if UserDefaults.standard.bool(forKey: Self.authorizationRequestedKey) && isHealthDataAvailable {
            isAuthorized = true
        }
    }

    // MARK: - Availability Check
    var isHealthDataAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    // MARK: - Authorization
    func requestAuthorization() async throws {
        guard isHealthDataAvailable else {
            throw HealthKitError.notAvailable
        }

        try await healthStore.requestAuthorization(toShare: writeTypes, read: readTypes)

        // Check actual authorization status for key types
        if let activeEnergy = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            let status = healthStore.authorizationStatus(for: activeEnergy)
            // Note: .sharingDenied means we can't write, but we might still be able to read
            // HealthKit doesn't tell us read status directly, we just try to use it
            authorizationStatus = status
        }

        // Persist that authorization was requested - HealthKit doesn't expose read status
        // but after requesting, we can attempt to read data (it will return empty if denied)
        UserDefaults.standard.set(true, forKey: Self.authorizationRequestedKey)
        isAuthorized = true
    }

    // Check if we have any authorization (for UI state)
    func checkAuthorizationStatus() {
        guard isHealthDataAvailable else {
            isAuthorized = false
            return
        }

        // HealthKit doesn't expose read authorization status directly.
        // We use a persisted flag to track if authorization was ever requested.
        // If it was, we assume read access may be available and try to fetch data.
        if UserDefaults.standard.bool(forKey: Self.authorizationRequestedKey) {
            isAuthorized = true
            return
        }

        // Fallback: check write status as a hint (not reliable for read access)
        if let energyType = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed) {
            let status = healthStore.authorizationStatus(for: energyType)
            isAuthorized = status == .sharingAuthorized

            // Persist the flag if fallback detected authorization (for faster future loads)
            if isAuthorized {
                UserDefaults.standard.set(true, forKey: Self.authorizationRequestedKey)
            }
        }
    }

    // MARK: - Read Weight
    func fetchCurrentWeight() async throws -> Double? {
        guard let weightType = HKQuantityType.quantityType(forIdentifier: .bodyMass) else {
            return nil
        }

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: weightType,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }

                let weight = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
                continuation.resume(returning: weight)
            }

            healthStore.execute(query)
        }
    }

    // MARK: - Read Height
    func fetchCurrentHeight() async throws -> Double? {
        guard let heightType = HKQuantityType.quantityType(forIdentifier: .height) else {
            return nil
        }

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: heightType,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }

                let height = sample.quantity.doubleValue(for: .meterUnit(with: .centi))
                continuation.resume(returning: height)
            }

            healthStore.execute(query)
        }
    }

    // MARK: - Read Date of Birth / Age
    func fetchAge() -> Int? {
        do {
            let dateOfBirth = try healthStore.dateOfBirthComponents()
            guard let birthDate = Calendar.current.date(from: dateOfBirth) else {
                return nil
            }
            let ageComponents = Calendar.current.dateComponents([.year], from: birthDate, to: Date())
            return ageComponents.year
        } catch {
            return nil
        }
    }

    /// Fetch profile data (height, weight, age) for onboarding pre-fill
    func fetchProfileData() async -> HealthProfileData {
        // Run queries in parallel for faster loading
        async let weightTask = fetchCurrentWeight()
        async let heightTask = fetchCurrentHeight()
        let age = fetchAge() // Synchronous call, no need to parallelize

        let weight = try? await weightTask
        let height = try? await heightTask

        return HealthProfileData(
            height: height,
            weight: weight,
            age: age
        )
    }

    // MARK: - Read Active Calories
    func fetchTodayActiveCalories() async throws -> Double {
        guard let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else {
            return 0
        }

        let startOfDay = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(
            withStart: startOfDay,
            end: Date(),
            options: .strictStartDate
        )

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: energyType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                let calories = statistics?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                continuation.resume(returning: calories)
            }

            healthStore.execute(query)
        }
    }

    // MARK: - Read Steps
    func fetchTodaySteps() async throws -> Int {
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            return 0
        }

        let startOfDay = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(
            withStart: startOfDay,
            end: Date(),
            options: .strictStartDate
        )

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: stepType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                let steps = Int(statistics?.sumQuantity()?.doubleValue(for: .count()) ?? 0)
                continuation.resume(returning: steps)
            }

            healthStore.execute(query)
        }
    }

    // MARK: - Read Recent Workouts
    func fetchRecentWorkouts(days: Int = 7) async throws -> [HKWorkout] {
        let workoutType = HKObjectType.workoutType()
        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: Date(),
            options: .strictStartDate
        )

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: workoutType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                let workouts = (samples as? [HKWorkout]) ?? []
                continuation.resume(returning: workouts)
            }

            healthStore.execute(query)
        }
    }

    // MARK: - Enhanced Workout Fetching

    /// Fetch today's workouts with detailed categorization
    func fetchTodayWorkouts() async -> [WorkoutSummary] {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        guard let workouts = try? await fetchWorkouts(from: startOfDay, to: Date()) else {
            return []
        }
        return workouts.map { mapToWorkoutSummary($0) }
    }

    /// Fetch workouts for a date range
    func fetchWorkouts(from startDate: Date, to endDate: Date) async throws -> [HKWorkout] {
        let workoutType = HKObjectType.workoutType()
        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate,
            options: .strictStartDate
        )

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: workoutType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                let workouts = (samples as? [HKWorkout]) ?? []
                continuation.resume(returning: workouts)
            }
            healthStore.execute(query)
        }
    }

    /// Map HKWorkout to our WorkoutSummary with category and intensity
    private func mapToWorkoutSummary(_ workout: HKWorkout) -> WorkoutSummary {
        let category = WorkoutCategory.from(workout.workoutActivityType)
        let durationMinutes = workout.duration / 60

        // Use new statistics API (iOS 16+) instead of deprecated totalEnergyBurned
        var calories = 0
        if let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
           let statistics = workout.statistics(for: energyType),
           let sum = statistics.sumQuantity() {
            calories = Int(sum.doubleValue(for: .kilocalorie()))
        }

        let caloriesPerMinute = durationMinutes > 0 ? Double(calories) / durationMinutes : 0
        let intensity = WorkoutIntensity.from(caloriesPerMinute: caloriesPerMinute)

        return WorkoutSummary(
            category: category,
            intensity: intensity,
            durationMinutes: durationMinutes,
            calories: calories,
            endTime: workout.endDate
        )
    }

    /// Fetch weekly activity trend (last 7 days)
    func fetchWeeklyTrend() async -> WeeklyActivityTrend {
        let calendar = Calendar.current
        let today = Date()
        guard let weekAgo = calendar.date(byAdding: .day, value: -7, to: today) else {
            return .empty
        }

        let workouts = (try? await fetchWorkouts(from: weekAgo, to: today)) ?? []
        let summaries = workouts.map { mapToWorkoutSummary($0) }

        // Count unique workout days
        let workoutDays = Set(summaries.map { calendar.startOfDay(for: $0.endTime) }).count

        // Total workout minutes
        let totalMinutes = Int(summaries.reduce(0.0) { $0 + $1.durationMinutes })

        // Count strength and cardio days
        let strengthDays = Set(
            summaries.filter { $0.category == .strength }
                .map { calendar.startOfDay(for: $0.endTime) }
        ).count

        let cardioDays = Set(
            summaries.filter { [.cardio, .hiit, .endurance].contains($0.category) }
                .map { calendar.startOfDay(for: $0.endTime) }
        ).count

        // Find dominant category
        let categoryCounts = Dictionary(grouping: summaries, by: { $0.category })
        let dominantCategory = categoryCounts.max(by: { $0.value.count < $1.value.count })?.key

        return WeeklyActivityTrend(
            workoutDays: workoutDays,
            totalWorkoutMinutes: totalMinutes,
            strengthDays: strengthDays,
            cardioDays: cardioDays,
            dominantCategory: dominantCategory
        )
    }

    /// Fetch complete enhanced activity summary for today
    func fetchEnhancedActivitySummary() async -> EnhancedActivitySummary {
        // Run all queries in parallel for faster loading
        async let caloriesTask = fetchTodayActiveCalories()
        async let stepsTask = fetchTodaySteps()
        async let workoutsTask = fetchTodayWorkouts()
        async let weeklyTrendTask = fetchWeeklyTrend()

        let activeCalories = (try? await caloriesTask) ?? 0
        let steps = (try? await stepsTask) ?? 0
        let workouts = await workoutsTask
        let weeklyTrend = await weeklyTrendTask

        return EnhancedActivitySummary(
            date: Date(),
            activeCalories: Int(activeCalories),
            steps: steps,
            workouts: workouts,
            weeklyTrend: weeklyTrend
        )
    }

    /// Calculate smart calorie target based on workouts and activity patterns
    func calculateSmartCalorieTarget(
        baseTarget: Int,
        goal: GoalType,
        activitySummary: EnhancedActivitySummary
    ) -> SmartCalorieTarget {
        // Goal-based multiplier for how much of burned calories to eat back
        let goalMultiplier: Double = {
            switch goal {
            case .weightLoss: return 0.5
            case .muscleGain: return 1.0
            case .maintenance: return 0.75
            case .keto: return 0.5
            }
        }()

        // Calculate workout-specific bonus
        var workoutBonus = 0
        var totalProteinBoost = 0.0
        var recoveryWindowActive = false

        for workout in activitySummary.workouts {
            let baseBonus = Double(workout.calories) * workout.category.calorieRecoveryMultiplier
            let adjustedBonus = baseBonus * workout.intensity.intensityMultiplier * goalMultiplier
            workoutBonus += Int(adjustedBonus)

            totalProteinBoost += workout.category.proteinBoostPerKg

            if workout.isInRecoveryWindow && workout.category == .strength {
                recoveryWindowActive = true
            }
        }

        // Weekly trend bonus (small additional adjustment for consistent exercisers)
        let trendMultiplier = activitySummary.weeklyTrend.activityLevel.weeklyCalorieMultiplier
        let trendBonus = Int(Double(baseTarget) * (trendMultiplier - 1.0) * 0.3)

        return SmartCalorieTarget(
            base: baseTarget,
            workoutBonus: workoutBonus,
            trendBonus: trendBonus,
            proteinBoostPerKg: totalProteinBoost,
            recoveryWindowActive: recoveryWindowActive,
            dominantWorkoutCategory: activitySummary.dominantWorkoutCategory
        )
    }

    /// Build activity context for AI prompts
    func buildActivityPromptContext(from summary: EnhancedActivitySummary) -> ActivityPromptContext {
        ActivityPromptContext(
            todayWorkouts: summary.workouts,
            weeklyTrend: summary.weeklyTrend,
            isRecoveryWindowActive: summary.hasActiveRecoveryWindow,
            proteinBoostNeeded: summary.totalProteinBoostPerKg,
            dominantCategory: summary.dominantWorkoutCategory ?? summary.weeklyTrend.dominantCategory
        )
    }

    // MARK: - Analytics Data Fetching

    /// Fetch weight history for analytics charts
    func fetchWeightHistory(days: Int = 30) async -> [WeightDataPoint] {
        guard let weightType = HKQuantityType.quantityType(forIdentifier: .bodyMass) else {
            return []
        }

        let calendar = Calendar.current
        guard let startDate = calendar.date(byAdding: .day, value: -days, to: Date()) else {
            return []
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: Date(),
            options: .strictStartDate
        )

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: weightType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)]
            ) { _, samples, _ in
                let points = (samples as? [HKQuantitySample])?.map { sample in
                    WeightDataPoint(
                        date: sample.endDate,
                        weight: sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
                    )
                } ?? []
                continuation.resume(returning: points)
            }
            healthStore.execute(query)
        }
    }

    /// Fetch sleep data for analytics
    func fetchSleepData(days: Int = 7) async -> SleepData? {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return nil
        }

        let calendar = Calendar.current
        guard let startDate = calendar.date(byAdding: .day, value: -days, to: Date()) else {
            return nil
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: Date(),
            options: .strictStartDate
        )

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)]
            ) { [weak self] _, samples, _ in
                guard let self = self,
                      let categorySamples = samples as? [HKCategorySample] else {
                    continuation.resume(returning: nil)
                    return
                }

                let sleepData = self.processSleepSamples(categorySamples, days: days)
                continuation.resume(returning: sleepData)
            }
            healthStore.execute(query)
        }
    }

    private nonisolated func processSleepSamples(_ samples: [HKCategorySample], days: Int) -> SleepData? {
        // Filter for asleep states only
        let asleepSamples = samples.filter { sample in
            if #available(iOS 16.0, *) {
                return sample.value == HKCategoryValueSleepAnalysis.asleepCore.rawValue ||
                       sample.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue ||
                       sample.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue ||
                       sample.value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
            } else {
                return sample.value == HKCategoryValueSleepAnalysis.asleep.rawValue
            }
        }

        guard !asleepSamples.isEmpty else { return nil }

        // Group by night (using end date's day)
        let calendar = Calendar.current
        var sleepByNight: [Date: Double] = [:]

        for sample in asleepSamples {
            let nightDate = calendar.startOfDay(for: sample.endDate)
            let durationHours = sample.endDate.timeIntervalSince(sample.startDate) / 3600
            sleepByNight[nightDate, default: 0] += durationHours
        }

        // Create daily sleep hours array
        var dailyHours: [DailySleepHours] = []
        for dayOffset in (0..<days).reversed() {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) else { continue }
            let startOfDay = calendar.startOfDay(for: date)
            let hours = sleepByNight[startOfDay] ?? 0
            if hours > 0 {
                dailyHours.append(DailySleepHours(date: startOfDay, hours: min(hours, 24)))
            }
        }

        let totalHours = dailyHours.reduce(0) { $0 + $1.hours }
        let avgHours = dailyHours.isEmpty ? 0 : totalHours / Double(dailyHours.count)
        let quality = SleepQuality.from(hours: avgHours)

        return SleepData(
            averageDuration: avgHours,
            quality: quality,
            dailyHours: dailyHours
        )
    }

    /// Fetch resting heart rate
    func fetchRestingHeartRate() async -> Int? {
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else {
            return nil
        }

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: hrType,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, _ in
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                let bpm = Int(sample.quantity.doubleValue(for: .count().unitDivided(by: .minute())))
                continuation.resume(returning: bpm)
            }
            healthStore.execute(query)
        }
    }

    /// Fetch heart rate variability (HRV)
    func fetchHeartRateVariability() async -> Double? {
        guard let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            return nil
        }

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: hrvType,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, _ in
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                let ms = sample.quantity.doubleValue(for: .secondUnit(with: .milli))
                continuation.resume(returning: ms)
            }
            healthStore.execute(query)
        }
    }

    /// Fetch body fat percentage
    func fetchBodyFatPercentage() async -> Double? {
        guard let bodyFatType = HKQuantityType.quantityType(forIdentifier: .bodyFatPercentage) else {
            return nil
        }

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: bodyFatType,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, _ in
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                let percentage = sample.quantity.doubleValue(for: .percent()) * 100
                continuation.resume(returning: percentage)
            }
            healthStore.execute(query)
        }
    }

    /// Fetch steps history for analytics charts
    func fetchStepsHistory(days: Int = 7) async -> [DailyStepData] {
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            return []
        }

        var dailySteps: [DailyStepData] = []
        let calendar = Calendar.current

        for dayOffset in (0..<days).reversed() {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) else { continue }
            let startOfDay = calendar.startOfDay(for: date)
            guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { continue }

            let predicate = HKQuery.predicateForSamples(
                withStart: startOfDay,
                end: endOfDay,
                options: .strictStartDate
            )

            let steps = await fetchStepsForPredicate(stepType: stepType, predicate: predicate)
            dailySteps.append(DailyStepData(date: startOfDay, steps: steps))
        }

        return dailySteps
    }

    private func fetchStepsForPredicate(stepType: HKQuantityType, predicate: NSPredicate) async -> Int {
        await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: stepType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, _ in
                let steps = Int(statistics?.sumQuantity()?.doubleValue(for: .count()) ?? 0)
                continuation.resume(returning: steps)
            }
            healthStore.execute(query)
        }
    }

    /// Fetch active calories history for analytics charts
    func fetchActiveCaloriesHistory(days: Int = 7) async -> [DailyActiveCaloriesData] {
        guard let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else {
            return []
        }

        var dailyCalories: [DailyActiveCaloriesData] = []
        let calendar = Calendar.current

        for dayOffset in (0..<days).reversed() {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) else { continue }
            let startOfDay = calendar.startOfDay(for: date)
            guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { continue }

            let predicate = HKQuery.predicateForSamples(
                withStart: startOfDay,
                end: endOfDay,
                options: .strictStartDate
            )

            let calories = await fetchCaloriesForPredicate(energyType: energyType, predicate: predicate)
            dailyCalories.append(DailyActiveCaloriesData(date: startOfDay, calories: calories))
        }

        return dailyCalories
    }

    private func fetchCaloriesForPredicate(energyType: HKQuantityType, predicate: NSPredicate) async -> Int {
        await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: energyType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, _ in
                let calories = Int(statistics?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0)
                continuation.resume(returning: calories)
            }
            healthStore.execute(query)
        }
    }

    /// Fetch workouts grouped by day for analytics
    func fetchWorkoutsByDay(days: Int = 7) async -> [DayWorkoutData] {
        let calendar = Calendar.current
        guard let startDate = calendar.date(byAdding: .day, value: -days + 1, to: Date()) else {
            return []
        }

        let workouts = (try? await fetchWorkouts(from: calendar.startOfDay(for: startDate), to: Date())) ?? []
        let summaries = workouts.map { mapToWorkoutSummary($0) }

        var result: [DayWorkoutData] = []
        for dayOffset in (0..<days).reversed() {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) else { continue }
            let startOfDay = calendar.startOfDay(for: date)

            let dayWorkouts = summaries.filter { calendar.isDate($0.endTime, inSameDayAs: startOfDay) }

            result.append(DayWorkoutData(
                dayName: date.shortDayName,
                date: startOfDay,
                workoutCount: dayWorkouts.count,
                totalDuration: dayWorkouts.reduce(0) { $0 + Int($1.durationMinutes) },
                totalCalories: dayWorkouts.reduce(0) { $0 + $1.calories },
                isToday: calendar.isDateInToday(date)
            ))
        }

        return result
    }

    /// Fetch workout type distribution for analytics
    func fetchWorkoutTypeDistribution(days: Int = 7) async -> [WorkoutTypeData] {
        let calendar = Calendar.current
        guard let startDate = calendar.date(byAdding: .day, value: -days, to: Date()) else {
            return []
        }

        let workouts = (try? await fetchWorkouts(from: startDate, to: Date())) ?? []
        let summaries = workouts.map { mapToWorkoutSummary($0) }

        // Group by category
        let grouped = Dictionary(grouping: summaries, by: { $0.category })

        return grouped.map { category, workouts in
            WorkoutTypeData(
                category: category,
                count: workouts.count,
                totalMinutes: workouts.reduce(0) { $0 + Int($1.durationMinutes) },
                totalCalories: workouts.reduce(0) { $0 + $1.calories }
            )
        }.sorted { $0.count > $1.count }
    }

    // MARK: - Write Nutrition Data
    func logMealNutrition(meal: Meal, date: Date = Date()) async throws {
        var samples: [HKQuantitySample] = []

        // Calories
        if meal.calories > 0,
           let caloriesType = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed) {
            let caloriesQuantity = HKQuantity(unit: .kilocalorie(), doubleValue: Double(meal.calories))
            samples.append(HKQuantitySample(
                type: caloriesType,
                quantity: caloriesQuantity,
                start: date,
                end: date
            ))
        }

        // Protein
        if meal.protein > 0,
           let proteinType = HKQuantityType.quantityType(forIdentifier: .dietaryProtein) {
            let proteinQuantity = HKQuantity(unit: .gram(), doubleValue: Double(meal.protein))
            samples.append(HKQuantitySample(
                type: proteinType,
                quantity: proteinQuantity,
                start: date,
                end: date
            ))
        }

        // Carbs
        if meal.carbs > 0,
           let carbsType = HKQuantityType.quantityType(forIdentifier: .dietaryCarbohydrates) {
            let carbsQuantity = HKQuantity(unit: .gram(), doubleValue: Double(meal.carbs))
            samples.append(HKQuantitySample(
                type: carbsType,
                quantity: carbsQuantity,
                start: date,
                end: date
            ))
        }

        // Fat
        if meal.fat > 0,
           let fatType = HKQuantityType.quantityType(forIdentifier: .dietaryFatTotal) {
            let fatQuantity = HKQuantity(unit: .gram(), doubleValue: Double(meal.fat))
            samples.append(HKQuantitySample(
                type: fatType,
                quantity: fatQuantity,
                start: date,
                end: date
            ))
        }

        guard !samples.isEmpty else { return }

        try await healthStore.save(samples)
    }

    // MARK: - Calculate Adjusted Calories
    func calculateAdjustedCalorieTarget(
        baseTarget: Int,
        goal: GoalType
    ) async throws -> Int {
        let activeCalories = try await fetchTodayActiveCalories()
        let weight = try await fetchCurrentWeight() ?? 70.0

        // Mifflin-St Jeor base (simplified, assuming male)
        let bmr = 10 * weight + 625 // Simplified

        // Activity multiplier based on active calories
        let activityMultiplier: Double
        switch activeCalories {
        case 0..<200: activityMultiplier = 1.2
        case 200..<400: activityMultiplier = 1.4
        case 400..<600: activityMultiplier = 1.6
        default: activityMultiplier = 1.8
        }

        let tdee = bmr * activityMultiplier

        // Goal adjustment
        let goalAdjustment: Double
        switch goal {
        case .weightLoss: goalAdjustment = -500
        case .muscleGain: goalAdjustment = 300
        case .maintenance: goalAdjustment = 0
        case .keto: goalAdjustment = -300
        }

        return Int(tdee + goalAdjustment)
    }

    // MARK: - Fetch Weekly Summary
    func fetchWeeklySummary() async -> HealthWeeklySummary {
        // Run all queries in parallel for faster loading
        async let caloriesTask = fetchTodayActiveCalories()
        async let stepsTask = fetchTodaySteps()
        async let weightTask = fetchCurrentWeight()
        async let workoutsTask = fetchRecentWorkouts(days: 7)

        let activeCalories = (try? await caloriesTask) ?? 0
        let steps = (try? await stepsTask) ?? 0
        let weight = try? await weightTask
        let workouts = (try? await workoutsTask) ?? []

        return HealthWeeklySummary(
            averageActiveCalories: activeCalories,
            totalSteps: steps,
            currentWeight: weight,
            workoutCount: workouts.count,
            workoutMinutes: workouts.reduce(0) { $0 + Int($1.duration / 60) }
        )
    }

    // MARK: - Quick Today Summary (for TodayView)
    func fetchTodayActivitySummary() async -> TodayActivitySummary {
        // Run queries in parallel for faster loading
        async let caloriesTask = fetchTodayActiveCalories()
        async let stepsTask = fetchTodaySteps()

        let activeCalories = (try? await caloriesTask) ?? 0
        let steps = (try? await stepsTask) ?? 0

        return TodayActivitySummary(
            activeCalories: Int(activeCalories),
            steps: steps
        )
    }
}

// MARK: - Today Activity Summary
struct TodayActivitySummary {
    let activeCalories: Int
    let steps: Int

    var hasData: Bool {
        activeCalories > 0 || steps > 0
    }
}

// MARK: - Health Profile Data (for onboarding pre-fill)
struct HealthProfileData {
    let height: Double?  // in cm
    let weight: Double?  // in kg
    let age: Int?

    var hasAnyData: Bool {
        height != nil || weight != nil || age != nil
    }
}

// MARK: - Health Summary
struct HealthWeeklySummary {
    let averageActiveCalories: Double
    let totalSteps: Int
    let currentWeight: Double?
    let workoutCount: Int
    let workoutMinutes: Int
}

// MARK: - Errors
enum HealthKitError: LocalizedError {
    case notAvailable
    case notAuthorized
    case dataNotFound
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Health data is not available on this device"
        case .notAuthorized:
            return "Health data access not authorized"
        case .dataNotFound:
            return "Requested health data not found"
        case .saveFailed(let reason):
            return "Failed to save health data: \(reason)"
        }
    }
}

// MARK: - HealthKit View
import SwiftUI

struct HealthKitConnectionView: View {
    @State private var healthService = HealthKitService.shared
    @State private var isLoading = false
    @State private var summary: HealthWeeklySummary?
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                if healthService.isHealthDataAvailable {
                    if healthService.isAuthorized {
                        HStack {
                            Label("Connected to Health", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Spacer()
                            if isLoading {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }
                    } else {
                        Button(action: requestAuthorization) {
                            HStack {
                                Label("Connect to Health", systemImage: "heart.fill")
                                Spacer()
                                if isLoading {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .disabled(isLoading)
                    }
                } else {
                    Label("Health not available", systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                }
            } footer: {
                if !healthService.isAuthorized && healthService.isHealthDataAvailable {
                    Text("Connect to Apple Health to sync your activity data and get personalized calorie recommendations.")
                }
            }

            if let summary = summary {
                Section("Today's Activity") {
                    HStack {
                        Label("Active Calories", systemImage: "flame.fill")
                            .foregroundStyle(.orange)
                        Spacer()
                        Text("\(Int(summary.averageActiveCalories)) kcal")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Label("Steps", systemImage: "figure.walk")
                            .foregroundStyle(.green)
                        Spacer()
                        Text("\(summary.totalSteps)")
                            .foregroundStyle(.secondary)
                    }

                    if let weight = summary.currentWeight {
                        HStack {
                            Label("Weight", systemImage: "scalemass.fill")
                                .foregroundStyle(.blue)
                            Spacer()
                            Text(String(format: "%.1f kg", weight))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("This Week") {
                    HStack {
                        Label("Workouts", systemImage: "figure.run")
                            .foregroundStyle(.pink)
                        Spacer()
                        Text("\(summary.workoutCount)")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Label("Exercise Minutes", systemImage: "timer")
                            .foregroundStyle(.cyan)
                        Spacer()
                        Text("\(summary.workoutMinutes) min")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if healthService.isAuthorized {
                Section {
                    Text("Your activity data is used to adjust your daily calorie target based on how active you are.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let error = errorMessage {
                Section {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(.caption)
                    }

                    Button("Try Again") {
                        errorMessage = nil
                        requestAuthorization()
                    }
                }
            }
        }
        .navigationTitle("Health Integration")
        .onAppear {
            healthService.checkAuthorizationStatus()
        }
        .task {
            if healthService.isAuthorized {
                await loadSummary()
            }
        }
    }

    private func requestAuthorization() {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        Task {
            do {
                try await healthService.requestAuthorization()
                await loadSummary()
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func loadSummary() async {
        isLoading = true
        summary = await healthService.fetchWeeklySummary()
        isLoading = false
    }
}
