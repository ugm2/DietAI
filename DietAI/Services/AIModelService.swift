import Foundation
import MLX
import MLXLLM
import MLXLMCommon

// MARK: - AI Model Service Protocol
protocol AIModelServiceProtocol {
    var isLoaded: Bool { get }
    var loadingProgress: Double { get }
    func loadModel() async throws
    func generate(prompt: String, maxTokens: Int, temperature: Float) async throws -> String
}

// MARK: - AI Model Service Implementation
/// This service shares the model container with ModelManager to avoid loading the model twice
@MainActor
@Observable
final class AIModelService: AIModelServiceProtocol {
    static let shared = AIModelService()

    // Model Configuration - now dynamic based on tier
    var modelId: String {
        ModelManager.shared.modelId
    }

    /// Current model tier
    var currentTier: AIModelTier {
        ModelManager.shared.currentTier
    }

    // State
    private(set) var loadingProgress: Double = 0
    private(set) var status: String = "Idle"

    private init() {}

    /// Check if model is loaded
    var isLoaded: Bool {
        ModelManager.shared.isModelLoaded
    }

    /// Get the model container from ModelManager (shared instance)
    private var modelContainer: MLXLMCommon.ModelContainer? {
        ModelManager.shared.modelContainer
    }

    func loadModel() async throws {
        let tierName = currentTier.displayName

        if !ModelManager.shared.isModelLoaded {
            status = "Loading \(tierName)..."
            await ModelManager.shared.loadModel()
        }
        status = "\(tierName) Ready"
    }

    func generate(prompt: String, maxTokens: Int = 2000, temperature: Float = 0.1) async throws -> String {
        // Ensure MLX model is loaded
        guard let container = modelContainer else {
            // Try to load the model first
            try await loadModel()
            guard let container = modelContainer else {
                throw AIModelError.modelNotLoaded
            }
            return try await performGeneration(container: container, prompt: prompt, maxTokens: maxTokens, temperature: temperature)
        }

        return try await performGeneration(container: container, prompt: prompt, maxTokens: maxTokens, temperature: temperature)
    }

    private func performGeneration(
        container: MLXLMCommon.ModelContainer,
        prompt: String,
        maxTokens: Int,
        temperature: Float
    ) async throws -> String {
        let output = try await container.perform { mlxContext in
            let input = try await mlxContext.processor.prepare(input: UserInput(prompt: prompt))
            let params = GenerateParameters(maxTokens: maxTokens, temperature: temperature)

            let result = try MLXLMCommon.generate(
                input: input,
                parameters: params,
                context: mlxContext
            ) { (tokens: [Int]) -> GenerateDisposition in
                if tokens.count > 1000 {
                    return .stop
                }
                return .more
            }

            return result.output
        }

        return output
    }
}

// MARK: - Errors
enum AIModelError: LocalizedError {
    case modelNotLoaded
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "AI model is not loaded. Please wait for the model to download."
        case .generationFailed(let reason):
            return "Generation failed: \(reason)"
        }
    }
}
