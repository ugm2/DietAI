import SwiftUI
import SwiftData

// MARK: - Me View (Profile + Settings Combined)
// Note: This view is kept for backwards compatibility but the main navigation
// now uses 2 tabs with settings accessible via gear icon
struct MeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query var userProfiles: [UserProfile]

    @State private var showEditProfile = false
    @State private var showHealthKit = false

    private var userProfile: UserProfile? { userProfiles.first }

    var body: some View {
        NavigationStack {
            List {
                // Profile header
                Section {
                    profileHeader
                }

                // Health
                Section("Health") {
                    NavigationLink {
                        HealthKitConnectionView()
                    } label: {
                        Label {
                            HStack {
                                Text("Apple Health")
                                Spacer()
                                if HealthKitService.shared.isAuthorized {
                                    Text("Connected")
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                }
                            }
                        } icon: {
                            Image(systemName: "heart.fill")
                                .foregroundStyle(.red)
                        }
                    }
                }

                // Preferences
                Section("Preferences") {
                    NavigationLink {
                        if let profile = userProfile {
                            ProfileSetupView(userProfile: profile, onComplete: {})
                        } else {
                            OnboardingView(onComplete: {})
                        }
                    } label: {
                        Label("Edit Profile", systemImage: "person.fill")
                    }

                    NavigationLink {
                        DietaryRestrictionsView()
                    } label: {
                        Label {
                            HStack {
                                Text("Dietary Restrictions")
                                Spacer()
                                if let profile = userProfile, !profile.dietaryRestrictionsArray.isEmpty {
                                    Text("\(profile.dietaryRestrictionsArray.count)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } icon: {
                            Image(systemName: "leaf.fill")
                                .foregroundStyle(.green)
                        }
                    }
                }

                // Data
                Section("Data") {
                    NavigationLink {
                        ShoppingListView()
                    } label: {
                        Label("Shopping List", systemImage: "cart.fill")
                    }

                    NavigationLink {
                        BackupRestoreView()
                    } label: {
                        Label("Backup & Restore", systemImage: "icloud.fill")
                    }
                }

                // AI Model
                Section("AI") {
                    AIModelStatusRow()
                    AIModelPreferenceToggle()
                }

                // About
                Section("About") {
                    HStack {
                        Label("Version", systemImage: "info.circle")
                        Spacer()
                        Text("2.0.0")
                            .foregroundStyle(.secondary)
                    }

                    Link(destination: URL(string: "https://github.com")!) {
                        Label("GitHub", systemImage: "link")
                    }
                }
            }
            .navigationTitle("Me")
        }
    }

    // MARK: - Profile Header
    private var profileHeader: some View {
        HStack(spacing: 16) {
            // Avatar
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 60, height: 60)

                Text(initials)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                if let profile = userProfile {
                    Text(displayName(profile))
                        .font(.headline)

                    HStack(spacing: 8) {
                        if let goal = profile.goalType {
                            Text(goal.rawValue)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.1))
                                .foregroundStyle(.blue)
                                .cornerRadius(8)
                        }

                        if let calories = profile.dailyCalorieTarget {
                            Text("\(calories) kcal")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("Set Up Profile")
                        .font(.headline)

                    Text("Personalize your experience")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 8)
    }

    // MARK: - Helpers
    private var initials: String {
        if let profile = userProfile {
            // Use first letter of goal or "U"
            return String(profile.goal.prefix(1)).uppercased()
        }
        return "?"
    }

    private func displayName(_ profile: UserProfile) -> String {
        if let age = profile.age {
            return "\(profile.goal) • \(age) years old"
        }
        return profile.goal
    }
}

// MARK: - Dietary Restrictions View
struct DietaryRestrictionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query var userProfiles: [UserProfile]

    @State private var selectedRestrictions: Set<String> = []

    private var userProfile: UserProfile? { userProfiles.first }

    let restrictions = [
        ("Vegetarian", "leaf.fill", Color.green),
        ("Vegan", "leaf.circle.fill", Color.green),
        ("Gluten-Free", "wheat.slash", Color.orange),
        ("Dairy-Free", "cup.and.saucer.fill", Color.blue),
        ("Nut-Free", "allergens", Color.red),
        ("Halal", "checkmark.seal.fill", Color.purple),
        ("Kosher", "checkmark.seal", Color.indigo),
        ("Low Sodium", "salt.shaker", Color.gray)
    ]

    var body: some View {
        List {
            ForEach(restrictions, id: \.0) { restriction, icon, color in
                Button {
                    toggleRestriction(restriction)
                } label: {
                    HStack {
                        Image(systemName: icon)
                            .foregroundStyle(color)
                            .frame(width: 30)

                        Text(restriction)

                        Spacer()

                        if selectedRestrictions.contains(restriction) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.blue)
                        }
                    }
                }
                .foregroundStyle(.primary)
            }
        }
        .navigationTitle("Dietary Restrictions")
        .onAppear {
            if let profile = userProfile {
                selectedRestrictions = Set(profile.dietaryRestrictionsArray)
            }
        }
        .onDisappear {
            saveRestrictions()
        }
    }

    private func toggleRestriction(_ restriction: String) {
        if selectedRestrictions.contains(restriction) {
            selectedRestrictions.remove(restriction)
        } else {
            selectedRestrictions.insert(restriction)
        }
    }

    private func saveRestrictions() {
        if let profile = userProfile {
            profile.dietaryRestrictions = Array(selectedRestrictions)
            try? modelContext.save()
        }
    }
}

// MARK: - AI Model Status Row
struct AIModelStatusRow: View {
    var body: some View {
        HStack {
            Label {
                HStack {
                    Text("Model")
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(ModelManager.shared.currentTier.displayName)
                            .foregroundStyle(tierColor)
                        Text(tierDescription)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            } icon: {
                Image(systemName: tierIcon)
                    .foregroundStyle(tierColor)
            }
        }
    }

    private var tierIcon: String {
        switch ModelManager.shared.currentTier {
        case .appleIntelligence:
            return "apple.logo"  // Apple Intelligence disabled, but keeping for enum completeness
        case .qwen4B:
            return "cpu.fill"
        case .llama3B:
            return "cpu"
        case .llama1B:
            return "cpu"
        }
    }

    private var tierColor: Color {
        switch ModelManager.shared.currentTier {
        case .appleIntelligence:
            return .blue
        case .qwen4B:
            return .purple
        case .llama3B:
            return .orange
        case .llama1B:
            return .gray
        }
    }

    private var tierDescription: String {
        switch ModelManager.shared.currentTier {
        case .appleIntelligence:
            return "On-device AI"
        case .qwen4B:
            return "High quality"
        case .llama3B:
            return "Balanced"
        case .llama1B:
            return "Lightweight"
        }
    }
}

// MARK: - AI Model Preference Toggle
struct AIModelPreferenceToggle: View {
    @State private var useHighQuality = ModelManager.shared.preferHighQualityModel

    // Only show if device can run Qwen 4B (requires 6GB+ RAM)
    private var showToggle: Bool {
        DeviceCapabilityDetector.shared.canRunTier(.qwen4B)
    }

    var body: some View {
        if showToggle {
            Toggle(isOn: $useHighQuality) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("High Quality Mode")
                    Text("Uses Qwen 4B (slower, better results)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: useHighQuality) { _, newValue in
                ModelManager.shared.preferHighQualityModel = newValue
            }
        }
    }
}
