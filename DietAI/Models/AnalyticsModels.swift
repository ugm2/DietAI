import Foundation
import SwiftUI

// MARK: - Time Range
enum AnalyticsTimeRange: String, CaseIterable {
    case day = "Today"
    case week = "Week"
    case month = "Month"

    var days: Int {
        switch self {
        case .day: return 1
        case .week: return 7
        case .month: return 30
        }
    }
}

// MARK: - Section Selection
enum AnalyticsSection: String, CaseIterable {
    case meals = "Meals"
    case workouts = "Workouts"
    case health = "Health"

    var icon: String {
        switch self {
        case .meals: return "fork.knife"
        case .workouts: return "figure.run"
        case .health: return "heart.fill"
        }
    }

    var color: Color {
        switch self {
        case .meals: return .orange
        case .workouts: return .green
        case .health: return .red
        }
    }
}

// MARK: - Meal Analytics Data
struct DailyCalorieData: Identifiable {
    let id = UUID()
    let date: Date
    let calories: Int
    let protein: Int
    let carbs: Int
    let fat: Int

    init(date: Date, calories: Int, protein: Int = 0, carbs: Int = 0, fat: Int = 0) {
        self.date = date
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
    }
}

struct MacroData: Identifiable {
    let id = UUID()
    let name: String
    let value: Double
    let color: Color

    var percentage: Double {
        // This will be calculated relative to total
        value
    }
}

struct MealTypeCalorieData: Identifiable {
    let id = UUID()
    let mealType: MealType
    let totalCalories: Int
    let averageCalories: Int
    let count: Int

    var displayName: String {
        mealType.rawValue.capitalized
    }
}

struct FrequentMeal: Identifiable {
    let id = UUID()
    let name: String
    let count: Int
    let avgCalories: Int
}

// MARK: - Workout Analytics Data
struct DayWorkoutData: Identifiable {
    let id = UUID()
    let dayName: String
    let date: Date
    let workoutCount: Int
    let totalDuration: Int
    let totalCalories: Int
    let isToday: Bool
}

struct WorkoutTypeData: Identifiable {
    let id = UUID()
    let category: WorkoutCategory
    let count: Int
    let totalMinutes: Int
    let totalCalories: Int

    var displayName: String {
        category.rawValue
    }

    var color: Color {
        switch category {
        case .strength: return .red
        case .cardio: return .blue
        case .hiit: return .orange
        case .yoga: return .purple
        case .endurance: return .green
        case .sports: return .cyan
        case .mixed: return .gray
        case .recovery: return .mint
        }
    }
}

struct DailyStepData: Identifiable {
    let id = UUID()
    let date: Date
    let steps: Int
}

struct DailyActiveCaloriesData: Identifiable {
    let id = UUID()
    let date: Date
    let calories: Int
}

// MARK: - Health Analytics Data
struct WeightDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let weight: Double
}

struct SleepData {
    let averageDuration: Double
    let quality: SleepQuality
    let dailyHours: [DailySleepHours]
}

struct DailySleepHours: Identifiable {
    let id = UUID()
    let date: Date
    let hours: Double
}

enum SleepQuality: String {
    case poor = "Poor"
    case fair = "Fair"
    case good = "Good"
    case excellent = "Excellent"

    var color: Color {
        switch self {
        case .poor: return .red
        case .fair: return .orange
        case .good: return .green
        case .excellent: return .blue
        }
    }

    var icon: String {
        switch self {
        case .poor: return "moon.zzz"
        case .fair: return "moon"
        case .good: return "moon.fill"
        case .excellent: return "sparkles"
        }
    }

    nonisolated static func from(hours: Double) -> SleepQuality {
        switch hours {
        case ..<6: return .poor
        case 6..<7: return .fair
        case 7..<8: return .good
        default: return .excellent
        }
    }
}

enum TrendDirection {
    case up(Double)
    case down(Double)
    case stable

    var icon: String {
        switch self {
        case .up: return "arrow.up.right"
        case .down: return "arrow.down.right"
        case .stable: return "arrow.right"
        }
    }

    var color: Color {
        switch self {
        case .up: return .green
        case .down: return .red
        case .stable: return .gray
        }
    }

    /// For weight, down is good (if losing weight is the goal)
    var weightColor: Color {
        switch self {
        case .up: return .red
        case .down: return .green
        case .stable: return .gray
        }
    }

    var percentageText: String {
        switch self {
        case .up(let pct): return String(format: "+%.1f%%", pct)
        case .down(let pct): return String(format: "-%.1f%%", pct)
        case .stable: return "0%"
        }
    }
}

// MARK: - Health Permissions
enum HealthPermission: String, CaseIterable {
    case sleep = "Sleep"
    case heartRate = "Heart Rate"
    case hrv = "Heart Rate Variability"
    case bodyFat = "Body Fat"
    case vo2Max = "VO2 Max"

    var description: String {
        switch self {
        case .sleep: return "Track sleep duration and quality"
        case .heartRate: return "Monitor resting heart rate"
        case .hrv: return "Measure recovery and stress levels"
        case .bodyFat: return "Track body composition changes"
        case .vo2Max: return "Measure cardiorespiratory fitness"
        }
    }

    var icon: String {
        switch self {
        case .sleep: return "bed.double.fill"
        case .heartRate: return "heart.fill"
        case .hrv: return "waveform.path.ecg"
        case .bodyFat: return "figure.stand"
        case .vo2Max: return "lungs.fill"
        }
    }
}

// MARK: - BMI Helpers
enum BMICategory: String {
    case underweight = "Underweight"
    case normal = "Normal"
    case overweight = "Overweight"
    case obese = "Obese"

    var color: Color {
        switch self {
        case .underweight: return .blue
        case .normal: return .green
        case .overweight: return .orange
        case .obese: return .red
        }
    }

    static func from(bmi: Double) -> BMICategory {
        switch bmi {
        case ..<18.5: return .underweight
        case 18.5..<25: return .normal
        case 25..<30: return .overweight
        default: return .obese
        }
    }
}

// MARK: - Helper Extensions
extension Date {
    var shortDayName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: self)
    }

    var isToday: Bool {
        Calendar.current.isDateInToday(self)
    }
}
