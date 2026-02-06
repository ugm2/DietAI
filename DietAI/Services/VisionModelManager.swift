import Foundation
import MLX
import MLXVLM
import MLXLMCommon
import SwiftUI

/// VisionModelManager manages vision language model loading and inference for food image analysis.
/// Follows the same patterns as ModelManager for LLMs.
@MainActor
@Observable
class VisionModelManager {
    static let shared = VisionModelManager()

    // MARK: - Model State

    /// The current VLM tier being used
    private(set) var currentTier: VisionModelTier = .vlmFast

    /// Whether we've determined the best tier for this device
    private var tierDetermined: Bool = false

    /// The loaded VLM container
    var visionContainer: MLXLMCommon.ModelContainer?

    // MARK: - UI State

    var status = "Idle"
    var memoryWarning: String?

    /// Whether the model is currently being downloaded/loaded
    var isDownloading: Bool {
        isLoadingModel
    }

    /// Actual download/loading progress (0.0 to 1.0)
    private(set) var loadingProgress: Double = 0

    var isModelLoaded: Bool {
        visionContainer != nil
    }

    /// Track if model is currently being loaded to prevent duplicate load requests
    private var isLoadingModel: Bool = false

    // MARK: - Model ID

    var modelId: String {
        currentTier.modelId
    }

    // MARK: - Memory Thresholds

    private var minimumRequiredMemory: UInt64 {
        UInt64(currentTier.estimatedMemoryGB * 1024 * 1024 * 1024)
    }

    // MARK: - Memory Management Strategy

    /// Strategy for loading VLM alongside LLM
    enum VLMLoadStrategy {
        case concurrent    // Both models can be in memory (high-end devices)
        case sequential    // Need to unload LLM, load VLM, then restore
    }

    var loadStrategy: VLMLoadStrategy {
        let detector = DeviceCapabilityDetector.shared
        let memoryGB = detector.physicalMemoryGB

        // If device has 8GB+ RAM, can run both VLM and LLM
        // Otherwise, need to swap
        return memoryGB >= 8.0 ? .concurrent : .sequential
    }

    // MARK: - Device Info

    var deviceCapabilityInfo: String {
        let detector = DeviceCapabilityDetector.shared
        return """
        Device: \(detector.deviceModel)
        Chip: \(detector.chipGeneration.displayName)
        Memory: \(String(format: "%.1f", detector.physicalMemoryGB)) GB
        VLM Tier: \(currentTier.displayName)
        Load Strategy: \(loadStrategy == .concurrent ? "Concurrent" : "Sequential")
        """
    }

    // MARK: - Tier Detection

    /// Determine and set the best available tier for this device
    func determineBestTier() {
        guard !tierDetermined else { return }

        let detector = DeviceCapabilityDetector.shared
        currentTier = detector.determineBestVLMTier()
        tierDetermined = true

        #if DEBUG
        print("📷 Selected VLM Tier: \(currentTier.displayName)")
        print("📱 \(deviceCapabilityInfo)")
        #endif
    }

    /// Force a specific tier (for testing or user preference)
    func setTier(_ tier: VisionModelTier) {
        let detector = DeviceCapabilityDetector.shared
        guard detector.canRunVLMTier(tier) else {
            print("⚠️ Device cannot run VLM tier: \(tier.displayName)")
            return
        }

        // Unload current model if changing tiers
        if tier != currentTier && visionContainer != nil {
            unloadModel()
        }

        currentTier = tier
        tierDetermined = true
        print("🔄 Switched to VLM tier: \(tier.displayName)")
    }

    // MARK: - Loading

    /// Load model if needed and return whether it's available
    @discardableResult
    func loadModelIfNeeded() async -> Bool {
        // Determine best tier if not already done
        if !tierDetermined {
            determineBestTier()
        }

        // Already loaded
        if visionContainer != nil {
            return true
        }

        // Already loading - wait for it
        if isLoadingModel {
            while isLoadingModel {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
            return visionContainer != nil
        }

        // Start loading
        await loadModel()
        return visionContainer != nil
    }

    /// Load the VLM with memory management
    func loadModel() async {
        // Determine best tier if not already done
        if !tierDetermined {
            determineBestTier()
        }

        guard visionContainer == nil else { return }
        guard !isLoadingModel else { return }

        isLoadingModel = true
        defer { isLoadingModel = false }

        // Handle sequential loading strategy - unload LLM if needed
        if loadStrategy == .sequential && ModelManager.shared.isModelLoaded {
            #if DEBUG
            print("📷 Sequential strategy: Unloading LLM to make room for VLM")
            #endif
            ModelManager.shared.unloadModel()
        }

        // Check memory availability
        let (available, sufficient) = checkMemoryAvailability()
        let availableGB = Double(available) / (1024 * 1024 * 1024)
        let requiredGB = currentTier.estimatedMemoryGB

        if !sufficient {
            // Try to fall back to smaller model
            if currentTier == .vlmQuality && DeviceCapabilityDetector.shared.canRunVLMTier(.vlmFast) {
                print("⚠️ Insufficient memory for Qwen VL, falling back to FastVLM")
                currentTier = .vlmFast
            } else {
                memoryWarning = String(format: "Low memory (%.1f GB available). VLM requires ~%.1f GB.", availableGB, requiredGB)
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
            self.visionContainer = try await VLMModelFactory.shared.loadContainer(
                configuration: config
            ) { [weak self] progress in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.loadingProgress = progress.fractionCompleted

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
            print("✅ VLM \(currentTier.displayName) Loaded")

        } catch {
            self.status = "Error: \(error.localizedDescription)"
            self.memoryWarning = "Failed to load VLM. Try closing other apps."

            // Try to fall back to smaller model on error
            if currentTier == .vlmQuality {
                print("🔄 Falling back to FastVLM after error")
                currentTier = .vlmFast
                await loadModel()
            }
        }
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

        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        let usedMemory = result == KERN_SUCCESS ? info.resident_size : 0
        let availableMemory = physicalMemory > usedMemory ? physicalMemory - usedMemory : physicalMemory / 2

        return (availableMemory, availableMemory >= minimumRequiredMemory)
    }

    /// Unload the model to free memory
    func unloadModel() {
        visionContainer = nil
        status = "Vision model unloaded"
        print("🗑️ VLM unloaded to free memory")
    }

    /// Called after VLM operation completes - release if using sequential strategy
    func releaseIfNeeded() {
        if loadStrategy == .sequential {
            unloadModel()
            #if DEBUG
            print("📷 Sequential strategy: Released VLM, LLM will reload on-demand")
            #endif
        }
    }
}
