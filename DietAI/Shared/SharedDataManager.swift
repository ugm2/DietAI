import Foundation

// MARK: - Shared Data Manager (For Widgets & Watch)
public final class SharedDataManager {
    public static let shared = SharedDataManager()

    public let appGroupIdentifier = "group.com.garay.DietAI"

    private init() {}

    public var sharedContainerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }

    public var sharedUserDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }

    // MARK: - Today's Summary (for widgets)
    public func saveTodaysSummary(_ summary: DaySummary) {
        guard let defaults = sharedUserDefaults else { return }
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(summary) {
            defaults.set(data, forKey: "todaysSummary")
        }
    }

    public func getTodaysSummary() -> DaySummary? {
        guard let defaults = sharedUserDefaults,
              let data = defaults.data(forKey: "todaysSummary") else { return nil }
        return try? JSONDecoder().decode(DaySummary.self, from: data)
    }

    // MARK: - Quick Access Data
    public func saveQuickStats(_ stats: QuickStats) {
        guard let defaults = sharedUserDefaults else { return }
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(stats) {
            defaults.set(data, forKey: "quickStats")
        }
    }

    public func getQuickStats() -> QuickStats? {
        guard let defaults = sharedUserDefaults,
              let data = defaults.data(forKey: "quickStats") else { return nil }
        return try? JSONDecoder().decode(QuickStats.self, from: data)
    }
}

// MARK: - Shared Data Structures
public struct DaySummary: Codable {
    public let date: Date
    public let targetCalories: Int
    public let consumedCalories: Int
    public let meals: [MealSummary]
    public let remainingCalories: Int
    public let streak: Int

    public var progressPercentage: Double {
        guard targetCalories > 0 else { return 0 }
        return min(Double(consumedCalories) / Double(targetCalories), 1.0)
    }

    public init(
        date: Date,
        targetCalories: Int,
        consumedCalories: Int,
        meals: [MealSummary],
        streak: Int
    ) {
        self.date = date
        self.targetCalories = targetCalories
        self.consumedCalories = consumedCalories
        self.meals = meals
        self.remainingCalories = targetCalories - consumedCalories
        self.streak = streak
    }
}

public struct MealSummary: Codable, Identifiable {
    public let id: UUID
    public let type: String
    public let name: String
    public let calories: Int
    public let isLogged: Bool

    public init(id: UUID, type: String, name: String, calories: Int, isLogged: Bool) {
        self.id = id
        self.type = type
        self.name = name
        self.calories = calories
        self.isLogged = isLogged
    }
}

public struct QuickStats: Codable {
    public let currentStreak: Int
    public let level: Int
    public let xp: Int
    public let todayCalories: Int
    public let targetCalories: Int
    public let nextMealName: String?
    public let nextMealCalories: Int?

    public init(
        currentStreak: Int,
        level: Int,
        xp: Int,
        todayCalories: Int,
        targetCalories: Int,
        nextMealName: String?,
        nextMealCalories: Int?
    ) {
        self.currentStreak = currentStreak
        self.level = level
        self.xp = xp
        self.todayCalories = todayCalories
        self.targetCalories = targetCalories
        self.nextMealName = nextMealName
        self.nextMealCalories = nextMealCalories
    }
}
