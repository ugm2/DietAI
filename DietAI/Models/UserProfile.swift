import Foundation
import SwiftData

// MARK: - User Profile Model
@Model
final class UserProfile {
    var id: UUID
    var appleUserIdentifier: String?
    var email: String?
    var displayName: String?
    var createdAt: Date
    var lastLoginAt: Date

    // Physical attributes
    var height: Double? // cm
    var weight: Double? // kg
    var age: Int?
    var activityLevelRaw: String?

    // Goals
    var preferredGoalRaw: String?
    var dailyCalorieTarget: Int?

    // Dietary preferences
    var dietaryRestrictions: [String]
    var preferredCuisines: [String]
    var dislikedIngredients: [String]
    var lovedIngredients: [String]

    // Health integration consent
    var healthKitConsentGiven: Bool
    var healthKitConsentDate: Date?

    // Cloud sync metadata
    var cloudKitRecordID: String?
    var lastSyncedAt: Date?
    var needsSync: Bool

    // NEW: Plan preference defaults
    var defaultPrepTimeMinutes: Int
    var defaultDifficultyRaw: String
    var defaultBudgetRaw: String
    var prefersBatchCooking: Bool
    var planNotes: String?

    // Preferred meal types (CSV format, defaults to all)
    var selectedMealTypesRaw: String = "Breakfast,Brunch,Lunch,Snack,Dinner"

    // NEW: Onboarding completion
    var hasCompletedOnboarding: Bool

    // Relationships
    @Relationship(deleteRule: .cascade) var dietPlans: [DietPlan]?

    init(
        appleUserIdentifier: String? = nil,
        email: String? = nil,
        displayName: String? = nil
    ) {
        self.id = UUID()
        self.appleUserIdentifier = appleUserIdentifier
        self.email = email
        self.displayName = displayName
        self.createdAt = Date()
        self.lastLoginAt = Date()
        self.dietaryRestrictions = []
        self.preferredCuisines = []
        self.dislikedIngredients = []
        self.lovedIngredients = []
        self.healthKitConsentGiven = false
        self.needsSync = false
        // New defaults
        self.defaultPrepTimeMinutes = 30
        self.defaultDifficultyRaw = MealDifficulty.easy.rawValue
        self.defaultBudgetRaw = BudgetLevel.moderate.rawValue
        self.prefersBatchCooking = false
        self.planNotes = nil
        self.hasCompletedOnboarding = false
    }

    // Computed properties for new fields
    var defaultDifficulty: MealDifficulty {
        get { MealDifficulty(rawValue: defaultDifficultyRaw) ?? .easy }
        set { defaultDifficultyRaw = newValue.rawValue }
    }

    var defaultBudget: BudgetLevel {
        get { BudgetLevel(rawValue: defaultBudgetRaw) ?? .moderate }
        set { defaultBudgetRaw = newValue.rawValue }
    }

    /// Preferred meal types for plan generation
    var selectedMealTypes: Set<MealType> {
        get {
            Set(selectedMealTypesRaw.split(separator: ",")
                .compactMap { MealType(rawValue: String($0)) })
        }
        set {
            selectedMealTypesRaw = newValue
                .sorted { $0.sortOrder < $1.sortOrder }
                .map { $0.rawValue }
                .joined(separator: ",")
        }
    }

    // Computed properties
    var activityLevel: ActivityLevel? {
        get {
            guard let raw = activityLevelRaw else { return nil }
            return ActivityLevel(rawValue: raw)
        }
        set {
            activityLevelRaw = newValue?.rawValue
        }
    }

    var preferredGoal: GoalType? {
        get {
            guard let raw = preferredGoalRaw else { return nil }
            return GoalType(rawValue: raw)
        }
        set {
            preferredGoalRaw = newValue?.rawValue
        }
    }

    // Convenience aliases for cleaner API
    var goalType: GoalType? { preferredGoal }
    var goal: String { preferredGoal?.rawValue ?? "healthy eating" }
    var dietaryRestrictionsArray: [String] { dietaryRestrictions }

    // Calculate BMR using Mifflin-St Jeor equation
    func calculateBMR(isMale: Bool = true) -> Double? {
        guard let weight = weight, let height = height, let age = age else {
            return nil
        }
        if isMale {
            return 10 * weight + 6.25 * height - 5 * Double(age) + 5
        } else {
            return 10 * weight + 6.25 * height - 5 * Double(age) - 161
        }
    }

    // Calculate TDEE (Total Daily Energy Expenditure)
    func calculateTDEE(isMale: Bool = true) -> Double? {
        guard let bmr = calculateBMR(isMale: isMale),
              let activity = activityLevel else {
            return nil
        }
        return bmr * activity.multiplier
    }

    // Recommended calories based on goal
    func recommendedCalories(isMale: Bool = true) -> Int? {
        guard let tdee = calculateTDEE(isMale: isMale) else { return nil }

        switch preferredGoal {
        case .weightLoss:
            return Int(tdee * 0.8) // 20% deficit
        case .muscleGain:
            return Int(tdee * 1.1) // 10% surplus
        case .maintenance:
            return Int(tdee)
        case .keto:
            return Int(tdee * 0.85) // Slight deficit
        case .none:
            return Int(tdee)
        }
    }
}

