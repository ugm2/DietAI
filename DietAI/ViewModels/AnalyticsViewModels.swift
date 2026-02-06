import Foundation
import SwiftUI
import SwiftData

// MARK: - Main Analytics ViewModel
@MainActor
@Observable
class AnalyticsViewModel {
    let mealAnalytics = MealAnalyticsViewModel()
    let workoutAnalytics = WorkoutAnalyticsViewModel()
    let healthAnalytics = HealthAnalyticsViewModel()

    private(set) var isLoading = false

    func loadData(for timeRange: AnalyticsTimeRange, mealLogs: [MealLog], userProfile: UserProfile?) async {
        isLoading = true

        // Load all data in parallel
        async let mealsTask: () = mealAnalytics.loadData(for: timeRange, mealLogs: mealLogs, userProfile: userProfile)
        async let workoutsTask: () = workoutAnalytics.loadData(for: timeRange)
        async let healthTask: () = healthAnalytics.loadData(for: timeRange, userProfile: userProfile)

        _ = await (mealsTask, workoutsTask, healthTask)

        isLoading = false
    }
}

// MARK: - Meal Analytics ViewModel
@MainActor
@Observable
class MealAnalyticsViewModel {
    private(set) var dailyCalories: [DailyCalorieData] = []
    private(set) var totalProtein: Int = 0
    private(set) var totalCarbs: Int = 0
    private(set) var totalFat: Int = 0
    private(set) var caloriesByMealType: [MealTypeCalorieData] = []
    private(set) var frequentMeals: [FrequentMeal] = []
    private(set) var loggingStreak: Int = 0
    private(set) var averageCalories: Int = 0
    private(set) var calorieTarget: Int = 2000
    private(set) var totalCalories: Int = 0

    func loadData(for timeRange: AnalyticsTimeRange, mealLogs: [MealLog], userProfile: UserProfile?) async {
        let calendar = Calendar.current
        let days = timeRange.days
        let startDate = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: Date())) ?? Date()

        // Filter logs for time range
        let filteredLogs = mealLogs.filter { $0.loggedAt >= startDate }

        // Set calorie target from user profile
        calorieTarget = userProfile?.dailyCalorieTarget ?? 2000

        // Calculate daily calories
        calculateDailyCalories(logs: filteredLogs, days: days)

        // Calculate totals
        totalCalories = filteredLogs.reduce(0) { $0 + $1.calories }
        totalProtein = filteredLogs.reduce(0) { $0 + $1.protein }
        totalCarbs = filteredLogs.reduce(0) { $0 + $1.carbs }
        totalFat = filteredLogs.reduce(0) { $0 + $1.fat }

        // Calculate average calories per day
        let daysWithLogs = Set(filteredLogs.map { calendar.startOfDay(for: $0.loggedAt) }).count
        averageCalories = daysWithLogs > 0 ? totalCalories / daysWithLogs : 0

        // Calculate calories by meal type
        calculateCaloriesByMealType(logs: filteredLogs)

        // Calculate frequent meals
        calculateFrequentMeals(logs: filteredLogs)

        // Calculate logging streak
        calculateLoggingStreak(allLogs: mealLogs)
    }

    private func calculateDailyCalories(logs: [MealLog], days: Int) {
        let calendar = Calendar.current
        var result: [DailyCalorieData] = []

        for dayOffset in (0..<days).reversed() {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) else { continue }
            let startOfDay = calendar.startOfDay(for: date)

            let dayLogs = logs.filter { calendar.isDate($0.loggedAt, inSameDayAs: startOfDay) }

            let calories = dayLogs.reduce(0) { $0 + $1.calories }
            let protein = dayLogs.reduce(0) { $0 + $1.protein }
            let carbs = dayLogs.reduce(0) { $0 + $1.carbs }
            let fat = dayLogs.reduce(0) { $0 + $1.fat }

            result.append(DailyCalorieData(
                date: startOfDay,
                calories: calories,
                protein: protein,
                carbs: carbs,
                fat: fat
            ))
        }

        dailyCalories = result
    }

    private func calculateCaloriesByMealType(logs: [MealLog]) {
        let grouped = Dictionary(grouping: logs, by: { $0.mealType })

        caloriesByMealType = MealType.allCases.compactMap { mealType in
            let typeLogs = grouped[mealType] ?? []
            guard !typeLogs.isEmpty else { return nil }

            let total = typeLogs.reduce(0) { $0 + $1.calories }
            let avg = total / typeLogs.count

            return MealTypeCalorieData(
                mealType: mealType,
                totalCalories: total,
                averageCalories: avg,
                count: typeLogs.count
            )
        }.sorted { $0.totalCalories > $1.totalCalories }
    }

    private func calculateFrequentMeals(logs: [MealLog]) {
        // Group by meal name (case-insensitive)
        let grouped = Dictionary(grouping: logs, by: { $0.mealName.lowercased() })

        frequentMeals = grouped.map { name, logs in
            let avgCalories = logs.reduce(0) { $0 + $1.calories } / logs.count
            let displayName = logs.first?.mealName ?? name.capitalized

            return FrequentMeal(
                name: displayName,
                count: logs.count,
                avgCalories: avgCalories
            )
        }
        .filter { $0.count >= 2 }
        .sorted { $0.count > $1.count }
        .prefix(5)
        .map { $0 }
    }

    private func calculateLoggingStreak(allLogs: [MealLog]) {
        let calendar = Calendar.current
        var streak = 0
        var checkDate = calendar.startOfDay(for: Date())

        while true {
            let hasLogsForDay = allLogs.contains { log in
                calendar.isDate(log.loggedAt, inSameDayAs: checkDate)
            }

            if hasLogsForDay {
                streak += 1
                guard let previousDay = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
                checkDate = previousDay
            } else {
                break
            }
        }

        loggingStreak = streak
    }
}

// MARK: - Workout Analytics ViewModel
@MainActor
@Observable
class WorkoutAnalyticsViewModel {
    private let healthService = HealthKitService.shared

    private(set) var totalWorkouts: Int = 0
    private(set) var totalCaloriesBurned: Int = 0
    private(set) var workoutsByDay: [DayWorkoutData] = []
    private(set) var workoutsByType: [WorkoutTypeData] = []
    private(set) var dailyActiveCalories: [DailyActiveCaloriesData] = []
    private(set) var dailySteps: [DailyStepData] = []
    private(set) var mostActiveDay: String?
    private(set) var averageWorkoutDuration: Int = 0
    private(set) var totalSteps: Int = 0

    func loadData(for timeRange: AnalyticsTimeRange) async {
        let days = timeRange.days

        // Load all data in parallel
        async let workoutsByDayTask = healthService.fetchWorkoutsByDay(days: days)
        async let workoutTypesTask = healthService.fetchWorkoutTypeDistribution(days: days)
        async let caloriesTask = healthService.fetchActiveCaloriesHistory(days: days)
        async let stepsTask = healthService.fetchStepsHistory(days: days)

        workoutsByDay = await workoutsByDayTask
        workoutsByType = await workoutTypesTask
        dailyActiveCalories = await caloriesTask
        dailySteps = await stepsTask

        // Calculate aggregates
        totalWorkouts = workoutsByDay.reduce(0) { $0 + $1.workoutCount }
        totalCaloriesBurned = workoutsByDay.reduce(0) { $0 + $1.totalCalories }
        totalSteps = dailySteps.reduce(0) { $0 + $1.steps }

        // Find most active day
        if let maxDay = workoutsByDay.max(by: { $0.totalCalories < $1.totalCalories }), maxDay.totalCalories > 0 {
            mostActiveDay = maxDay.dayName
        }

        // Calculate average workout duration
        let totalDuration = workoutsByDay.reduce(0) { $0 + $1.totalDuration }
        averageWorkoutDuration = totalWorkouts > 0 ? totalDuration / totalWorkouts : 0
    }
}

// MARK: - Health Analytics ViewModel
@MainActor
@Observable
class HealthAnalyticsViewModel {
    private let healthService = HealthKitService.shared

    private(set) var currentWeight: Double?
    private(set) var currentBMI: Double?
    private(set) var weightHistory: [WeightDataPoint] = []
    private(set) var weightTrend: TrendDirection = .stable
    private(set) var hasWeightData: Bool = false
    private(set) var goalWeight: Double?

    // Sleep
    private(set) var sleepData: SleepData?
    private(set) var hasSleepPermission: Bool = true

    // Heart rate
    private(set) var restingHeartRate: Int?
    private(set) var heartRateVariability: Double?
    private(set) var hasHeartRatePermission: Bool = true

    // Body composition
    private(set) var bodyFatPercentage: Double?

    // Permission states
    private(set) var hasAllHealthPermissions: Bool = true
    private(set) var missingPermissions: [HealthPermission] = []

    func loadData(for timeRange: AnalyticsTimeRange, userProfile: UserProfile?) async {
        let days = timeRange.days

        // Goal weight could be stored in profile or calculated from goal type
        // For now, we'll calculate a target based on the user's goal and current weight
        // This can be extended later to store a specific goal weight
        goalWeight = nil

        // Load all health data in parallel
        async let weightTask = healthService.fetchCurrentWeight()
        async let weightHistoryTask = healthService.fetchWeightHistory(days: days)
        async let sleepTask = healthService.fetchSleepData(days: days)
        async let hrTask = healthService.fetchRestingHeartRate()
        async let hrvTask = healthService.fetchHeartRateVariability()
        async let bodyFatTask = healthService.fetchBodyFatPercentage()
        async let heightTask = healthService.fetchCurrentHeight()

        currentWeight = try? await weightTask
        weightHistory = await weightHistoryTask
        sleepData = await sleepTask
        restingHeartRate = await hrTask
        heartRateVariability = await hrvTask
        bodyFatPercentage = await bodyFatTask
        let height = try? await heightTask

        // Calculate BMI
        if let weight = currentWeight, let heightCm = height ?? userProfile?.height, heightCm > 0 {
            let heightM = heightCm / 100
            currentBMI = weight / (heightM * heightM)
        }

        // Determine weight trend
        calculateWeightTrend()

        hasWeightData = !weightHistory.isEmpty

        // Check permission states based on data availability
        updatePermissionStates()
    }

    private func calculateWeightTrend() {
        guard weightHistory.count >= 2 else {
            weightTrend = .stable
            return
        }

        let firstWeight = weightHistory.first!.weight
        let lastWeight = weightHistory.last!.weight

        let change = lastWeight - firstWeight
        let percentChange = abs(change / firstWeight) * 100

        if percentChange < 0.5 {
            weightTrend = .stable
        } else if change > 0 {
            weightTrend = .up(percentChange)
        } else {
            weightTrend = .down(percentChange)
        }
    }

    private func updatePermissionStates() {
        missingPermissions = []

        // If we requested permissions but got no data, it might be denied
        // However, HealthKit doesn't tell us directly, so we assume permission granted
        // but no data recorded yet

        hasSleepPermission = true
        hasHeartRatePermission = true
        hasAllHealthPermissions = true
    }

    func requestMissingPermissions() async {
        // Re-request authorization (this will show the HealthKit permission sheet)
        try? await healthService.requestAuthorization()
    }
}
