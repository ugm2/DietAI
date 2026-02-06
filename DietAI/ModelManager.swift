import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import SwiftData
import SwiftUI

/// ModelManager serves as a facade for the AI services.
/// It maintains backwards compatibility with existing views while using the new architecture internally.
/// Supports tiered model selection: Qwen 4B → Llama 3B → Llama 1B
@MainActor
@Observable
class ModelManager {
    static let shared = ModelManager()

    // Use the new AI service internally
    private var aiService: AIModelService { AIModelService.shared }

    // MARK: - Tiered Model System

    /// The current AI model tier being used
    private(set) var currentTier: AIModelTier = .llama3B

    /// Whether we've determined the best tier for this device
    private var tierDetermined: Bool = false

    /// User preference for high quality model (Qwen 4B) vs fast model (Llama 3B)
    /// Default is false (use Llama 3B for speed)
    var preferHighQualityModel: Bool {
        get { UserDefaults.standard.bool(forKey: "preferHighQualityModel") }
        set {
            UserDefaults.standard.set(newValue, forKey: "preferHighQualityModel")
            // Re-determine tier when preference changes
            tierDetermined = false
            determineBestTier()
            #if DEBUG
            print("🔧 Model preference changed to: \(newValue ? "Qwen 4B (high quality)" : "Llama 3B (fast)")")
            #endif
        }
    }

    /// Model ID based on current tier
    var modelId: String {
        currentTier.modelId ?? "mlx-community/Llama-3.2-3B-Instruct-4bit"
    }

    var modelContainer: MLXLMCommon.ModelContainer?

    // UI State
    var status = "Idle"
    var outputText = ""
    var isGenerating = false
    var memoryWarning: String?

    /// Whether the model is currently being downloaded/loaded
    var isDownloading: Bool {
        isLoadingModel
    }

    /// Device capability info for UI display
    var deviceCapabilityInfo: String {
        let detector = DeviceCapabilityDetector.shared
        return """
        Device: \(detector.deviceModel)
        Chip: \(detector.chipGeneration.displayName)
        Memory: \(String(format: "%.1f", detector.physicalMemoryGB)) GB
        Model Tier: \(currentTier.displayName)
        """
    }

    // Memory thresholds based on tier
    private var minimumRequiredMemory: UInt64 {
        UInt64(currentTier.estimatedMemoryGB * 1024 * 1024 * 1024)
    }

    // MARK: - Tier Detection

    /// Determine and set the best available tier for this device
    func determineBestTier() {
        guard !tierDetermined else { return }

        let detector = DeviceCapabilityDetector.shared

        // Default to Llama 3B (fast), upgrade to Qwen 4B if user prefers high quality
        var bestTier: AIModelTier

        if preferHighQualityModel && detector.canRunTier(.qwen4B) {
            // User wants high quality and device supports it
            bestTier = .qwen4B
            #if DEBUG
            print("🔧 Using high quality model: Qwen 4B")
            #endif
        } else if detector.canRunTier(.llama3B) {
            // Default: Llama 3B for best speed/quality balance
            bestTier = .llama3B
        } else {
            // Fallback for older devices
            bestTier = .llama1B
        }

        currentTier = bestTier
        tierDetermined = true

        #if DEBUG
        print("🎯 Selected AI Model Tier: \(currentTier.displayName)")
        print("📱 \(deviceCapabilityInfo)")
        #endif
    }

    /// Force a specific tier (for testing or user preference)
    func setTier(_ tier: AIModelTier) {
        let detector = DeviceCapabilityDetector.shared
        guard detector.canRunTier(tier) else {
            print("⚠️ Device cannot run tier: \(tier.displayName)")
            return
        }

        // Unload current model if changing tiers
        if tier != currentTier && modelContainer != nil {
            unloadModel()
        }

        currentTier = tier
        tierDetermined = true
        print("🔄 Switched to tier: \(tier.displayName)")
    }

    // Actual download/loading progress (0.0 to 1.0)
    private(set) var loadingProgress: Double = 0

    var isModelLoaded: Bool {
        modelContainer != nil
    }

    /// Track if model is currently being loaded to prevent duplicate load requests
    private var isLoadingModel: Bool = false

    // MARK: - Session-Aware Generation

    /// Create a session-aware generator for efficient sequential generation
    /// Uses KV cache reuse to speed up multi-meal generation
    /// - Returns: A new SessionAwareGenerator instance
    /// - Throws: ModelManagerError.modelNotLoaded if model is not loaded
    func createSessionGenerator() throws -> SessionAwareGenerator {
        guard let container = modelContainer else {
            throw ModelManagerError.modelNotLoaded
        }
        return SessionAwareGenerator(container: container)
    }

    // MARK: - Public Text Generation

    /// Generate text using the loaded model
    /// - Parameters:
    ///   - prompt: The prompt to send to the model
    ///   - maxTokens: Maximum tokens to generate (default 500)
    /// - Returns: The generated text response
    func generate(prompt: String, maxTokens: Int = 500) async throws -> String {
        guard let container = modelContainer else {
            throw ModelManagerError.modelNotLoaded
        }

        return try await container.perform { mlxContext in
            let input = try await mlxContext.processor.prepare(input: UserInput(prompt: prompt))
            let params = GenerateParameters(maxTokens: maxTokens, temperature: 0.1)

            let result = try MLXLMCommon.generate(
                input: input,
                parameters: params,
                context: mlxContext
            ) { (tokens: [Int]) -> GenerateDisposition in
                return .more
            }

            return result.output
        }
    }

    enum ModelManagerError: Error {
        case modelNotLoaded
    }

    // MARK: - On-Demand Loading

    /// Load model if needed and return whether it's available
    /// This method ensures the model is loaded before AI features are used
    @discardableResult
    func loadModelIfNeeded() async -> Bool {
        // Determine best tier if not already done
        if !tierDetermined {
            determineBestTier()
        }

        // Already loaded
        if modelContainer != nil {
            return true
        }

        // Already loading - wait for it
        if isLoadingModel {
            // Poll until loading completes
            while isLoadingModel {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
            return modelContainer != nil
        }

        // Start loading
        await loadModel()
        return modelContainer != nil
    }

    // MARK: - Memory Management

    /// Check available memory before loading model
    func checkMemoryAvailability() -> (available: UInt64, sufficient: Bool) {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        // Get physical memory
        let physicalMemory = ProcessInfo.processInfo.physicalMemory

        // Estimate available (this is approximate)
        let usedMemory = result == KERN_SUCCESS ? info.resident_size : 0
        let availableMemory = physicalMemory > usedMemory ? physicalMemory - usedMemory : physicalMemory / 2

        return (availableMemory, availableMemory >= minimumRequiredMemory)
    }

    /// Unload the model to free memory
    func unloadModel() {
        modelContainer = nil
        status = "Model unloaded"
        print("🗑️ Model unloaded to free memory")
    }

    func loadModel() async {
        // Determine best tier if not already done
        if !tierDetermined {
            determineBestTier()
        }

        guard modelContainer == nil else { return }
        guard !isLoadingModel else { return } // Prevent concurrent loads

        isLoadingModel = true
        defer { isLoadingModel = false }

        // Check memory first
        let (available, sufficient) = checkMemoryAvailability()
        let availableGB = Double(available) / (1024 * 1024 * 1024)
        let requiredGB = currentTier.estimatedMemoryGB

        if !sufficient {
            // Try to fall back to a smaller model
            if currentTier == .qwen4B && DeviceCapabilityDetector.shared.canRunTier(.llama3B) {
                print("⚠️ Insufficient memory for Qwen 4B, falling back to Llama 3B")
                currentTier = .llama3B
            } else if currentTier == .llama3B && DeviceCapabilityDetector.shared.canRunTier(.llama1B) {
                print("⚠️ Insufficient memory for Llama 3B, falling back to Llama 1B")
                currentTier = .llama1B
            } else {
                memoryWarning = String(format: "Low memory (%.1f GB available). Model requires ~%.1f GB. App may crash.", availableGB, requiredGB)
                print("⚠️ \(memoryWarning!)")
            }
        } else {
            memoryWarning = nil
        }

        status = "Downloading \(currentTier.displayName)..."
        loadingProgress = 0

        do {
            let config = ModelConfiguration(id: modelId)

            let tierName = self.currentTier.displayName
            self.modelContainer = try await LLMModelFactory.shared.loadContainer(
                configuration: config
            ) { [weak self] progress in
                // Update progress on main thread for UI
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.loadingProgress = progress.fractionCompleted

                    // Update status based on progress
                    if progress.fractionCompleted < 0.1 {
                        self.status = "Preparing download..."
                    } else if progress.fractionCompleted < 1.0 {
                        self.status = "Downloading \(tierName)... \(Int(progress.fractionCompleted * 100))%"
                    } else {
                        self.status = "Loading model..."
                    }
                }
            }

            self.loadingProgress = 1.0
            self.status = "\(currentTier.displayName) Ready!"
            print("✅ \(currentTier.displayName) Loaded")

        } catch {
            self.status = "Error: \(error.localizedDescription)"
            self.memoryWarning = "Failed to load model. Try closing other apps."

            // Try to fall back to smaller model on error
            if currentTier == .qwen4B {
                print("🔄 Falling back to Llama 3B after error")
                currentTier = .llama3B
                await loadModel()
            } else if currentTier == .llama3B {
                print("🔄 Falling back to Llama 1B after error")
                currentTier = .llama1B
                await loadModel()
            }
        }
    }
    
    /// Generation mode for controlling JSON output quality
    enum GenerationMode {
        case standard           // Basic generation with post-processing
        case withRepair         // Standard + automatic retry/repair on failure
        case constrained        // Grammar-constrained generation (experimental)
    }

    /// Current generation mode - can be changed by user
    var generationMode: GenerationMode = .withRepair

    // MARK: - Health Data Container

    /// Container for health data to inform diet generation
    struct HealthContext {
        var activeCalories: Double = 0
        var steps: Int = 0
        var currentWeight: Double?
        var workoutMinutes: Int = 0
        var adjustedCalorieTarget: Int?
    }

    // MARK: - Diet Generation with User Profile

    /// Generate diet using user profile for personalization
    func generateDiet(
        userPrompt: String,
        context: SwiftData.ModelContext,
        userProfile: UserProfile? = nil,
        healthContext: HealthContext? = nil
    ) async {
        guard let container = modelContainer else {
            self.status = "Model not loaded"
            return
        }

        self.isGenerating = true
        self.outputText = ""
        self.status = "Thinking..."

        // Build personalized system prompt
        let systemPrompt = buildSystemPrompt(userProfile: userProfile, healthContext: healthContext)

        let fullPrompt = """
        <|begin_of_text|><|start_header_id|>system<|end_header_id|>
        \(systemPrompt)
        <|eot_id|><|start_header_id|>user<|end_header_id|>
        \(userPrompt)
        <|eot_id|><|start_header_id|>assistant<|end_header_id|>
        {
        """

        do {
            let output: String

            switch generationMode {
            case .standard:
                output = try await generateStandard(container: container, prompt: fullPrompt)

            case .withRepair:
                output = try await ConstrainedJSONGenerator.generateWithRepair(
                    container: container,
                    prompt: fullPrompt,
                    maxTokens: 1500,  // Reduced for faster generation
                    temperature: 0.1,
                    maxRetries: 2,
                    onProgress: { progressStatus in
                        Task { @MainActor in
                            self.status = progressStatus
                        }
                    }
                )

            case .constrained:
                self.status = "Generating (constrained)..."
                output = try await ConstrainedJSONGenerator.generate(
                    container: container,
                    prompt: fullPrompt,
                    maxTokens: 2000,
                    temperature: 0.1
                )
            }

            self.outputText = output

            self.status = "Saving to Database..."
            saveDietToDatabase(jsonString: output, context: context, userProfile: userProfile)

        } catch {
            self.status = "Error: \(error)"
            print(error)
        }

        self.isGenerating = false
    }

    /// Build personalized system prompt based on user data
    private func buildSystemPrompt(userProfile: UserProfile?, healthContext: HealthContext? = nil) -> String {
        var prompt = """
        You are an expert nutritionist. OUTPUT VALID JSON ONLY - no markdown, no explanation, no code blocks.

        Create balanced meal plans with accurate nutritional information.

        Required JSON structure:
        {
          "days": [
            {
              "day": "Monday",
              "meals": [
                {
                  "type": "Breakfast",
                  "name": "Greek Yogurt Parfait",
                  "calories": 350,
                  "protein": 20,
                  "carbs": 45,
                  "fat": 10,
                  "ingredients": ["greek yogurt", "granola", "mixed berries", "honey"],
                  "prepTime": 5
                }
              ]
            }
          ]
        }
        """

        // Add user-specific context
        if let profile = userProfile {
            prompt += "\n\nUser Profile:"

            if let goal = profile.preferredGoal {
                prompt += "\n- Goal: \(goal.rawValue)"
            }

            if let calories = profile.dailyCalorieTarget {
                prompt += "\n- Daily calorie target: \(calories) kcal"
            }

            if !profile.dietaryRestrictions.isEmpty {
                prompt += "\n- Dietary restrictions: \(profile.dietaryRestrictions.joined(separator: ", "))"
                prompt += "\n- IMPORTANT: Do NOT include any ingredients that violate these restrictions"
            }

            if !profile.dislikedIngredients.isEmpty {
                prompt += "\n- Avoid these ingredients: \(profile.dislikedIngredients.joined(separator: ", "))"
            }

            if !profile.lovedIngredients.isEmpty {
                prompt += "\n- Preferred ingredients: \(profile.lovedIngredients.joined(separator: ", "))"
            }

            if !profile.preferredCuisines.isEmpty {
                prompt += "\n- Preferred cuisines: \(profile.preferredCuisines.joined(separator: ", "))"
            }
        }

        // Add health context for activity-aware recommendations
        if let health = healthContext {
            prompt += "\n\nActivity Data:"
            if health.activeCalories > 0 {
                prompt += "\n- Today's active calories burned: \(Int(health.activeCalories)) kcal"
            }
            if health.steps > 0 {
                prompt += "\n- Steps today: \(health.steps)"
            }
            if let weight = health.currentWeight {
                prompt += "\n- Current weight: \(String(format: "%.1f", weight)) kg"
            }
            if health.workoutMinutes > 0 {
                prompt += "\n- Workout minutes this week: \(health.workoutMinutes)"
            }
            if let adjusted = health.adjustedCalorieTarget {
                prompt += "\n- IMPORTANT: Adjusted calorie target based on activity: \(adjusted) kcal"
            }
        }

        prompt += """

        Rules:
        - Include 4 meals per day: Breakfast, Lunch, Snack, Dinner
        - Provide realistic macros (protein, carbs, fat in grams)
        - List 3-6 main ingredients per meal
        - prepTime is in minutes
        - Ensure daily totals match the requested calorie target
        - Start output immediately with { character
        - Respect all dietary restrictions strictly
        """

        return prompt
    }

    /// Standard generation without constraints
    private func generateStandard(container: MLXLMCommon.ModelContainer, prompt: String) async throws -> String {
        return try await container.perform { mlxContext in
            let input = try await mlxContext.processor.prepare(input: UserInput(prompt: prompt))
            let params = GenerateParameters(maxTokens: 2000, temperature: 0.1)

            let result = try MLXLMCommon.generate(
                input: input,
                parameters: params,
                context: mlxContext
            ) { (tokens: [Int]) -> GenerateDisposition in
                return .more
            }

            return result.output
        }
    }
    
    private func saveDietToDatabase(jsonString: String, context: SwiftData.ModelContext, userProfile: UserProfile? = nil) {
        // More robust JSON extraction
        let cleanJSON = extractJSON(from: jsonString)

        print("📝 Raw output length: \(jsonString.count)")
        print("📝 Extracted JSON length: \(cleanJSON.count)")
        print("📝 Raw output:\n\(jsonString)")
        print("📝 Extracted JSON:\n\(cleanJSON)")

        guard let data = cleanJSON.data(using: .utf8) else {
            print("❌ Error: Could not convert string to data")
            self.status = "Error processing data"
            return
        }

        do {
            let aiResponse = try JSONDecoder().decode(AIResponse.self, from: data)

            // Use user profile data if available
            let goal = userProfile?.preferredGoal ?? .weightLoss
            let calories = userProfile?.dailyCalorieTarget ?? 1800

            let planName = "\(goal.rawValue.capitalized) Plan - \(Date().formatted(date: .abbreviated, time: .omitted))"
            let newDietPlan = DietPlan(name: planName, goal: goal, calories: calories)
            context.insert(newDietPlan)

            for aiDay in aiResponse.days {
                let newDay = DailyPlan(date: Date(), dayName: aiDay.day)
                newDay.plan = newDietPlan
                context.insert(newDay)

                for aiMeal in aiDay.meals {
                    let type = MealType(rawValue: aiMeal.type) ?? .snack

                    let newMeal = Meal(
                        type: type,
                        name: aiMeal.name,
                        calories: aiMeal.calories,
                        protein: aiMeal.protein ?? 0,
                        carbs: aiMeal.carbs ?? 0,
                        fat: aiMeal.fat ?? 0
                    )
                    newMeal.ingredients = aiMeal.getMealIngredients()
                    newMeal.day = newDay
                    context.insert(newMeal)
                }
            }

            try context.save()

            print("✅ Saved to Database!")
            self.status = "Plan Saved!"

        } catch let decodingError as DecodingError {
            // Detailed decoding error information
            switch decodingError {
            case .keyNotFound(let key, let context):
                print("❌ Missing key '\(key.stringValue)' at: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
            case .typeMismatch(let type, let context):
                print("❌ Type mismatch: expected \(type) at: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
            case .valueNotFound(let type, let context):
                print("❌ Value not found: expected \(type) at: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
            case .dataCorrupted(let context):
                print("❌ Data corrupted at: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                print("   Debug description: \(context.debugDescription)")
            @unknown default:
                print("❌ Unknown decoding error: \(decodingError)")
            }
            self.status = "Error parsing plan"
        } catch {
            print("❌ Parsing Error: \(error)")
            self.status = "Error parsing plan"
        }
    }

    // MARK: - JSON Extraction Helper

    /// Extract JSON from model output, handling various formats
    private func extractJSON(from text: String) -> String {
        var cleaned = text

        // Remove markdown code blocks
        cleaned = cleaned.replacingOccurrences(of: "```json", with: "")
        cleaned = cleaned.replacingOccurrences(of: "```JSON", with: "")
        cleaned = cleaned.replacingOccurrences(of: "```", with: "")

        // Try to find JSON object by looking for { and }
        if let startIndex = cleaned.firstIndex(of: "{"),
           let endIndex = cleaned.lastIndex(of: "}") {
            let jsonRange = startIndex...endIndex
            cleaned = String(cleaned[jsonRange])
        }

        // Clean up common issues
        cleaned = cleaned
            .trimmingCharacters(in: .whitespacesAndNewlines)
            // Fix trailing commas before ] or }
            .replacingOccurrences(of: ",\\s*]", with: "]", options: .regularExpression)
            .replacingOccurrences(of: ",\\s*}", with: "}", options: .regularExpression)

        return cleaned
    }
}
