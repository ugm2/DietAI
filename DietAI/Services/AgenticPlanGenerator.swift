import Foundation
import SwiftUI
import MLX
import MLXLLM
import MLXLMCommon

// MARK: - Generation Phase
enum GenerationPhase: Equatable {
    case idle
    case initializing
    case generatingMeal(day: Int, meal: MealType)
    case validating(day: Int, meal: MealType)
    case retrying(day: Int, meal: MealType, attempt: Int)
    case usingFallback(day: Int, meal: MealType)
    case paused(day: Int, meal: MealType)  // Paused due to app going to background
    case completing
    case completed
    case failed(String)

    var displayText: String {
        switch self {
        case .idle: return "Ready to generate"
        case .initializing: return "Preparing AI model..."
        case .generatingMeal(let day, let meal):
            return "Generating Day \(day) - \(meal.rawValue)"
        case .validating(let day, let meal):
            return "Validating Day \(day) - \(meal.rawValue)"
        case .retrying(let day, let meal, let attempt):
            return "Retrying Day \(day) - \(meal.rawValue) (attempt \(attempt))"
        case .usingFallback(let day, let meal):
            return "Using smart default for Day \(day) - \(meal.rawValue)"
        case .paused(let day, let meal):
            return "Paused at Day \(day) - \(meal.rawValue). Return to app to continue."
        case .completing: return "Finalizing plan..."
        case .completed: return "Plan complete!"
        case .failed(let error): return "Failed: \(error)"
        }
    }

    var icon: String {
        switch self {
        case .idle: return "circle"
        case .initializing: return "gear"
        case .generatingMeal: return "sparkles"
        case .validating: return "checkmark.circle"
        case .retrying: return "arrow.triangle.2.circlepath"
        case .usingFallback: return "bookmark.fill"
        case .paused: return "pause.circle.fill"
        case .completing: return "flag.checkered"
        case .completed: return "checkmark.seal.fill"
        case .failed: return "exclamationmark.triangle"
        }
    }

    /// Whether generation is actively running (not paused/idle/completed)
    var isActive: Bool {
        switch self {
        case .idle, .paused, .completed, .failed:
            return false
        default:
            return true
        }
    }
}

// MARK: - Generation Statistics
struct GenerationStats {
    var totalMealsPlanned: Int = 0
    var aiGeneratedMeals: Int = 0
    var fallbackMeals: Int = 0
    var retriesUsed: Int = 0
    var averageGenerationTime: TimeInterval = 0
    var totalCaloriesPlanned: Int = 0
}

// MARK: - Validation Result
struct MealValidationResult {
    let isValid: Bool
    let meal: PlannedMeal?
    let errors: [ValidationError]

    enum ValidationError: Error, CustomStringConvertible {
        case jsonParsingFailed(String)
        case missingRequiredField(String)
        case caloriesOutOfRange(actual: Int, expected: Int, tolerance: Double)
        case invalidMacros(protein: Int?, carbs: Int?, fat: Int?)
        case emptyIngredients

        var description: String {
            switch self {
            case .jsonParsingFailed(let detail):
                return "JSON parsing failed: \(detail)"
            case .missingRequiredField(let field):
                return "Missing required field: \(field)"
            case .caloriesOutOfRange(let actual, let expected, let tolerance):
                let range = Int(Double(expected) * (1 - tolerance))...Int(Double(expected) * (1 + tolerance))
                return "Calories \(actual) outside target range \(range)"
            case .invalidMacros(let p, let c, let f):
                return "Invalid macros - P:\(p ?? -1) C:\(c ?? -1) F:\(f ?? -1)"
            case .emptyIngredients:
                return "No ingredients provided"
            }
        }
    }

    static func valid(_ meal: PlannedMeal) -> MealValidationResult {
        MealValidationResult(isValid: true, meal: meal, errors: [])
    }

    static func invalid(_ errors: [ValidationError]) -> MealValidationResult {
        MealValidationResult(isValid: false, meal: nil, errors: errors)
    }
}

// MARK: - Agentic Errors
enum AgenticError: LocalizedError {
    case alreadyGenerating
    case modelNotAvailable
    case cancelled
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .alreadyGenerating:
            return "A plan generation is already in progress"
        case .modelNotAvailable:
            return "AI model is not available. Please ensure the model is downloaded."
        case .cancelled:
            return "Generation was cancelled"
        case .generationFailed(let reason):
            return "Generation failed: \(reason)"
        }
    }
}

// MARK: - Meal JSON for Parsing
private struct MealJSON: Codable {
    let name: String
    let calories: Int
    let protein: Int
    let carbs: Int
    let fat: Int
    let ingredients: [MealJSONIngredient]

    /// Flexible decoding to handle both structured and legacy string ingredients
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        name = try container.decode(String.self, forKey: .name)
        calories = try container.decode(Int.self, forKey: .calories)
        protein = try container.decode(Int.self, forKey: .protein)
        carbs = try container.decode(Int.self, forKey: .carbs)
        fat = try container.decode(Int.self, forKey: .fat)

        // Try structured format first, then fall back to strings
        if let structured = try? container.decode([MealJSONIngredient].self, forKey: .ingredients) {
            ingredients = structured
        } else if let strings = try? container.decode([String].self, forKey: .ingredients) {
            ingredients = strings.map { MealJSONIngredient(name: $0, quantity: "") }
        } else {
            ingredients = []
        }
    }

    private enum CodingKeys: String, CodingKey {
        case name, calories, protein, carbs, fat, ingredients
    }
}

/// Ingredient format for JSON parsing
private struct MealJSONIngredient: Codable {
    let name: String
    let quantity: String

    init(name: String, quantity: String) {
        self.name = name
        self.quantity = quantity
    }

    func toMealIngredient() -> MealIngredient {
        MealIngredient(name: name, quantity: quantity)
    }
}

// MARK: - Agentic Plan Generator
@MainActor
@Observable
final class AgenticPlanGenerator {
    // MARK: - Observable State
    private(set) var phase: GenerationPhase = .idle
    private(set) var progress: Double = 0.0
    private(set) var currentDayIndex: Int = 0
    private(set) var currentMealType: MealType = .breakfast
    private(set) var generatedDays: [PlannedDay] = []
    private(set) var stats: GenerationStats = GenerationStats()
    private(set) var isGenerating: Bool = false

    // MARK: - Configuration
    private let baseMaxRetries: Int = 2
    private let allAIMaxRetries: Int = 5  // More retries for "All AI" mode
    private let baseTemperature: Float = 0.3
    private let temperatureIncrement: Float = 0.1
    private let maxTokensPerMeal: Int = 300
    private let calorieTolerancePercent: Double = 0.25  // More lenient tolerance

    /// Get max retries based on generation mode
    private var maxRetriesPerMeal: Int {
        config?.generationMode == .allAI ? allAIMaxRetries : baseMaxRetries
    }

    // MARK: - Internal State
    private var config: PlanConfiguration?
    private var userProfile: UserProfile?
    private var activityContext: ActivityPromptContext?
    private var generationStartTime: Date?
    private var isCancelled: Bool = false

    /// Session-aware generator for KV cache reuse
    private var sessionGenerator: SessionAwareGenerator?

    /// Whether to use cached generation (can be disabled for debugging)
    var useCachedGeneration: Bool = true

    // MARK: - Pause/Resume State

    /// Whether generation is currently paused (app went to background)
    private(set) var isPaused: Bool = false

    /// Continuation for resuming paused generation
    private var pauseContinuation: CheckedContinuation<Void, Never>?

    /// Phase before pausing (to restore display state)
    private var phaseBeforePause: GenerationPhase?

    /// Observer tokens for app lifecycle
    private var backgroundObserver: NSObjectProtocol?
    private var foregroundObserver: NSObjectProtocol?

    /// Dynamic meal order based on user selection (sorted by sortOrder)
    private var mealOrder: [MealType] {
        config?.mealTypeOrder ?? MealType.allCases.sorted { $0.sortOrder < $1.sortOrder }
    }

    // MARK: - Computed Properties
    var totalMealsToGenerate: Int {
        (config?.daysCount ?? 7) * mealOrder.count
    }

    var mealsGenerated: Int {
        generatedDays.reduce(0) { $0 + $1.meals.count }
    }

    var estimatedTimeRemaining: TimeInterval {
        let remaining = totalMealsToGenerate - mealsGenerated
        let avgTime = stats.averageGenerationTime > 0 ? stats.averageGenerationTime : 3.0
        return Double(remaining) * avgTime
    }

    // MARK: - Public API

    /// Start autonomous plan generation
    func generatePlan(
        config: PlanConfiguration,
        userProfile: UserProfile? = nil,
        activityContext: ActivityPromptContext? = nil
    ) async throws -> [PlannedDay] {
        guard !isGenerating else {
            throw AgenticError.alreadyGenerating
        }

        // Reset state
        await resetState()

        self.config = config
        self.userProfile = userProfile
        self.activityContext = activityContext
        self.isGenerating = true
        self.isCancelled = false
        self.generationStartTime = Date()

        // Setup app lifecycle observers for pause/resume
        setupLifecycleObservers()

        defer {
            self.isGenerating = false
            teardownLifecycleObservers()
        }

        do {
            // Phase 1: Initialize
            phase = .initializing
            try await ensureModelLoaded()

            // Phase 2: Initialize day structures
            initializeDays(config: config)
            #if DEBUG
            print("🗓️ Initialized \(generatedDays.count) days for generation (config.daysCount: \(config.daysCount))")
            #endif

            // Phase 3: Agentic generation loop
            try await runAgenticLoop()
            #if DEBUG
            print("✅ Agentic loop complete. Generated \(generatedDays.count) days with total \(generatedDays.reduce(0) { $0 + $1.meals.count }) meals")
            #endif

            // Phase 4: Complete
            phase = .completing
            await finalizeGeneration()
            phase = .completed

            return generatedDays

        } catch {
            if isCancelled {
                phase = .idle
                throw AgenticError.cancelled
            }
            phase = .failed(error.localizedDescription)
            throw error
        }
    }

    /// Cancel ongoing generation
    func cancel() {
        isCancelled = true
        resumeIfPaused()  // Resume to allow cancellation to propagate
        phase = .idle
        isGenerating = false
    }

    // MARK: - Pause/Resume

    /// Pause generation (called when app goes to background)
    func pause() {
        guard isGenerating, !isPaused else { return }

        isPaused = true
        phaseBeforePause = phase
        phase = .paused(day: currentDayIndex + 1, meal: currentMealType)

        #if DEBUG
        print("⏸️ Generation paused at Day \(currentDayIndex + 1) - \(currentMealType.rawValue)")
        #endif
    }

    /// Resume generation (called when app returns to foreground)
    func resume() {
        guard isPaused else { return }

        isPaused = false

        // Restore previous phase
        if let previousPhase = phaseBeforePause {
            phase = previousPhase
        }
        phaseBeforePause = nil

        // Resume the waiting continuation
        resumeIfPaused()

        #if DEBUG
        print("▶️ Generation resumed at Day \(currentDayIndex + 1) - \(currentMealType.rawValue)")
        #endif
    }

    /// Resume the paused continuation if one exists
    private func resumeIfPaused() {
        pauseContinuation?.resume()
        pauseContinuation = nil
    }
}

// MARK: - Agentic Loop
private extension AgenticPlanGenerator {

    /// Main agentic generation loop
    func runAgenticLoop() async throws {
        // Initialize session generator for KV cache reuse
        if useCachedGeneration {
            try await initializeSessionGenerator()
        }

        for dayIndex in 0..<(config?.daysCount ?? 7) {
            guard !isCancelled else { throw AgenticError.cancelled }

            currentDayIndex = dayIndex

            for mealType in mealOrder {
                guard !isCancelled else { throw AgenticError.cancelled }

                // Wait if paused (app went to background)
                await waitIfPaused()

                // Check cancellation again after resume
                guard !isCancelled else { throw AgenticError.cancelled }

                currentMealType = mealType

                // Generate with self-validation and retry
                let meal = await generateMealWithValidation(
                    dayIndex: dayIndex,
                    mealType: mealType
                )

                // Add to day
                generatedDays[dayIndex].meals.append(meal)

                // Update progress
                updateProgress()

                // Update average generation time
                if let startTime = generationStartTime {
                    let elapsed = Date().timeIntervalSince(startTime)
                    stats.averageGenerationTime = elapsed / Double(mealsGenerated)
                }
            }
        }

        // Log session statistics
        if let session = sessionGenerator {
            #if DEBUG
            print("📊 \(session.statisticsSummary)")
            #endif
        }
    }

    /// Wait until generation is resumed (if paused)
    private func waitIfPaused() async {
        guard isPaused else { return }

        await withCheckedContinuation { continuation in
            pauseContinuation = continuation
        }
    }

    /// Check if app is in foreground and wait if not
    /// This prevents Metal GPU errors when app goes to background
    private func waitForForeground() async {
        #if os(iOS)
        // Check if app is not in active state
        while !isAppInForeground() {
            // App is backgrounded - wait and check again
            #if DEBUG
            print("⏳ Waiting for app to return to foreground...")
            #endif

            // Wait a short time before checking again
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

            // Also check if cancelled while waiting
            if isCancelled { return }
        }
        #endif
    }

    /// Check if app is currently in foreground
    private func isAppInForeground() -> Bool {
        #if os(iOS)
        return UIApplication.shared.applicationState == .active
        #else
        return true
        #endif
    }

    // MARK: - App Lifecycle

    /// Setup observers for app going to background/foreground
    func setupLifecycleObservers() {
        #if os(iOS)
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                self?.pause()
            }
        }

        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                self?.resume()
            }
        }

        #if DEBUG
        print("👀 Lifecycle observers setup for pause/resume")
        #endif
        #endif
    }

    /// Remove lifecycle observers
    func teardownLifecycleObservers() {
        if let observer = backgroundObserver {
            NotificationCenter.default.removeObserver(observer)
            backgroundObserver = nil
        }
        if let observer = foregroundObserver {
            NotificationCenter.default.removeObserver(observer)
            foregroundObserver = nil
        }

        #if DEBUG
        print("👀 Lifecycle observers removed")
        #endif
    }

    /// Initialize session generator with prefilled system prompt
    private func initializeSessionGenerator() async throws {
        guard config?.generationMode != .allCurated,
              ModelManager.shared.modelContainer != nil else {
            return
        }

        do {
            sessionGenerator = try ModelManager.shared.createSessionGenerator()

            // Build and prefill the common system prompt
            let systemPrompt = buildCommonSystemPrompt()
            try await sessionGenerator?.prefillSystemPrompt(systemPrompt)

            #if DEBUG
            print("✅ Session generator initialized with prefilled system prompt")
            #endif
        } catch {
            #if DEBUG
            print("⚠️ Failed to initialize session generator: \(error). Falling back to standard generation.")
            #endif
            sessionGenerator = nil
        }
    }

    /// Build the common system prompt used across all meal generations
    private func buildCommonSystemPrompt() -> String {
        guard let config = config else { return "" }

        var promptParts: [String] = []

        // Base instruction
        promptParts.append("""
        You are an expert nutritionist. Generate ONE meal at a time.
        Respond with ONLY valid JSON, no explanations.
        IMPORTANT: Give each meal a DESCRIPTIVE name based on its main ingredients (e.g., "Greek Yogurt Parfait", "Grilled Salmon Bowl"). NEVER use generic names like "Breakfast" or "Dinner".
        """)

        // Goal-specific guidance
        let goalGuidance = getGoalGuidance(config.goal)
        promptParts.append("Goal: \(config.goal.rawValue). \(goalGuidance)")

        // Restrictions (critical - must be in system prompt)
        if !config.restrictions.isEmpty {
            promptParts.append("STRICT restrictions (must avoid): \(config.restrictions.joined(separator: ", "))")
        }

        // User preferences from profile
        if let profile = userProfile {
            if !profile.lovedIngredients.isEmpty {
                promptParts.append("Preferred ingredients: \(profile.lovedIngredients.prefix(5).joined(separator: ", "))")
            }
            if !profile.dislikedIngredients.isEmpty {
                promptParts.append("Avoid: \(profile.dislikedIngredients.prefix(5).joined(separator: ", "))")
            }
            if !profile.preferredCuisines.isEmpty {
                promptParts.append("Preferred cuisines: \(profile.preferredCuisines.prefix(3).joined(separator: ", "))")
            }
        }

        // Activity context (if available)
        if let activity = activityContext {
            promptParts.append(buildActivityContextSection(activity, mealType: .breakfast))
        }

        // JSON format instruction
        promptParts.append("""
        Required JSON format:
        {"name":"Descriptive Meal Name","calories":XXX,"protein":XX,"carbs":XX,"fat":XX,"ingredients":[{"name":"ingredient","quantity":"amount"}]}
        """)

        return promptParts.joined(separator: "\n\n")
    }

    /// Generate a single meal with validation and retry logic
    func generateMealWithValidation(
        dayIndex: Int,
        mealType: MealType
    ) async -> PlannedMeal {
        // Check generation mode from config
        let generationMode = config?.generationMode ?? .mixed

        // If all curated mode, skip AI entirely
        if generationMode == .allCurated {
            phase = .usingFallback(day: dayIndex + 1, meal: mealType)
            stats.fallbackMeals += 1
            stats.totalMealsPlanned += 1
            return createFallbackMeal(mealType: mealType, dayIndex: dayIndex)
        }

        // MLX model generation with validation and retry
        #if DEBUG
        print("🔷 Using MLX (\(ModelManager.shared.currentTier.displayName)) for Day \(dayIndex + 1) \(mealType.rawValue)")
        #endif

        // CRITICAL: Check if model container exists before attempting generation
        guard ModelManager.shared.modelContainer != nil else {
            #if DEBUG
            print("❌ MLX model container is nil - using curated fallback")
            #endif
            phase = .usingFallback(day: dayIndex + 1, meal: mealType)
            stats.fallbackMeals += 1
            stats.totalMealsPlanned += 1
            return createFallbackMeal(mealType: mealType, dayIndex: dayIndex)
        }

        var currentTemperature = baseTemperature
        var lastErrors: [MealValidationResult.ValidationError] = []

        for attempt in 1...(maxRetriesPerMeal + 1) {
            // Wait for foreground before GPU work to prevent Metal errors
            await waitForForeground()

            // Check if cancelled while waiting
            if isCancelled {
                phase = .usingFallback(day: dayIndex + 1, meal: mealType)
                stats.fallbackMeals += 1
                stats.totalMealsPlanned += 1
                return createFallbackMeal(mealType: mealType, dayIndex: dayIndex)
            }

            do {
                // Update phase
                if attempt == 1 {
                    phase = .generatingMeal(day: dayIndex + 1, meal: mealType)
                } else {
                    phase = .retrying(day: dayIndex + 1, meal: mealType, attempt: attempt)
                    stats.retriesUsed += 1
                }

                // Build context-aware prompt
                let prompt = buildMealPrompt(
                    dayIndex: dayIndex,
                    mealType: mealType,
                    existingMeals: generatedDays[dayIndex].meals
                )

                // Final foreground check right before GPU work
                await waitForForeground()

                // Generate
                let rawOutput = try await generateRaw(
                    prompt: prompt,
                    maxTokens: maxTokensPerMeal,
                    temperature: currentTemperature
                )

                // Validate
                phase = .validating(day: dayIndex + 1, meal: mealType)
                let validationResult = validateMealOutput(
                    rawOutput: rawOutput,
                    mealType: mealType,
                    targetCalories: calculateMealCalorieTarget(mealType: mealType)
                )

                if validationResult.isValid, let meal = validationResult.meal {
                    stats.aiGeneratedMeals += 1
                    stats.totalMealsPlanned += 1
                    return meal
                }

                // Store errors for potential logging
                lastErrors = validationResult.errors
                #if DEBUG
                print("⚠️ Validation failed (attempt \(attempt)): \(lastErrors.map { $0.description })")
                #endif

                // Increase temperature for retry
                currentTemperature = min(currentTemperature + temperatureIncrement, 0.7)

            } catch {
                #if DEBUG
                print("❌ Generation error (attempt \(attempt)): \(error)")
                #endif
                currentTemperature = min(currentTemperature + temperatureIncrement, 0.7)
            }
        }

        // All retries exhausted
        // For "All AI" mode, try one last time with a very simple prompt
        if generationMode == .allAI {
            if let simpleMeal = await trySimpleGeneration(dayIndex: dayIndex, mealType: mealType) {
                stats.aiGeneratedMeals += 1
                stats.totalMealsPlanned += 1
                return simpleMeal
            }
        }

        // Use fallback
        phase = .usingFallback(day: dayIndex + 1, meal: mealType)
        stats.fallbackMeals += 1
        stats.totalMealsPlanned += 1

        return createFallbackMeal(
            mealType: mealType,
            dayIndex: dayIndex
        )
    }

    /// Last-resort simple generation for "All AI" mode
    private func trySimpleGeneration(dayIndex: Int, mealType: MealType) async -> PlannedMeal? {
        guard let container = ModelManager.shared.modelContainer else { return nil }

        let targetCalories = calculateMealCalorieTarget(mealType: mealType)

        // Sample meal names for the prompt example based on meal type
        let exampleName: String = {
            switch mealType {
            case .breakfast: return "Oatmeal Power Bowl"
            case .brunch: return "Avocado Eggs Benedict"
            case .lunch: return "Mediterranean Quinoa Salad"
            case .snack: return "Greek Yogurt with Berries"
            case .dinner: return "Grilled Salmon with Vegetables"
            }
        }()

        // Very simple prompt that's more likely to produce valid JSON
        let simplePrompt = """
        <|begin_of_text|><|start_header_id|>system<|end_header_id|>
        Output JSON only. Use a descriptive meal name based on ingredients.
        <|eot_id|><|start_header_id|>user<|end_header_id|>
        Create a \(mealType.rawValue.lowercased()) meal with \(targetCalories) calories. Name it after its main ingredients like "\(exampleName)".
        <|eot_id|><|start_header_id|>assistant<|end_header_id|>
        {"name":"
        """

        do {
            let output = try await container.perform { context in
                let input = try await context.processor.prepare(input: UserInput(prompt: simplePrompt))
                let params = GenerateParameters(maxTokens: 200, temperature: 0.5)

                let result = try MLXLMCommon.generate(
                    input: input,
                    parameters: params,
                    context: context
                ) { (tokens: [Int]) -> GenerateDisposition in
                    tokens.count > 200 ? .stop : .more
                }

                return result.output
            }

            // Try to parse with very lenient validation
            if let meal = parseLenientMeal(from: output, mealType: mealType, targetCalories: targetCalories) {
                return meal
            }
        } catch {
            #if DEBUG
            print("❌ Simple generation failed: \(error)")
            #endif
        }

        return nil
    }

    /// Lenient parsing that fills in missing values
    private func parseLenientMeal(from output: String, mealType: MealType, targetCalories: Int) -> PlannedMeal? {
        // Try to extract name at minimum
        var cleaned = output
        if let startIndex = cleaned.firstIndex(of: "{") {
            cleaned = String(cleaned[startIndex...])
        }
        if let endIndex = cleaned.lastIndex(of: "}") {
            cleaned = String(cleaned[...endIndex])
        }

        // Try full parsing first
        if let data = cleaned.data(using: .utf8),
           let json = try? JSONDecoder().decode(MealJSON.self, from: data) {
            let mealIngredients = json.ingredients.isEmpty
                ? [MealIngredient(name: "Various ingredients")]
                : json.ingredients.map { $0.toMealIngredient() }
            return PlannedMeal(
                type: mealType,
                name: json.name,
                calories: json.calories > 0 ? json.calories : targetCalories,
                protein: max(0, json.protein),
                carbs: max(0, json.carbs),
                fat: max(0, json.fat),
                structuredIngredients: mealIngredients
            )
        }

        // Try to extract just the name
        if let nameMatch = output.range(of: "\"name\"\\s*:\\s*\"([^\"]+)\"", options: .regularExpression) {
            let nameRange = output[nameMatch]
            if let colonIndex = nameRange.firstIndex(of: ":"),
               let startQuote = nameRange[colonIndex...].firstIndex(of: "\"") {
                let afterQuote = nameRange.index(after: startQuote)
                if let endQuote = nameRange[afterQuote...].firstIndex(of: "\"") {
                    let name = String(nameRange[afterQuote..<endQuote])
                    let macros = calculateMacros(forCalories: targetCalories, goal: config?.goal ?? .maintenance)
                    return PlannedMeal(
                        type: mealType,
                        name: name,
                        calories: targetCalories,
                        protein: macros.protein,
                        carbs: macros.carbs,
                        fat: macros.fat,
                        structuredIngredients: [MealIngredient(name: "Various ingredients")]
                    )
                }
            }
        }

        return nil
    }

}

// MARK: - Validation
private extension AgenticPlanGenerator {

    /// Validate raw model output and parse into PlannedMeal
    func validateMealOutput(
        rawOutput: String,
        mealType: MealType,
        targetCalories: Int
    ) -> MealValidationResult {
        var errors: [MealValidationResult.ValidationError] = []

        // Step 1: Extract and clean JSON
        guard let jsonString = extractJSON(from: rawOutput) else {
            return .invalid([.jsonParsingFailed("No valid JSON found in output")])
        }

        // Step 2: Parse JSON
        guard let data = jsonString.data(using: .utf8) else {
            return .invalid([.jsonParsingFailed("UTF-8 encoding failed")])
        }

        let mealJSON: MealJSON
        do {
            mealJSON = try JSONDecoder().decode(MealJSON.self, from: data)
        } catch {
            return .invalid([.jsonParsingFailed(error.localizedDescription)])
        }

        // Step 3: Validate required fields
        if mealJSON.name.isEmpty {
            errors.append(.missingRequiredField("name"))
        }

        // Step 4: Validate calorie range
        let minCalories = Int(Double(targetCalories) * (1 - calorieTolerancePercent))
        let maxCalories = Int(Double(targetCalories) * (1 + calorieTolerancePercent))

        if mealJSON.calories < minCalories || mealJSON.calories > maxCalories {
            errors.append(.caloriesOutOfRange(
                actual: mealJSON.calories,
                expected: targetCalories,
                tolerance: calorieTolerancePercent
            ))
        }

        // Step 5: Validate macros are reasonable
        if mealJSON.protein < 0 || mealJSON.carbs < 0 || mealJSON.fat < 0 {
            errors.append(.invalidMacros(
                protein: mealJSON.protein,
                carbs: mealJSON.carbs,
                fat: mealJSON.fat
            ))
        }

        // Step 6: Validate ingredients
        if mealJSON.ingredients.isEmpty {
            errors.append(.emptyIngredients)
        }

        // Return result
        if errors.isEmpty {
            let meal = PlannedMeal(
                type: mealType,
                name: mealJSON.name,
                calories: mealJSON.calories,
                protein: mealJSON.protein,
                carbs: mealJSON.carbs,
                fat: mealJSON.fat,
                structuredIngredients: mealJSON.ingredients.map { $0.toMealIngredient() }
            )
            return .valid(meal)
        } else {
            return .invalid(errors)
        }
    }

    /// Extract JSON from raw model output
    func extractJSON(from text: String) -> String? {
        var cleaned = text

        // Remove markdown code blocks
        cleaned = cleaned.replacingOccurrences(of: "```json", with: "")
        cleaned = cleaned.replacingOccurrences(of: "```JSON", with: "")
        cleaned = cleaned.replacingOccurrences(of: "```", with: "")

        // Find JSON boundaries
        guard let startIndex = cleaned.firstIndex(of: "{") else {
            return nil
        }

        // Find closing brace
        if let endIndex = cleaned.lastIndex(of: "}") {
            let jsonRange = startIndex...endIndex
            cleaned = String(cleaned[jsonRange])
        } else {
            // Add closing brace
            cleaned = String(cleaned[startIndex...]) + "}"
        }

        // Apply repairs
        cleaned = repairJSON(cleaned)

        // Validate it parses
        if let data = cleaned.data(using: .utf8),
           let _ = try? JSONSerialization.jsonObject(with: data) {
            return cleaned
        }

        return nil
    }

    /// Repair common JSON issues
    func repairJSON(_ json: String) -> String {
        var repaired = json

        // Fix trailing commas
        repaired = repaired.replacingOccurrences(of: ",\\s*]", with: "]", options: .regularExpression)
        repaired = repaired.replacingOccurrences(of: ",\\s*}", with: "}", options: .regularExpression)

        // Fix single quotes
        repaired = repaired.replacingOccurrences(of: "'", with: "\"")

        return repaired
    }
}

// MARK: - Prompt Building
private extension AgenticPlanGenerator {

    /// Build a context-aware prompt for meal generation
    func buildMealPrompt(
        dayIndex: Int,
        mealType: MealType,
        existingMeals: [PlannedMeal]
    ) -> String {
        guard let config = config else { return "" }

        let targetCalories = calculateMealCalorieTarget(mealType: mealType)
        let dayName = config.dayNames[dayIndex]

        // Calculate remaining calories for the day
        let usedCalories = existingMeals.reduce(0) { $0 + $1.calories }
        let remainingDayCalories = config.dailyCalories - usedCalories

        // Build context section
        var contextParts: [String] = []

        // Goal-specific guidance
        let goalGuidance = getGoalGuidance(config.goal)
        contextParts.append("Goal: \(config.goal.rawValue). \(goalGuidance)")

        // Existing meals context (avoid repetition)
        if !existingMeals.isEmpty {
            let mealNames = existingMeals.map { $0.name }.joined(separator: ", ")
            contextParts.append("Already planned today: \(mealNames). Choose something different.")
        }

        // Budget awareness
        contextParts.append("Remaining calorie budget for \(dayName): \(remainingDayCalories) kcal.")

        // Restrictions
        if !config.restrictions.isEmpty {
            contextParts.append("STRICT restrictions (must avoid): \(config.restrictions.joined(separator: ", "))")
        }

        // User preferences from profile
        if let profile = userProfile {
            if !profile.lovedIngredients.isEmpty {
                contextParts.append("Preferred ingredients: \(profile.lovedIngredients.prefix(5).joined(separator: ", "))")
            }
            if !profile.dislikedIngredients.isEmpty {
                contextParts.append("Avoid: \(profile.dislikedIngredients.prefix(5).joined(separator: ", "))")
            }
            if !profile.preferredCuisines.isEmpty {
                contextParts.append("Preferred cuisines: \(profile.preferredCuisines.prefix(3).joined(separator: ", "))")
            }
        }

        // Custom prompt from user (important - user's specific request)
        if !config.customPrompt.isEmpty {
            contextParts.append("IMPORTANT user request: \(config.customPrompt)")
        }

        // Activity context for sports nutrition optimization
        if let activity = activityContext {
            contextParts.append(buildActivityContextSection(activity, mealType: mealType))
        }

        let contextString = contextParts.joined(separator: "\n")

        // Build the full prompt using Llama 3.2 chat template
        return """
        <|begin_of_text|><|start_header_id|>system<|end_header_id|>
        You are an expert nutritionist. Generate ONE \(mealType.rawValue.lowercased()) meal.

        Context:
        \(contextString)

        Requirements:
        - Target: approximately \(targetCalories) calories (±20% acceptable)
        - Include realistic protein, carbs, and fat values in grams
        - List 3-6 main ingredients with separate name and quantity fields
        - Create a practical, appetizing meal
        - IMPORTANT: Give the meal a DESCRIPTIVE name based on its main ingredients (e.g., "Greek Yogurt Parfait with Berries", "Grilled Salmon with Quinoa", "Avocado Toast with Eggs"). NEVER use generic names like "Breakfast" or "Friday Dinner".

        Respond with ONLY valid JSON, no explanations:
        {"name":"Descriptive Meal Name Here","calories":XXX,"protein":XX,"carbs":XX,"fat":XX,"ingredients":[{"name":"chicken breast","quantity":"200g"},{"name":"rice","quantity":"1 cup"}]}
        <|eot_id|><|start_header_id|>user<|end_header_id|>
        Generate a \(mealType.rawValue.lowercased()) with approximately \(targetCalories) calories. Give it a creative, descriptive name based on the ingredients.
        <|eot_id|><|start_header_id|>assistant<|end_header_id|>
        {
        """
    }

    /// Get goal-specific guidance for the prompt
    func getGoalGuidance(_ goal: GoalType) -> String {
        switch goal {
        case .weightLoss:
            return "Focus on high protein, high fiber, filling foods with moderate calories."
        case .muscleGain:
            return "Prioritize high protein (25g+ per meal) with adequate carbs for muscle building."
        case .maintenance:
            return "Provide balanced macronutrients for sustained energy."
        case .keto:
            return "Focus on high fat, moderate protein, very low carbs (under 10g net carbs per meal)."
        }
    }

    /// Build activity context section for the prompt
    func buildActivityContextSection(_ activity: ActivityPromptContext, mealType: MealType) -> String {
        var parts: [String] = []

        parts.append("ACTIVITY CONTEXT:")

        // Weekly training pattern
        if activity.weeklyTrend.workoutDays > 0 {
            parts.append("- Training frequency: \(activity.weeklyTrend.workoutDays) days/week")
        }

        // Dominant training type
        if let dominant = activity.dominantCategory ?? activity.weeklyTrend.dominantCategory {
            parts.append("- Primary training focus: \(dominant.rawValue)")

            // Specific nutrition guidance based on workout type
            switch dominant {
            case .strength:
                parts.append("- NUTRITION PRIORITY: High protein (25-30g) for muscle recovery")
                if activity.isRecoveryWindowActive {
                    parts.append("- IN RECOVERY WINDOW: Include fast-digesting protein and carbs")
                }
            case .cardio, .hiit:
                parts.append("- NUTRITION PRIORITY: Adequate carbs for glycogen, lean protein")
            case .endurance:
                parts.append("- NUTRITION PRIORITY: Complex carbs for sustained energy")
            case .yoga, .recovery:
                parts.append("- NUTRITION PRIORITY: Light, easily digestible foods")
            default:
                break
            }
        }

        // Protein boost recommendation
        if activity.proteinBoostNeeded > 0 {
            let extraProtein = Int(activity.proteinBoostNeeded * 70) // Assuming 70kg
            parts.append("- Extra protein needed today: +\(extraProtein)g")
        }

        return parts.joined(separator: "\n")
    }

    /// Calculate target calories per meal based on meal type
    func calculateMealCalorieTarget(mealType: MealType) -> Int {
        guard let config = config else { return 500 }

        // Base calorie weights for each meal type (relative proportions)
        let baseWeights: [MealType: Double] = [
            .breakfast: 25,
            .brunch: 25,
            .lunch: 30,
            .snack: 15,
            .dinner: 30
        ]

        // Calculate total weight of selected meal types
        let selectedTypes = config.selectedMealTypes
        let totalWeight = selectedTypes.reduce(0.0) { $0 + (baseWeights[$1] ?? 20) }

        // Calculate percentage for this meal type (normalized to 100%)
        let weight = baseWeights[mealType] ?? 20
        let percentage = totalWeight > 0 ? weight / totalWeight : 0.25

        return Int(Double(config.dailyCalories) * percentage)
    }
}

// MARK: - Fallback Meals
private extension AgenticPlanGenerator {

    /// Create a fallback meal when AI generation fails
    func createFallbackMeal(mealType: MealType, dayIndex: Int) -> PlannedMeal {
        let targetCalories = calculateMealCalorieTarget(mealType: mealType)
        let goal = config?.goal ?? .maintenance

        // Curated fallback meals organized by type and goal
        let fallbackLibrary: [GoalType: [MealType: [(String, [String])]]] = [
            .weightLoss: [
                .breakfast: [
                    ("Egg White Vegetable Scramble", ["egg whites", "spinach", "tomatoes", "bell peppers"]),
                    ("Greek Yogurt with Berries", ["non-fat greek yogurt", "mixed berries", "chia seeds"]),
                    ("Overnight Oats", ["oats", "almond milk", "banana", "cinnamon"])
                ],
                .brunch: [
                    ("Veggie Frittata", ["egg whites", "zucchini", "tomatoes", "feta"]),
                    ("Smoked Salmon Toast", ["whole grain bread", "smoked salmon", "cream cheese", "capers"]),
                    ("Açaí Bowl Light", ["açaí", "banana", "berries", "granola"])
                ],
                .lunch: [
                    ("Grilled Chicken Salad", ["chicken breast", "mixed greens", "cucumber", "light vinaigrette"]),
                    ("Turkey Lettuce Wraps", ["turkey breast", "lettuce leaves", "hummus", "tomatoes"]),
                    ("Tuna Poke Bowl", ["tuna", "brown rice", "edamame", "seaweed"])
                ],
                .snack: [
                    ("Apple Slices with Almond Butter", ["apple", "almond butter"]),
                    ("Cottage Cheese Cup", ["low-fat cottage cheese", "cherry tomatoes"]),
                    ("Veggie Sticks with Hummus", ["carrots", "celery", "hummus"])
                ],
                .dinner: [
                    ("Baked Salmon with Vegetables", ["salmon fillet", "asparagus", "lemon", "olive oil"]),
                    ("Turkey Meatballs with Zoodles", ["ground turkey", "zucchini noodles", "marinara"]),
                    ("Shrimp Stir Fry", ["shrimp", "broccoli", "snap peas", "ginger"])
                ]
            ],
            .muscleGain: [
                .breakfast: [
                    ("Protein Pancakes", ["protein powder", "oats", "eggs", "banana"]),
                    ("Steak and Eggs", ["sirloin steak", "whole eggs", "avocado"]),
                    ("High Protein Smoothie Bowl", ["protein powder", "Greek yogurt", "peanut butter", "granola"])
                ],
                .brunch: [
                    ("Eggs Benedict with Ham", ["English muffin", "poached eggs", "ham", "hollandaise"]),
                    ("Protein French Toast", ["whole grain bread", "eggs", "protein powder", "maple syrup"]),
                    ("Loaded Breakfast Burrito", ["tortilla", "scrambled eggs", "sausage", "cheese", "beans"])
                ],
                .lunch: [
                    ("Double Chicken Burrito Bowl", ["chicken breast", "brown rice", "black beans", "avocado"]),
                    ("Beef and Sweet Potato", ["lean beef", "sweet potato", "broccoli"]),
                    ("Salmon Rice Bowl", ["salmon", "white rice", "edamame", "teriyaki"])
                ],
                .snack: [
                    ("Protein Shake with Banana", ["protein powder", "banana", "peanut butter", "milk"]),
                    ("Greek Yogurt Parfait", ["Greek yogurt", "granola", "honey"]),
                    ("Cheese and Turkey Roll-Ups", ["turkey slices", "cheese slices", "mustard"])
                ],
                .dinner: [
                    ("Grilled Ribeye with Potatoes", ["ribeye steak", "baked potato", "butter", "asparagus"]),
                    ("Chicken Pasta Alfredo", ["chicken breast", "whole wheat pasta", "alfredo sauce"]),
                    ("Lamb Chops with Quinoa", ["lamb chops", "quinoa", "roasted vegetables"])
                ]
            ],
            .maintenance: [
                .breakfast: [
                    ("Avocado Toast with Eggs", ["whole grain bread", "avocado", "poached eggs"]),
                    ("Oatmeal with Nuts", ["oatmeal", "walnuts", "honey", "banana"]),
                    ("Smoothie Bowl", ["frozen berries", "banana", "Greek yogurt", "granola"])
                ],
                .brunch: [
                    ("Classic Eggs Florentine", ["English muffin", "poached eggs", "spinach", "hollandaise"]),
                    ("Brunch Quinoa Bowl", ["quinoa", "avocado", "poached egg", "cherry tomatoes"]),
                    ("Stuffed French Toast", ["brioche", "cream cheese", "berries", "maple syrup"])
                ],
                .lunch: [
                    ("Mediterranean Wrap", ["whole wheat wrap", "falafel", "hummus", "vegetables"]),
                    ("Chicken Caesar Salad", ["chicken breast", "romaine", "parmesan", "caesar dressing"]),
                    ("Veggie Burger", ["veggie patty", "whole wheat bun", "lettuce", "tomato"])
                ],
                .snack: [
                    ("Mixed Nuts and Dried Fruit", ["almonds", "cashews", "dried cranberries"]),
                    ("Cheese and Crackers", ["cheddar cheese", "whole grain crackers"]),
                    ("Fruit and Nut Bar", ["dates", "almonds", "dark chocolate"])
                ],
                .dinner: [
                    ("Grilled Chicken with Rice", ["chicken breast", "brown rice", "steamed vegetables"]),
                    ("Pasta Primavera", ["whole wheat pasta", "mixed vegetables", "olive oil", "parmesan"]),
                    ("Fish Tacos", ["white fish", "corn tortillas", "cabbage slaw", "lime"])
                ]
            ],
            .keto: [
                .breakfast: [
                    ("Bacon and Eggs", ["bacon", "eggs", "avocado", "cheese"]),
                    ("Keto Coffee with Eggs", ["butter coffee", "scrambled eggs", "cheese"]),
                    ("Smoked Salmon Plate", ["smoked salmon", "cream cheese", "capers", "cucumber"])
                ],
                .brunch: [
                    ("Keto Eggs Benedict", ["Canadian bacon", "poached eggs", "keto hollandaise", "avocado"]),
                    ("Loaded Omelet", ["eggs", "bacon", "cheese", "spinach", "mushrooms"]),
                    ("Salmon Avocado Stack", ["smoked salmon", "avocado", "cream cheese", "capers"])
                ],
                .lunch: [
                    ("Cobb Salad", ["chicken", "bacon", "eggs", "avocado", "blue cheese"]),
                    ("Bunless Burger", ["beef patty", "cheese", "lettuce", "tomato", "mayo"]),
                    ("Chicken Caesar (no croutons)", ["chicken", "romaine", "parmesan", "caesar dressing"])
                ],
                .snack: [
                    ("Cheese and Pepperoni", ["mozzarella", "pepperoni"]),
                    ("Avocado with Everything", ["avocado", "everything bagel seasoning", "olive oil"]),
                    ("Pork Rinds with Guacamole", ["pork rinds", "guacamole"])
                ],
                .dinner: [
                    ("Ribeye with Butter", ["ribeye steak", "butter", "asparagus"]),
                    ("Salmon with Creamy Spinach", ["salmon", "spinach", "cream", "garlic"]),
                    ("Chicken Thighs with Cauliflower", ["chicken thighs", "cauliflower mash", "gravy"])
                ]
            ]
        ]

        let mealOptions = fallbackLibrary[goal]?[mealType]
            ?? fallbackLibrary[.maintenance]?[mealType]
            ?? [("Balanced Meal", ["protein source", "vegetables", "grains"])]
        let selected = mealOptions[dayIndex % max(mealOptions.count, 1)]

        // Calculate macros based on goal and calories
        let macros = calculateMacros(forCalories: targetCalories, goal: goal)

        return PlannedMeal(
            type: mealType,
            name: selected.0,
            calories: targetCalories,
            protein: macros.protein,
            carbs: macros.carbs,
            fat: macros.fat,
            ingredients: selected.1
        )
    }

    /// Calculate appropriate macros based on goal
    func calculateMacros(forCalories calories: Int, goal: GoalType) -> (protein: Int, carbs: Int, fat: Int) {
        // Macro ratios by goal (protein/carbs/fat)
        let ratios: (p: Double, c: Double, f: Double) = {
            switch goal {
            case .weightLoss: return (0.35, 0.35, 0.30)
            case .muscleGain: return (0.30, 0.45, 0.25)
            case .maintenance: return (0.25, 0.45, 0.30)
            case .keto: return (0.25, 0.05, 0.70)
            }
        }()

        let protein = Int(Double(calories) * ratios.p / 4.0)
        let carbs = Int(Double(calories) * ratios.c / 4.0)
        let fat = Int(Double(calories) * ratios.f / 9.0)

        return (protein, carbs, fat)
    }
}

// MARK: - Supporting Methods
private extension AgenticPlanGenerator {

    /// Reset all state for a new generation
    func resetState() async {
        phase = .idle
        progress = 0.0
        currentDayIndex = 0
        currentMealType = .breakfast
        generatedDays = []
        stats = GenerationStats()
        isCancelled = false
        generationStartTime = nil

        // Reset pause state
        isPaused = false
        pauseContinuation = nil
        phaseBeforePause = nil

        // Reset session generator
        sessionGenerator?.resetCache()
        sessionGenerator = nil
    }

    /// Ensure the AI model is loaded
    func ensureModelLoaded() async throws {
        // First, determine the best tier if not already done
        ModelManager.shared.determineBestTier()

        // If using "All Curated" mode, no model needed
        if config?.generationMode == .allCurated {
            return
        }

        // For MLX models, need to load the model
        if !ModelManager.shared.isModelLoaded {
            await ModelManager.shared.loadModel()
        }

        // If model still not loaded, check if we can fall back to curated meals
        // instead of throwing an error
        if !ModelManager.shared.isModelLoaded || ModelManager.shared.modelContainer == nil {
            // Allow generation to proceed - will use fallback meals
            #if DEBUG
            print("⚠️ MLX model not loaded, will use curated fallback meals")
            #endif
            // Don't throw - let the generator use fallback meals
        }
    }

    /// Initialize empty day structures
    func initializeDays(config: PlanConfiguration) {
        generatedDays = config.dayNames.enumerated().map { index, name in
            let date = Calendar.current.date(byAdding: .day, value: index, to: config.startDate) ?? config.startDate
            return PlannedDay(dayName: name, date: date)
        }
    }

    /// Update progress percentage
    func updateProgress() {
        progress = Double(mealsGenerated) / Double(totalMealsToGenerate)
    }

    /// Generate raw output from the model
    /// Uses session generator with cached system prompt when available
    func generateRaw(prompt: String, maxTokens: Int, temperature: Float) async throws -> String {
        // Try using session generator first for cache efficiency
        if let session = sessionGenerator, session.isPrefilled {
            // Extract just the user-specific part from the prompt
            // The session already has the system prompt prefilled
            let userPrompt = extractUserPrompt(from: prompt)
            return try await session.generateWithCache(
                userPrompt: userPrompt,
                maxTokens: maxTokens,
                temperature: temperature
            )
        }

        // Fall back to standard generation
        guard let container = ModelManager.shared.modelContainer else {
            throw AgenticError.modelNotAvailable
        }

        return try await container.perform { context in
            let input = try await context.processor.prepare(input: UserInput(prompt: prompt))
            let params = GenerateParameters(maxTokens: maxTokens, temperature: temperature)

            let result = try MLXLMCommon.generate(
                input: input,
                parameters: params,
                context: context
            ) { (tokens: [Int]) -> GenerateDisposition in
                if tokens.count > maxTokens {
                    return .stop
                }
                return .more
            }

            return result.output
        }
    }

    /// Extract user-specific prompt content for session-based generation
    private func extractUserPrompt(from fullPrompt: String) -> String {
        // The full prompt contains the system prompt in chat template format
        // We need to extract just the user request part
        // Look for the user header marker
        if let userRange = fullPrompt.range(of: "<|start_header_id|>user<|end_header_id|>") {
            let afterUser = fullPrompt[userRange.upperBound...]
            // Find the end of user section
            if let endRange = afterUser.range(of: "<|eot_id|>") {
                return String(afterUser[..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return String(afterUser).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // If no chat template markers found, return the whole prompt
        return fullPrompt
    }

    /// Finalize generation and compute final stats
    func finalizeGeneration() async {
        stats.totalCaloriesPlanned = generatedDays.reduce(0) { $0 + $1.totalCalories }

        // Clean up session generator
        sessionGenerator?.resetCache()
        sessionGenerator = nil
    }
}
