import Foundation
import HealthKit

// MARK: - Workout Category
enum WorkoutCategory: String, Codable, CaseIterable {
    case strength = "Strength"
    case cardio = "Cardio"
    case hiit = "HIIT"
    case yoga = "Yoga"
    case endurance = "Endurance"
    case sports = "Sports"
    case mixed = "Mixed"
    case recovery = "Recovery"

    /// Map HKWorkoutActivityType to our simplified categories
    static func from(_ activityType: HKWorkoutActivityType) -> WorkoutCategory {
        switch activityType {
        case .traditionalStrengthTraining, .functionalStrengthTraining, .coreTraining:
            return .strength
        case .running, .cycling, .swimming, .rowing, .elliptical, .stairClimbing, .stepTraining:
            return .cardio
        case .highIntensityIntervalTraining, .crossTraining, .mixedCardio:
            return .hiit
        case .yoga, .pilates, .flexibility, .mindAndBody:
            return .yoga
        case .walking, .hiking:
            return .endurance
        case .soccer, .basketball, .tennis, .volleyball, .golf, .badminton, .tableTennis, .racquetball, .squash:
            return .sports
        case .cooldown, .preparationAndRecovery:
            return .recovery
        default:
            return .mixed
        }
    }

    /// How much of burned calories to eat back (recovery multiplier)
    var calorieRecoveryMultiplier: Double {
        switch self {
        case .strength: return 0.7    // Need more for muscle repair
        case .cardio: return 0.5      // Standard recovery
        case .hiit: return 0.65       // Higher due to EPOC effect
        case .yoga: return 0.3        // Lower caloric demand
        case .endurance: return 0.6   // Moderate recovery
        case .sports: return 0.55     // Variable intensity
        case .mixed: return 0.55      // Average
        case .recovery: return 0.25   // Minimal
        }
    }

    /// Extra protein per kg bodyweight for this workout type
    var proteinBoostPerKg: Double {
        switch self {
        case .strength: return 0.3    // +0.3g/kg extra protein
        case .hiit: return 0.2        // +0.2g/kg
        case .cardio: return 0.1      // +0.1g/kg
        case .endurance: return 0.15  // +0.15g/kg
        case .sports: return 0.15     // +0.15g/kg
        case .mixed: return 0.15      // +0.15g/kg
        case .yoga: return 0.0        // No boost
        case .recovery: return 0.0    // No boost
        }
    }

    /// Carbohydrate emphasis level
    var carbEmphasis: CarbEmphasis {
        switch self {
        case .strength: return .moderate
        case .cardio: return .high
        case .hiit: return .high
        case .endurance: return .veryHigh
        case .yoga: return .low
        case .sports: return .high
        case .mixed: return .moderate
        case .recovery: return .low
        }
    }

    /// Recovery window in hours (when extra protein matters most)
    var recoveryWindowHours: Int {
        switch self {
        case .strength: return 2
        case .hiit: return 2
        case .cardio: return 1
        case .endurance: return 3
        default: return 1
        }
    }

    /// SF Symbol icon name
    var icon: String {
        switch self {
        case .strength: return "figure.strengthtraining.traditional"
        case .cardio: return "figure.run"
        case .hiit: return "bolt.heart.fill"
        case .yoga: return "figure.yoga"
        case .endurance: return "figure.hiking"
        case .sports: return "sportscourt.fill"
        case .mixed: return "figure.mixed.cardio"
        case .recovery: return "figure.walk"
        }
    }
}

// MARK: - Carb Emphasis
enum CarbEmphasis: String, Codable {
    case veryHigh = "Very High"
    case high = "High"
    case moderate = "Moderate"
    case low = "Low"
}

// MARK: - Workout Intensity
enum WorkoutIntensity: String, Codable, CaseIterable {
    case light = "Light"
    case moderate = "Moderate"
    case vigorous = "Vigorous"
    case extreme = "Extreme"

    /// Derive intensity from calories burned per minute
    static func from(caloriesPerMinute: Double) -> WorkoutIntensity {
        switch caloriesPerMinute {
        case 0..<5: return .light
        case 5..<8: return .moderate
        case 8..<12: return .vigorous
        default: return .extreme
        }
    }

    /// Multiplier for calorie adjustments based on intensity
    var intensityMultiplier: Double {
        switch self {
        case .light: return 0.8
        case .moderate: return 1.0
        case .vigorous: return 1.2
        case .extreme: return 1.4
        }
    }
}

// MARK: - Workout Summary
struct WorkoutSummary: Identifiable, Codable {
    let id: UUID
    let category: WorkoutCategory
    let intensity: WorkoutIntensity
    let durationMinutes: Double
    let calories: Int
    let endTime: Date

    init(id: UUID = UUID(), category: WorkoutCategory, intensity: WorkoutIntensity, durationMinutes: Double, calories: Int, endTime: Date) {
        self.id = id
        self.category = category
        self.intensity = intensity
        self.durationMinutes = durationMinutes
        self.calories = calories
        self.endTime = endTime
    }

    /// Hours since workout ended
    var hoursAgo: Double {
        Date().timeIntervalSince(endTime) / 3600
    }

    /// Whether we're still in the optimal recovery window
    var isInRecoveryWindow: Bool {
        hoursAgo < Double(category.recoveryWindowHours)
    }

    /// Calculated calorie bonus for this workout
    var calorieBonus: Int {
        let base = Double(calories) * category.calorieRecoveryMultiplier
        return Int(base * intensity.intensityMultiplier)
    }
}

// MARK: - Weekly Activity Trend
struct WeeklyActivityTrend: Codable {
    let workoutDays: Int
    let totalWorkoutMinutes: Int
    let strengthDays: Int
    let cardioDays: Int
    let dominantCategory: WorkoutCategory?

    /// Overall activity level based on workout frequency
    var activityLevel: ActivityTrendLevel {
        switch workoutDays {
        case 0: return .sedentary
        case 1...2: return .lightlyActive
        case 3...4: return .moderatelyActive
        case 5...6: return .veryActive
        default: return .extremelyActive
        }
    }

    static var empty: WeeklyActivityTrend {
        WeeklyActivityTrend(
            workoutDays: 0,
            totalWorkoutMinutes: 0,
            strengthDays: 0,
            cardioDays: 0,
            dominantCategory: nil
        )
    }
}

// MARK: - Activity Trend Level
enum ActivityTrendLevel: String, Codable {
    case sedentary = "Sedentary"
    case lightlyActive = "Lightly Active"
    case moderatelyActive = "Moderately Active"
    case veryActive = "Very Active"
    case extremelyActive = "Extremely Active"

    /// Weekly calorie multiplier based on activity trend
    var weeklyCalorieMultiplier: Double {
        switch self {
        case .sedentary: return 1.0
        case .lightlyActive: return 1.1
        case .moderatelyActive: return 1.2
        case .veryActive: return 1.35
        case .extremelyActive: return 1.5
        }
    }
}

// MARK: - Enhanced Activity Summary
struct EnhancedActivitySummary {
    let date: Date
    let activeCalories: Int
    let steps: Int
    let workouts: [WorkoutSummary]
    let weeklyTrend: WeeklyActivityTrend

    /// Total calories from all workouts today
    var totalWorkoutCalories: Int {
        workouts.reduce(0) { $0 + $1.calories }
    }

    /// Most common workout type today
    var dominantWorkoutCategory: WorkoutCategory? {
        guard !workouts.isEmpty else { return nil }
        let grouped = Dictionary(grouping: workouts, by: { $0.category })
        return grouped.max(by: { $0.value.count < $1.value.count })?.key
    }

    /// Check if any strength workout is in recovery window
    var hasActiveRecoveryWindow: Bool {
        workouts.contains { $0.category == .strength && $0.isInRecoveryWindow }
    }

    /// Whether this is a rest day (no workouts, low steps)
    var isRecoveryDay: Bool {
        workouts.isEmpty && steps < 5000
    }

    /// Total calorie bonus from all workouts
    var totalCalorieBonus: Int {
        workouts.reduce(0) { $0 + $1.calorieBonus }
    }

    /// Accumulated protein boost from all workouts (g per kg bodyweight)
    var totalProteinBoostPerKg: Double {
        workouts.reduce(0.0) { $0 + $1.category.proteinBoostPerKg }
    }

    static var empty: EnhancedActivitySummary {
        EnhancedActivitySummary(
            date: Date(),
            activeCalories: 0,
            steps: 0,
            workouts: [],
            weeklyTrend: .empty
        )
    }
}

// MARK: - Smart Calorie Target
struct SmartCalorieTarget {
    let base: Int
    let workoutBonus: Int
    let trendBonus: Int
    let proteinBoostPerKg: Double
    let recoveryWindowActive: Bool
    let dominantWorkoutCategory: WorkoutCategory?

    /// Total adjusted calorie target (trend bonus only applies on workout days)
    var total: Int { base + workoutBonus + (workoutBonus > 0 ? trendBonus : 0) }

    /// Human-readable explanation of the calorie adjustment
    var explanation: String {
        var parts: [String] = []
        parts.append("Base target: \(base) kcal")
        if workoutBonus > 0 {
            parts.append("Workout bonus: +\(workoutBonus) kcal")
        }
        if trendBonus > 0 {
            parts.append("Weekly activity trend: +\(trendBonus) kcal")
        }
        return parts.joined(separator: "\n")
    }

    /// Extra protein recommendation in grams (requires weight in kg)
    func extraProteinGrams(weightKg: Double) -> Int {
        Int(proteinBoostPerKg * weightKg)
    }
}

// MARK: - Activity Prompt Context (for AI)
struct ActivityPromptContext {
    let todayWorkouts: [WorkoutSummary]
    let weeklyTrend: WeeklyActivityTrend
    let isRecoveryWindowActive: Bool
    let proteinBoostNeeded: Double
    let dominantCategory: WorkoutCategory?

    /// Generate prompt description for AI meal generation
    var promptDescription: String {
        var parts: [String] = []

        // Today's activity
        if !todayWorkouts.isEmpty {
            let workoutDescriptions = todayWorkouts.map { workout in
                "\(workout.category.rawValue) (\(Int(workout.durationMinutes)) min, \(workout.intensity.rawValue) intensity)"
            }
            parts.append("Today's workouts: \(workoutDescriptions.joined(separator: ", "))")

            if isRecoveryWindowActive {
                parts.append("Currently in post-workout recovery window - prioritize high-protein meal (25-30g+)")
            }
        }

        // Weekly context
        if weeklyTrend.workoutDays > 0 {
            parts.append("Weekly activity: \(weeklyTrend.workoutDays) workout days, \(weeklyTrend.totalWorkoutMinutes) total minutes")
        }

        if let dominant = dominantCategory {
            parts.append("Primary training focus: \(dominant.rawValue)")
        }

        // Specific guidance based on workout type
        if let dominant = dominantCategory ?? weeklyTrend.dominantCategory {
            switch dominant {
            case .strength:
                parts.append("Nutrition emphasis: High protein (30g+ per main meal) for muscle recovery, moderate carbs for glycogen")
            case .cardio, .hiit:
                parts.append("Nutrition emphasis: Adequate carbs for glycogen replenishment, lean protein for recovery")
            case .endurance:
                parts.append("Nutrition emphasis: Complex carbs for sustained energy, moderate protein, electrolyte-rich foods")
            case .yoga, .recovery:
                parts.append("Nutrition emphasis: Light, easily digestible foods, anti-inflammatory ingredients")
            default:
                parts.append("Nutrition emphasis: Balanced macros for general fitness")
            }
        }

        if proteinBoostNeeded > 0 {
            parts.append("Extra protein recommended today: +\(Int(proteinBoostNeeded * 70))g (assuming 70kg bodyweight)")
        }

        return parts.isEmpty ? "No specific activity context" : parts.joined(separator: "\n")
    }

    static var empty: ActivityPromptContext {
        ActivityPromptContext(
            todayWorkouts: [],
            weeklyTrend: .empty,
            isRecoveryWindowActive: false,
            proteinBoostNeeded: 0,
            dominantCategory: nil
        )
    }
}
