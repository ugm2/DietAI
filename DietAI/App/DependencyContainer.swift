import Foundation
import SwiftData
import SwiftUI
import Combine

// MARK: - Dependency Container
@MainActor
final class DependencyContainer: ObservableObject {
    static let shared = DependencyContainer()

    // Required for ObservableObject conformance
    let objectWillChange = ObservableObjectPublisher()

    // MARK: - Core Dependencies
    @Published private(set) var modelContext: ModelContext?
    @Published private(set) var configurationError: String?

    /// Returns true if the container has been properly configured
    var isConfigured: Bool { modelContext != nil }

    // MARK: - Services (Singletons)
    lazy var aiModelService: AIModelService = AIModelService.shared

    // MARK: - Repositories (Created after context is set)
    private var _dietPlanRepository: DietPlanRepository?
    var dietPlanRepository: DietPlanRepository? {
        guard let context = modelContext else {
            let error = "DependencyContainer: ModelContext not configured. Call configure(with:) first."
            configurationError = error
            #if DEBUG
            print("⚠️ \(error)")
            #endif
            return nil
        }
        if _dietPlanRepository == nil {
            _dietPlanRepository = DietPlanRepository(modelContext: context)
        }
        return _dietPlanRepository
    }

    private var _mealRepository: MealRepository?
    var mealRepository: MealRepository? {
        guard let context = modelContext else {
            let error = "DependencyContainer: ModelContext not configured. Call configure(with:) first."
            configurationError = error
            #if DEBUG
            print("⚠️ \(error)")
            #endif
            return nil
        }
        if _mealRepository == nil {
            _mealRepository = MealRepository(modelContext: context)
        }
        return _mealRepository
    }

    // MARK: - Use Cases
    var generateDietPlanUseCase: GenerateDietPlanUseCase? {
        guard let repository = dietPlanRepository else { return nil }
        return GenerateDietPlanUseCase(
            aiModelService: aiModelService,
            repository: repository
        )
    }

    // MARK: - Configuration
    func configure(with modelContext: ModelContext) {
        self.modelContext = modelContext
        // Reset repositories when context changes
        _dietPlanRepository = nil
        _mealRepository = nil
    }

    private init() {}
}

// MARK: - Environment Key
struct DependencyContainerKey: EnvironmentKey {
    @MainActor static let defaultValue = DependencyContainer.shared
}

extension EnvironmentValues {
    var dependencies: DependencyContainer {
        get { self[DependencyContainerKey.self] }
        set { self[DependencyContainerKey.self] = newValue }
    }
}

// MARK: - View Extension for Easy Access
extension View {
    func withDependencies() -> some View {
        self.environmentObject(DependencyContainer.shared)
    }
}
