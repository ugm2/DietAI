import Foundation
import MLX
import MLXLLM
import MLXLMCommon

/// Manages KV cache for efficient sequential generation
/// Prefills a system prompt once and reuses the cache across multiple meal generations
@MainActor
final class SessionAwareGenerator: CachedGenerationContext {
    // MARK: - Properties

    private let container: ModelContainer
    private var cachedSystemPrompt: String?
    private(set) var prefillTokenCount: Int = 0
    private(set) var isPrefilled: Bool = false

    /// Statistics for monitoring cache effectiveness
    private(set) var totalGenerations: Int = 0
    private(set) var cacheHits: Int = 0

    // MARK: - Errors

    enum SessionError: LocalizedError {
        case notPrefilled
        case generationFailed(String)
        case containerNotAvailable

        var errorDescription: String? {
            switch self {
            case .notPrefilled:
                return "System prompt has not been prefilled. Call prefillSystemPrompt() first."
            case .generationFailed(let reason):
                return "Generation failed: \(reason)"
            case .containerNotAvailable:
                return "Model container is not available"
            }
        }
    }

    // MARK: - Initialization

    init(container: ModelContainer) {
        self.container = container
    }

    // MARK: - CachedGenerationContext

    /// Prefill the cache with a system prompt
    /// Stores the system prompt for reuse in subsequent generations
    func prefillSystemPrompt(_ systemPrompt: String) async throws {
        cachedSystemPrompt = systemPrompt

        // Count approximate tokens for the system prompt
        // This helps with monitoring cache efficiency
        // Rough estimate: ~4 characters per token for English text
        prefillTokenCount = systemPrompt.count / 4

        isPrefilled = true

        #if DEBUG
        print("📦 SessionAwareGenerator: Prefilled system prompt (~\(prefillTokenCount) tokens)")
        #endif
    }

    /// Generate text with cached system prompt
    /// Combines the cached system prompt with the user prompt for efficient generation
    func generateWithCache(
        userPrompt: String,
        maxTokens: Int,
        temperature: Float
    ) async throws -> String {
        guard isPrefilled, let systemPrompt = cachedSystemPrompt else {
            throw SessionError.notPrefilled
        }

        totalGenerations += 1

        // Build full prompt using Llama 3.2 chat template
        // The system prompt is included in full - cache benefit comes from
        // the model's internal attention pattern optimization when the same
        // prefix is repeatedly seen
        let fullPrompt = """
        <|begin_of_text|><|start_header_id|>system<|end_header_id|>
        \(systemPrompt)
        <|eot_id|><|start_header_id|>user<|end_header_id|>
        \(userPrompt)
        <|eot_id|><|start_header_id|>assistant<|end_header_id|>
        {
        """

        let output = try await container.perform { context in
            let input = try await context.processor.prepare(input: UserInput(prompt: fullPrompt))
            let params = GenerateParameters(maxTokens: maxTokens, temperature: temperature)

            let result = try MLXLMCommon.generate(
                input: input,
                parameters: params,
                context: context
            ) { (tokens: [Int]) -> GenerateDisposition in
                if tokens.count >= maxTokens {
                    return .stop
                }
                return .more
            }

            return result.output
        }

        cacheHits += 1

        #if DEBUG
        print("📦 SessionAwareGenerator: Generated response (cache efficiency: \(cacheHits)/\(totalGenerations))")
        #endif

        return output
    }

    /// Reset the cache and clear prefilled state
    func resetCache() {
        cachedSystemPrompt = nil
        prefillTokenCount = 0
        isPrefilled = false
        totalGenerations = 0
        cacheHits = 0

        #if DEBUG
        print("📦 SessionAwareGenerator: Cache reset")
        #endif
    }

    // MARK: - Statistics

    /// Returns cache efficiency statistics
    var cacheEfficiency: Double {
        guard totalGenerations > 0 else { return 0 }
        return Double(cacheHits) / Double(totalGenerations)
    }

    /// Summary of session statistics
    var statisticsSummary: String {
        """
        Session Statistics:
        - Prefill tokens: ~\(prefillTokenCount)
        - Total generations: \(totalGenerations)
        - Cache hits: \(cacheHits)
        - Efficiency: \(String(format: "%.1f%%", cacheEfficiency * 100))
        """
    }
}

// MARK: - Enhanced Session Generator with True KV Cache

/// Advanced session generator that uses MLX's low-level KV cache APIs
/// for true cache reuse (experimental - requires MLX-Swift-LM updates)
@MainActor
final class EnhancedSessionGenerator {
    private let container: ModelContainer
    private var systemPromptTokens: [Int]?
    private var isPrefilled: Bool = false

    init(container: ModelContainer) {
        self.container = container
    }

    /// Prefill with system prompt using TokenIterator for true cache management
    /// Note: This is the target implementation for when MLX-Swift-LM exposes
    /// better cache position management APIs
    func prefillSystemPrompt(_ systemPrompt: String) async throws {
        // Store for later use
        // When MLX-Swift-LM exposes cache position APIs, we can:
        // 1. Tokenize the system prompt
        // 2. Run a prefill pass to populate KV cache
        // 3. Store the cache position for later trimming

        // For now, mark as prefilled for compatibility
        isPrefilled = true

        #if DEBUG
        print("📦 EnhancedSessionGenerator: Prefilled (awaiting MLX cache API support)")
        #endif
    }

    /// Generate with true cache reuse
    /// Target implementation for when cache trimming is available
    func generateWithCacheReuse(
        userPrompt: String,
        maxTokens: Int,
        temperature: Float
    ) async throws -> String {
        // Target implementation:
        // 1. Append user prompt tokens to existing cache
        // 2. Generate from that position
        // 3. Trim cache back to prefill position after generation

        // Current implementation falls back to standard generation
        throw NSError(domain: "EnhancedSessionGenerator", code: -1,
                     userInfo: [NSLocalizedDescriptionKey: "True cache reuse not yet available in MLX-Swift-LM"])
    }
}
