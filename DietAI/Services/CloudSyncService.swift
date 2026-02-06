import Foundation
import CloudKit
import SwiftData
import Network

// MARK: - Sync State
enum SyncState: Equatable {
    case idle
    case syncing
    case error(String)
    case offline

    static func == (lhs: SyncState, rhs: SyncState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.syncing, .syncing), (.offline, .offline):
            return true
        case (.error(let l), .error(let r)):
            return l == r
        default:
            return false
        }
    }
}

// MARK: - Cloud Sync Service
@MainActor
@Observable
final class CloudSyncService {
    static let shared = CloudSyncService()

    private let containerIdentifier = "iCloud.com.garay.DietAI"
    private var container: CKContainer?
    private var privateDatabase: CKDatabase?

    private(set) var syncState: SyncState = .idle
    private(set) var lastSyncDate: Date?
    private(set) var pendingChangesCount: Int = 0

    private var networkMonitor: NWPathMonitor?
    private var isNetworkAvailable = true

    private init() {
        setupNetworkMonitor()
    }

    // MARK: - Setup
    func configure() {
        container = CKContainer(identifier: containerIdentifier)
        privateDatabase = container?.privateCloudDatabase
    }

    // MARK: - Network Monitoring
    private func setupNetworkMonitor() {
        networkMonitor = NWPathMonitor()
        networkMonitor?.pathUpdateHandler = { path in
            // Network status updates are handled - SwiftData + CloudKit handles sync automatically
            // UI updates for network status can be checked via isNetworkAvailable when needed
        }
        networkMonitor?.start(queue: DispatchQueue.global(qos: .utility))
    }

    func updateNetworkStatus(isAvailable: Bool) {
        self.isNetworkAvailable = isAvailable
        if isAvailable {
            self.syncState = .idle
        } else {
            self.syncState = .offline
        }
    }

    // MARK: - Sync Operations
    func syncNow(context: ModelContext) async throws {
        guard isNetworkAvailable else {
            syncState = .offline
            throw SyncError.noNetworkConnection
        }

        syncState = .syncing

        do {
            // Save local changes - SwiftData handles CloudKit sync automatically
            // when configured with cloudKitDatabase
            try context.save()

            // Simulate sync delay for UI feedback
            try await Task.sleep(for: .seconds(1))

            lastSyncDate = Date()
            pendingChangesCount = 0
            syncState = .idle
        } catch {
            syncState = .error(error.localizedDescription)
            throw error
        }
    }

    // MARK: - Mark Changes for Sync
    func markForSync(_ count: Int = 1) {
        pendingChangesCount += count
    }

    // MARK: - Backup & Restore
    func createBackup(context: ModelContext) async throws -> URL {
        let descriptor = FetchDescriptor<DietPlan>()
        let plans = try context.fetch(descriptor)

        let exportData = ExportData(
            version: "1.0",
            exportDate: Date(),
            dietPlans: plans.map { plan in
                ExportDietPlan(
                    id: plan.id,
                    name: plan.name,
                    createdAt: plan.createdAt,
                    goal: plan.goal,
                    dailyCaloriesTarget: plan.dailyCaloriesTarget,
                    days: plan.days.map { day in
                        ExportDailyPlan(
                            dayName: day.dayName,
                            date: day.date,
                            meals: day.meals.map { meal in
                                ExportMeal(
                                    id: meal.id,
                                    type: meal.typeRaw,
                                    name: meal.name,
                                    calories: meal.calories,
                                    protein: meal.protein,
                                    carbs: meal.carbs,
                                    fat: meal.fat,
                                    ingredients: meal.ingredientStrings
                                )
                            }
                        )
                    }
                )
            }
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted

        let data = try encoder.encode(exportData)

        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let backupURL = documentsURL.appendingPathComponent("DietAI_Backup_\(Date().ISO8601Format()).json")

        try data.write(to: backupURL)
        return backupURL
    }

    func restoreFromBackup(url: URL, context: ModelContext) async throws {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let exportData = try decoder.decode(ExportData.self, from: data)

        for planData in exportData.dietPlans {
            let plan = DietPlan(
                name: planData.name,
                goal: GoalType(rawValue: planData.goal) ?? .maintenance,
                calories: planData.dailyCaloriesTarget
            )
            plan.id = planData.id
            plan.createdAt = planData.createdAt
            context.insert(plan)

            for dayData in planData.days {
                let day = DailyPlan(date: dayData.date, dayName: dayData.dayName)
                day.plan = plan
                context.insert(day)

                for mealData in dayData.meals {
                    let meal = Meal(
                        type: MealType(rawValue: mealData.type) ?? .snack,
                        name: mealData.name,
                        calories: mealData.calories,
                        protein: mealData.protein,
                        carbs: mealData.carbs,
                        fat: mealData.fat
                    )
                    meal.id = mealData.id
                    meal.setIngredientsFromStrings(mealData.ingredients)
                    meal.day = day
                    context.insert(meal)
                }
            }
        }

        try context.save()
    }

    func listBackups() -> [URL] {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: documentsURL,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else { return [] }

        return contents
            .filter { $0.lastPathComponent.hasPrefix("DietAI_Backup_") && $0.pathExtension == "json" }
            .sorted { $0.path > $1.path }
    }
}

// MARK: - Sync Errors
enum SyncError: LocalizedError {
    case noNetworkConnection
    case syncFailed(String)
    case backupFailed(String)
    case restoreFailed(String)

    var errorDescription: String? {
        switch self {
        case .noNetworkConnection:
            return "No network connection available"
        case .syncFailed(let reason):
            return "Sync failed: \(reason)"
        case .backupFailed(let reason):
            return "Backup failed: \(reason)"
        case .restoreFailed(let reason):
            return "Restore failed: \(reason)"
        }
    }
}

// MARK: - Export Structures
struct ExportData: Codable {
    let version: String
    let exportDate: Date
    let dietPlans: [ExportDietPlan]
}

struct ExportDietPlan: Codable {
    let id: UUID
    let name: String
    let createdAt: Date
    let goal: String
    let dailyCaloriesTarget: Int
    let days: [ExportDailyPlan]
}

struct ExportDailyPlan: Codable {
    let dayName: String
    let date: Date
    let meals: [ExportMeal]
}

struct ExportMeal: Codable {
    let id: UUID
    let type: String
    let name: String
    let calories: Int
    let protein: Int
    let carbs: Int
    let fat: Int
    let ingredients: [String]
}
