import SwiftUI
import SwiftData

/// View shown when reinstalling the app and iCloud data exists
/// Allows user to choose between restoring their data or starting fresh
struct CloudRestoreChoiceView: View {
    @Environment(\.modelContext) private var modelContext
    let onChoiceMade: (Bool) -> Void // true = restore, false = start fresh

    @State private var isProcessing = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Icon
            Image(systemName: "icloud.fill")
                .font(.system(size: 80))
                .foregroundStyle(.blue)
                .padding(.bottom, 8)

            // Title
            Text("Welcome Back!")
                .font(.largeTitle)
                .fontWeight(.bold)

            // Description
            Text("We found your Diet AI data in iCloud. Would you like to restore it or start fresh?")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            // Buttons
            VStack(spacing: 16) {
                // Restore button (primary)
                Button {
                    handleRestore()
                } label: {
                    HStack {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("Restore My Data")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
                }
                .disabled(isProcessing)

                // Start fresh button (secondary)
                Button {
                    handleStartFresh()
                } label: {
                    HStack {
                        Image(systemName: "sparkles")
                        Text("Start Fresh")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .foregroundStyle(.primary)
                    .cornerRadius(12)
                }
                .disabled(isProcessing)

                // Warning text for start fresh
                Text("Starting fresh will delete your existing meal plans and preferences from all devices.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
        .overlay {
            if isProcessing {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                ProgressView("Processing...")
                    .padding()
                    .background(.regularMaterial)
                    .cornerRadius(12)
            }
        }
    }

    private func handleRestore() {
        // Mark choice as made and let sync continue normally
        CloudRestoreManager.markChoiceMade(restore: true)
        onChoiceMade(true)
    }

    private func handleStartFresh() {
        isProcessing = true

        Task {
            // Delete all existing data
            await clearAllData()

            await MainActor.run {
                // Mark choice as made
                CloudRestoreManager.markChoiceMade(restore: false)
                isProcessing = false
                onChoiceMade(false)
            }
        }
    }

    @MainActor
    private func clearAllData() async {
        // Delete all user profiles
        let profileDescriptor = FetchDescriptor<UserProfile>()
        if let profiles = try? modelContext.fetch(profileDescriptor) {
            for profile in profiles {
                modelContext.delete(profile)
            }
        }

        // Delete all diet plans (cascade will delete daily plans and meals)
        let planDescriptor = FetchDescriptor<DietPlan>()
        if let plans = try? modelContext.fetch(planDescriptor) {
            for plan in plans {
                modelContext.delete(plan)
            }
        }

        // Delete shopping list items
        let shoppingDescriptor = FetchDescriptor<ShoppingListItem>()
        if let items = try? modelContext.fetch(shoppingDescriptor) {
            for item in items {
                modelContext.delete(item)
            }
        }

        // Delete meal logs
        let logDescriptor = FetchDescriptor<MealLog>()
        if let logs = try? modelContext.fetch(logDescriptor) {
            for log in logs {
                modelContext.delete(log)
            }
        }

        try? modelContext.save()

        #if DEBUG
        print("🗑️ All data cleared for fresh start")
        #endif
    }
}

// MARK: - Cloud Restore Manager

/// Manages the cloud restore choice state
enum CloudRestoreManager {
    private static let choiceMadeKey = "cloudRestoreChoiceMade"
    private static let choiceWasRestoreKey = "cloudRestoreChoiceWasRestore"
    private static let appVersionKey = "lastLaunchedAppVersion"

    /// Check if we need to show the restore choice
    /// Returns true if this appears to be a reinstall with existing iCloud data
    static func shouldShowRestoreChoice(modelContext: ModelContext) -> Bool {
        let defaults = UserDefaults.standard

        // If choice was already made, don't show again
        if defaults.bool(forKey: choiceMadeKey) {
            return false
        }

        // Check if there's existing data (indicates iCloud sync brought data)
        let hasExistingData = checkForExistingData(modelContext: modelContext)

        #if DEBUG
        print("☁️ CloudRestoreManager: hasExistingData = \(hasExistingData), choiceMade = \(defaults.bool(forKey: choiceMadeKey))")
        #endif

        return hasExistingData
    }

    /// Mark that the user made their choice
    static func markChoiceMade(restore: Bool) {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: choiceMadeKey)
        defaults.set(restore, forKey: choiceWasRestoreKey)

        #if DEBUG
        print("☁️ CloudRestoreManager: Choice made - \(restore ? "Restore" : "Start Fresh")")
        #endif
    }

    /// Check if there's any existing data in the database
    private static func checkForExistingData(modelContext: ModelContext) -> Bool {
        // Check for user profiles
        let profileDescriptor = FetchDescriptor<UserProfile>()
        if let profiles = try? modelContext.fetch(profileDescriptor), !profiles.isEmpty {
            return true
        }

        // Check for diet plans
        let planDescriptor = FetchDescriptor<DietPlan>()
        if let plans = try? modelContext.fetch(planDescriptor), !plans.isEmpty {
            return true
        }

        return false
    }

    /// Reset the choice (for testing)
    static func resetChoice() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: choiceMadeKey)
        defaults.removeObject(forKey: choiceWasRestoreKey)
    }
}
