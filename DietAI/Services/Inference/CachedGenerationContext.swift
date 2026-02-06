import Foundation
import MLXLMCommon

/// Protocol for generation contexts that support KV cache reuse
/// Enables prefilling a system prompt once and reusing the cache across multiple generations
@MainActor
protocol CachedGenerationContext {
    /// Whether the cache has been prefilled with a system prompt
    var isPrefilled: Bool { get }

    /// Number of tokens in the prefilled cache
    var prefillTokenCount: Int { get }

    /// Prefill the cache with a system prompt
    /// This runs a forward pass on the system prompt and stores the KV cache state
    /// - Parameter systemPrompt: The system prompt to prefill
    func prefillSystemPrompt(_ systemPrompt: String) async throws

    /// Generate text using the cached system prompt
    /// Appends user prompt to existing cache, generates, and trims back to prefill point
    /// - Parameters:
    ///   - userPrompt: The user-specific prompt to append
    ///   - maxTokens: Maximum tokens to generate
    ///   - temperature: Sampling temperature
    /// - Returns: The generated text
    func generateWithCache(
        userPrompt: String,
        maxTokens: Int,
        temperature: Float
    ) async throws -> String

    /// Reset the cache, clearing all prefilled state
    func resetCache()
}
