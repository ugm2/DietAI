import Foundation

// MARK: - Vision Model Tier
/// Represents the available VLM tiers for food image analysis
/// Mirrors AIModelTier pattern for LLMs
enum VisionModelTier: Int, CaseIterable, Comparable {
    case vlmQuality = 0  // Gemma3-4B - Google's latest, best quality
    case vlmFast = 1     // Qwen2.5-VL-3B - Good balance

    static func < (lhs: VisionModelTier, rhs: VisionModelTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var displayName: String {
        switch self {
        case .vlmQuality:
            return "Gemma3 4B"
        case .vlmFast:
            return "Qwen2.5-VL 3B"
        }
    }

    var modelId: String {
        switch self {
        case .vlmQuality:
            // Gemma3 4B - Google's latest VLM, better visual understanding
            return "mlx-community/gemma-3-4b-it-qat-4bit"
        case .vlmFast:
            return "mlx-community/Qwen2.5-VL-3B-Instruct-4bit"
        }
    }

    var estimatedMemoryGB: Double {
        switch self {
        case .vlmQuality:
            return 4.0
        case .vlmFast:
            return 3.0
        }
    }

    var description: String {
        switch self {
        case .vlmQuality:
            return "Google's latest vision model for best food recognition"
        case .vlmFast:
            return "Fast vision model for quick food estimation"
        }
    }
}

// MARK: - Vision Model Tier Detection Extension
extension DeviceCapabilityDetector {
    /// Determine the best available VLM tier for this device
    func determineBestVLMTier() -> VisionModelTier {
        let memoryGB = physicalMemoryGB
        let chip = chipGeneration

        #if DEBUG
        print("📷 VLM Tier Detection - Memory: \(String(format: "%.1f", memoryGB)) GB, Chip: \(chip.displayName)")
        #endif

        // Use quality tier if device has enough memory and recent chip
        if memoryGB >= 6.0 && chip >= .a15 {
            return .vlmQuality
        }

        // Default to fast tier
        return .vlmFast
    }

    /// Check if device can run a specific VLM tier
    func canRunVLMTier(_ tier: VisionModelTier) -> Bool {
        let memoryGB = physicalMemoryGB
        let chip = chipGeneration

        switch tier {
        case .vlmQuality:
            return memoryGB >= 6.0 && chip >= .a15
        case .vlmFast:
            return chip >= .a14  // Fast model runs on most devices
        }
    }
}
