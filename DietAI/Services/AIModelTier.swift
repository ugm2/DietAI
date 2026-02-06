import Foundation
import UIKit

// MARK: - AI Model Tier
/// Represents the available AI model tiers from best to fallback
/// Note: Apple Intelligence is disabled due to unreliable guardrails
enum AIModelTier: Int, CaseIterable, Comparable {
    case appleIntelligence = 0  // Disabled - kept for enum stability
    case qwen4B = 1             // Capable devices (6GB+ RAM, A15+ chip)
    case llama3B = 2            // Mid-tier devices (4GB+ RAM, A14+ chip)
    case llama1B = 3            // Older/lower-end devices (fallback)

    static func < (lhs: AIModelTier, rhs: AIModelTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var displayName: String {
        switch self {
        case .appleIntelligence:
            return "Apple Intelligence"
        case .qwen4B:
            return "Qwen 4B"
        case .llama3B:
            return "Llama 3B"
        case .llama1B:
            return "Llama 1B"
        }
    }

    var modelId: String? {
        switch self {
        case .appleIntelligence:
            return nil // Uses Foundation Models API
        case .qwen4B:
            return "mlx-community/Qwen3-4B-Instruct-2507-4bit"
        case .llama3B:
            return "mlx-community/Llama-3.2-3B-Instruct-4bit"
        case .llama1B:
            return "mlx-community/Llama-3.2-1B-Instruct-4bit"
        }
    }

    var estimatedMemoryGB: Double {
        switch self {
        case .appleIntelligence:
            return 0 // System-managed
        case .qwen4B:
            return 3.0
        case .llama3B:
            return 2.5
        case .llama1B:
            return 1.2
        }
    }

    var description: String {
        switch self {
        case .appleIntelligence:
            return "Apple's on-device AI with guaranteed structured output"
        case .qwen4B:
            return "High-quality model with excellent JSON and tool support"
        case .llama3B:
            return "Balanced model for most devices"
        case .llama1B:
            return "Lightweight model for older devices"
        }
    }
}

// MARK: - Device Capability Detection
@MainActor
final class DeviceCapabilityDetector {
    static let shared = DeviceCapabilityDetector()

    private init() {}

    // MARK: - Device Info

    /// Physical memory in GB
    var physicalMemoryGB: Double {
        Double(ProcessInfo.processInfo.physicalMemory) / (1024 * 1024 * 1024)
    }

    /// Device model identifier (e.g., "iPhone14,2")
    var deviceModel: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0) ?? "Unknown"
            }
        }
    }

    /// iOS version
    var iOSVersion: OperatingSystemVersion {
        ProcessInfo.processInfo.operatingSystemVersion
    }

    /// Check if running iOS 26 or later
    /// NOTE: iOS 26 is not yet released. This will return false until the SDK is available.
    var isiOS26OrLater: Bool {
        // Check actual runtime iOS version (iOS 26 = major version 26)
        // Foundation Models requires iOS 26 which is not yet available
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return version.majorVersion >= 26
    }

    // MARK: - Chip Detection

    /// Detected Apple chip generation
    var chipGeneration: AppleChipGeneration {
        let model = deviceModel

        // iPhone models
        if model.hasPrefix("iPhone") {
            // iPhone 16 Pro/Pro Max = A18 Pro (iPhone17,1 and iPhone17,2)
            // iPhone 16/16 Plus = A18 (iPhone17,3 and iPhone17,4)
            if model.hasPrefix("iPhone17") {
                return .a18
            }
            // iPhone 15 Pro/Pro Max = A17 Pro (iPhone16,1 and iPhone16,2)
            if model == "iPhone16,1" || model == "iPhone16,2" {
                return .a17Pro
            }
            // iPhone 15/15 Plus = A16 (iPhone15,4 and iPhone15,5)
            if model == "iPhone15,4" || model == "iPhone15,5" {
                return .a16
            }
            // iPhone 14 Pro/Pro Max = A16 (iPhone15,2 and iPhone15,3)
            if model == "iPhone15,2" || model == "iPhone15,3" {
                return .a16
            }
            // iPhone 14/14 Plus = A15 (iPhone14,7 and iPhone14,8)
            if model == "iPhone14,7" || model == "iPhone14,8" {
                return .a15
            }
            // iPhone 13 series = A15 (iPhone14,2 through iPhone14,5)
            if model.hasPrefix("iPhone14") {
                return .a15
            }
            // iPhone SE 3rd gen = A15 (iPhone14,6)
            if model == "iPhone14,6" {
                return .a15
            }
            // iPhone 12 series = A14 (iPhone13,1 through iPhone13,4)
            if model.hasPrefix("iPhone13") {
                return .a14
            }
            // iPhone 11 series = A13 (iPhone12,1 through iPhone12,8)
            if model.hasPrefix("iPhone12") {
                return .a13
            }
        }

        // iPad models with M chips
        if model.hasPrefix("iPad") {
            // iPad Pro M4 (iPad16,x)
            if model.hasPrefix("iPad16") {
                return .m4
            }
            // iPad Pro M2 / iPad Air M2 (iPad14,x)
            if model.hasPrefix("iPad14") {
                return .m2
            }
            // iPad Pro M1 / iPad Air M1 (iPad13,x)
            if model.hasPrefix("iPad13") {
                return .m1
            }
        }

        // Simulator - treat as capable
        if model == "x86_64" || model == "arm64" {
            return .a17Pro
        }

        return .older
    }

    // MARK: - Apple Intelligence Check (Disabled)

    /// Apple Intelligence is disabled due to unreliable guardrails
    var isAppleIntelligenceAvailable: Bool {
        return false
    }

    /// Apple Intelligence is disabled due to unreliable guardrails
    var isAppleIntelligenceEnabled: Bool {
        return false
    }

    // MARK: - Tier Selection

    /// Determine the best available AI model tier for this device
    /// Defaults to Llama 3B for best speed/quality balance
    func determineBestTier() -> AIModelTier {
        let memoryGB = physicalMemoryGB
        let chip = chipGeneration

        #if DEBUG
        print("📱 Device: \(deviceModel), Memory: \(String(format: "%.1f", memoryGB)) GB, Chip: \(chip.displayName)")
        #endif

        // Llama 3B: Best speed/quality balance (preferred default)
        // Requires 4GB+ RAM and A14+ chip
        if memoryGB >= 4.0 && chip >= .a14 {
            return .llama3B
        }

        // Fallback to Llama 1B for older devices
        return .llama1B
    }

    /// Check if device can run a specific tier
    func canRunTier(_ tier: AIModelTier) -> Bool {
        let memoryGB = physicalMemoryGB
        let chip = chipGeneration

        switch tier {
        case .appleIntelligence:
            return false // Apple Intelligence is disabled
        case .qwen4B:
            return memoryGB >= 6.0 && chip >= .a15
        case .llama3B:
            return memoryGB >= 4.0 && chip >= .a14
        case .llama1B:
            return true // Always available as fallback
        }
    }
}

// MARK: - Apple Chip Generation
enum AppleChipGeneration: Int, Comparable {
    case older = 0
    case a13 = 1
    case a14 = 2
    case a15 = 3
    case a16 = 4
    case a17Pro = 5
    case a18 = 6
    case m1 = 10
    case m2 = 11
    case m3 = 12
    case m4 = 13

    static func < (lhs: AppleChipGeneration, rhs: AppleChipGeneration) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var displayName: String {
        switch self {
        case .older: return "A12 or older"
        case .a13: return "A13 Bionic"
        case .a14: return "A14 Bionic"
        case .a15: return "A15 Bionic"
        case .a16: return "A16 Bionic"
        case .a17Pro: return "A17 Pro"
        case .a18: return "A18 / A18 Pro"
        case .m1: return "M1"
        case .m2: return "M2"
        case .m3: return "M3"
        case .m4: return "M4"
        }
    }

    var supportsAppleIntelligence: Bool {
        switch self {
        case .a17Pro, .a18, .m1, .m2, .m3, .m4:
            return true
        default:
            return false
        }
    }
}
