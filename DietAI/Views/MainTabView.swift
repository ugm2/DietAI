import SwiftUI
import SwiftData
import HealthKit

// MARK: - Main Tab View (Simplified 2-Tab Structure)
struct MainTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Query var userProfiles: [UserProfile]
    @State private var selectedTab = 0
    @State private var showSettings = false

    private var userProfile: UserProfile? { userProfiles.first }
    private var needsOnboarding: Bool {
        userProfile == nil || !(userProfile?.hasCompletedOnboarding ?? false)
    }

    var body: some View {
        Group {
            if needsOnboarding {
                OnboardingContainerView()
            } else {
                mainContent
            }
        }
    }

    private var mainContent: some View {
        TabView(selection: $selectedTab) {
            // Today - Primary home screen with daily progress
            TodayView()
                .tabItem {
                    Label("Today", systemImage: "sun.max.fill")
                }
                .tag(0)

            // Plan - Integrated plan builder & viewer
            PlanView()
                .tabItem {
                    Label("Plan", systemImage: "list.bullet.clipboard.fill")
                }
                .tag(1)

            // Analytics - Meal, workout, and health analytics
            AnalyticsView()
                .tabItem {
                    Label("Analytics", systemImage: "chart.line.uptrend.xyaxis")
                }
                .tag(2)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }
}

// MARK: - Onboarding Container
struct OnboardingContainerView: View {
    var body: some View {
        OnboardingView(onComplete: {
            // OnboardingView handles profile creation and marking onboarding complete
            // The view will automatically refresh due to @Query observing userProfiles
        })
    }
}

// MARK: - Legacy views kept for compatibility
// These views are still referenced by MeView and other parts of the app

// MARK: - Backup Restore View
struct BackupRestoreView: View {
    @Environment(\.modelContext) private var context
    @State private var backups: [URL] = []
    @State private var isExporting = false
    @State private var exportURL: URL?
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        List {
            Section("Create Backup") {
                Button(action: createBackup) {
                    Label("Create New Backup", systemImage: "square.and.arrow.down")
                }
            }

            Section("Restore") {
                if backups.isEmpty {
                    Text("No backups found")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(backups, id: \.absoluteString) { backup in
                        Button(action: { restoreBackup(backup) }) {
                            VStack(alignment: .leading) {
                                Text(backup.lastPathComponent)
                                    .font(.subheadline)
                                Text(formatDate(from: backup))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Backup & Restore")
        .onAppear {
            backups = CloudSyncService.shared.listBackups()
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private func createBackup() {
        Task {
            do {
                _ = try await CloudSyncService.shared.createBackup(context: context)
                backups = CloudSyncService.shared.listBackups()
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func restoreBackup(_ url: URL) {
        Task {
            do {
                try await CloudSyncService.shared.restoreFromBackup(url: url, context: context)
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func formatDate(from url: URL) -> String {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        if let date = attributes?[.creationDate] as? Date {
            return date.formatted()
        }
        return "Unknown date"
    }
}

// MARK: - Settings View
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query var userProfiles: [UserProfile]
    @Query var plans: [DietPlan]
    @Query var mealLogs: [MealLog]

    @State private var showDeleteConfirmation = false
    @State private var showProfileEditor = false
    @State private var showPlanDefaultsEditor = false
    @State private var showDietEditor = false

    private var userProfile: UserProfile? { userProfiles.first }

    var body: some View {
        NavigationStack {
            List {
                // Profile Section
                Section("Profile") {
                    if let profile = userProfile {
                        NavigationLink {
                            ProfileSettingsView(profile: profile)
                        } label: {
                            HStack {
                                Label("Height", systemImage: "ruler")
                                Spacer()
                                Text(formatHeight(profile.height ?? 170))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        NavigationLink {
                            ProfileSettingsView(profile: profile)
                        } label: {
                            HStack {
                                Label("Weight", systemImage: "scalemass")
                                Spacer()
                                Text("\(Int(profile.weight ?? 70)) kg")
                                    .foregroundStyle(.secondary)
                            }
                        }

                        NavigationLink {
                            ProfileSettingsView(profile: profile)
                        } label: {
                            HStack {
                                Label("Activity Level", systemImage: "figure.walk")
                                Spacer()
                                Text(profile.activityLevel?.rawValue ?? "Not set")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                // Plan Defaults Section
                Section("Plan Defaults") {
                    if let profile = userProfile {
                        NavigationLink {
                            PlanDefaultsSettingsView(profile: profile)
                        } label: {
                            HStack {
                                Label("Default Prep Time", systemImage: "clock")
                                Spacer()
                                Text("\(profile.defaultPrepTimeMinutes) min")
                                    .foregroundStyle(.secondary)
                            }
                        }

                        NavigationLink {
                            PlanDefaultsSettingsView(profile: profile)
                        } label: {
                            HStack {
                                Label("Default Difficulty", systemImage: "gauge.medium")
                                Spacer()
                                Text(profile.defaultDifficulty.rawValue)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        NavigationLink {
                            PlanDefaultsSettingsView(profile: profile)
                        } label: {
                            HStack {
                                Label("Default Budget", systemImage: "dollarsign.circle")
                                Spacer()
                                Text(profile.defaultBudget.displayName)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        NavigationLink {
                            PlanDefaultsSettingsView(profile: profile)
                        } label: {
                            HStack {
                                Label("Batch Cooking", systemImage: "refrigerator")
                                Spacer()
                                Text(profile.prefersBatchCooking ? "On" : "Off")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                // Diet Section
                Section("Diet") {
                    if let profile = userProfile {
                        NavigationLink {
                            DietRestrictionsSettingsView(profile: profile)
                        } label: {
                            HStack {
                                Label("Dietary Restrictions", systemImage: "leaf")
                                Spacer()
                                let count = profile.dietaryRestrictions.count
                                Text(count == 0 ? "None" : "\(count) set")
                                    .foregroundStyle(.secondary)
                            }
                        }

                        NavigationLink {
                            DietRestrictionsSettingsView(profile: profile)
                        } label: {
                            HStack {
                                Label("Avoided Ingredients", systemImage: "xmark.circle")
                                Spacer()
                                let count = profile.dislikedIngredients.count
                                Text(count == 0 ? "None" : "\(count) items")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                // Health Section
                Section("Health") {
                    NavigationLink {
                        HealthKitConnectionView()
                    } label: {
                        Label {
                            HStack {
                                Text("Apple Health Sync")
                                Spacer()
                                if HealthKitService.shared.isAuthorized {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                        } icon: {
                            Image(systemName: "heart.fill")
                                .foregroundStyle(.red)
                        }
                    }
                }

                // Data Section
                Section("Data") {
                    NavigationLink {
                        BackupRestoreView()
                    } label: {
                        Label("Export Data", systemImage: "square.and.arrow.up")
                    }

                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete All Data", systemImage: "trash")
                            .foregroundStyle(.red)
                    }
                }

                // About Section
                Section("About") {
                    HStack {
                        Label("Version", systemImage: "info.circle")
                        Spacer()
                        Text("2.0.0")
                            .foregroundStyle(.secondary)
                    }

                    Link(destination: URL(string: "https://dietai.app/privacy")!) {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Delete All Data?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    deleteAllData()
                }
            } message: {
                Text("This will permanently delete all your meal plans, logs, and preferences. This action cannot be undone.")
            }
        }
    }

    private func formatHeight(_ cm: Double) -> String {
        let inches = cm / 2.54
        let feet = Int(inches / 12)
        let remainingInches = Int(inches.truncatingRemainder(dividingBy: 12))
        return "\(feet)' \(remainingInches)\""
    }

    private func deleteAllData() {
        // Delete all plans
        for plan in plans {
            modelContext.delete(plan)
        }

        // Delete all meal logs
        for log in mealLogs {
            modelContext.delete(log)
        }

        // Reset user profile to defaults
        if let profile = userProfile {
            profile.hasCompletedOnboarding = false
        }

        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Profile Settings View
struct ProfileSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var profile: UserProfile

    @State private var heightFeet: Int = 5
    @State private var heightInches: Int = 10
    @State private var weight: Double = 70
    @State private var selectedActivity: ActivityLevel = .moderatelyActive
    @FocusState private var isWeightFocused: Bool

    var body: some View {
        Form {
            Section("Height") {
                HStack {
                    Picker("Feet", selection: $heightFeet) {
                        ForEach(4...7, id: \.self) { ft in
                            Text("\(ft) ft").tag(ft)
                        }
                    }
                    .pickerStyle(.wheel)

                    Picker("Inches", selection: $heightInches) {
                        ForEach(0...11, id: \.self) { inch in
                            Text("\(inch) in").tag(inch)
                        }
                    }
                    .pickerStyle(.wheel)
                }
                .frame(height: 100)
            }

            Section("Weight") {
                HStack {
                    Text("Weight")
                    Spacer()
                    TextField("Weight", value: $weight, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                        .focused($isWeightFocused)
                    Text("kg")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Activity Level") {
                Picker("Activity Level", selection: $selectedActivity) {
                    ForEach(ActivityLevel.allCases, id: \.self) { level in
                        Text(level.rawValue).tag(level)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
        }
        .formKeyboardDismissible()
        .navigationTitle("Edit Profile")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            let heightCm = profile.height ?? 170
            let totalInches = heightCm / 2.54
            heightFeet = Int(totalInches / 12)
            heightInches = Int(totalInches.truncatingRemainder(dividingBy: 12))
            weight = profile.weight ?? 70
            selectedActivity = profile.activityLevel ?? .moderatelyActive
        }
        .onChange(of: heightFeet) { _, _ in saveChanges() }
        .onChange(of: heightInches) { _, _ in saveChanges() }
        .onChange(of: weight) { _, _ in saveChanges() }
        .onChange(of: selectedActivity) { _, _ in saveChanges() }
    }

    private func saveChanges() {
        profile.height = Double(heightFeet * 12 + heightInches) * 2.54
        profile.weight = weight
        profile.activityLevel = selectedActivity
        try? modelContext.save()
    }
}

// MARK: - Plan Defaults Settings View
struct PlanDefaultsSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var profile: UserProfile

    var body: some View {
        Form {
            Section("Default Prep Time") {
                Picker("Max prep time per meal", selection: Binding(
                    get: { profile.defaultPrepTimeMinutes },
                    set: { profile.defaultPrepTimeMinutes = $0; save() }
                )) {
                    Text("15 min").tag(15)
                    Text("30 min").tag(30)
                    Text("45 min").tag(45)
                    Text("60 min").tag(60)
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            Section("Default Difficulty") {
                Picker("Cooking difficulty", selection: Binding(
                    get: { profile.defaultDifficulty },
                    set: { profile.defaultDifficultyRaw = $0.rawValue; save() }
                )) {
                    ForEach(MealDifficulty.allCases, id: \.self) { difficulty in
                        Text(difficulty.rawValue).tag(difficulty)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            Section("Default Budget") {
                Picker("Budget level", selection: Binding(
                    get: { profile.defaultBudget },
                    set: { profile.defaultBudgetRaw = $0.rawValue; save() }
                )) {
                    ForEach(BudgetLevel.allCases, id: \.self) { level in
                        HStack {
                            Text(level.rawValue)
                            Text("- \(level.displayName)")
                                .foregroundStyle(.secondary)
                        }
                        .tag(level)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            Section("Batch Cooking") {
                Toggle("Prefer batch cooking friendly meals", isOn: Binding(
                    get: { profile.prefersBatchCooking },
                    set: { profile.prefersBatchCooking = $0; save() }
                ))
            }
        }
        .navigationTitle("Plan Defaults")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func save() {
        try? modelContext.save()
    }
}

// MARK: - Diet Restrictions Settings View
struct DietRestrictionsSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var profile: UserProfile

    @State private var newIngredient = ""
    @FocusState private var isIngredientFocused: Bool

    private let restrictionOptions = [
        "Vegetarian", "Vegan", "Gluten-free", "Dairy-free",
        "Nut-free", "Low-carb", "Keto", "Halal", "Kosher"
    ]

    var body: some View {
        Form {
            Section("Dietary Restrictions") {
                ForEach(restrictionOptions, id: \.self) { restriction in
                    let isSelected = profile.dietaryRestrictions.contains(restriction)

                    Button {
                        toggleRestriction(restriction)
                    } label: {
                        HStack {
                            Text(restriction)
                                .foregroundStyle(.primary)
                            Spacer()
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }
            }

            Section("Avoided Ingredients") {
                ForEach(profile.dislikedIngredients, id: \.self) { ingredient in
                    HStack {
                        Text(ingredient)
                        Spacer()
                    }
                }
                .onDelete(perform: deleteIngredient)

                HStack {
                    TextField("Add ingredient", text: $newIngredient)
                        .submitLabel(.done)
                        .focused($isIngredientFocused)
                        .onSubmit {
                            addIngredient()
                        }

                    if !newIngredient.isEmpty {
                        Button("Add") {
                            addIngredient()
                        }
                    }
                }
            }
        }
        .formKeyboardDismissible()
        .navigationTitle("Diet Preferences")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func toggleRestriction(_ restriction: String) {
        if profile.dietaryRestrictions.contains(restriction) {
            profile.dietaryRestrictions.removeAll { $0 == restriction }
        } else {
            profile.dietaryRestrictions.append(restriction)
        }
        try? modelContext.save()
    }

    private func addIngredient() {
        guard !newIngredient.isEmpty else { return }
        profile.dislikedIngredients.append(newIngredient.trimmingCharacters(in: .whitespaces))
        newIngredient = ""
        try? modelContext.save()
    }

    private func deleteIngredient(at offsets: IndexSet) {
        profile.dislikedIngredients.remove(atOffsets: offsets)
        try? modelContext.save()
    }
}

// HealthKitConnectionView is defined in HealthKitService.swift

// MARK: - Raw Output View (Debug)
struct RawOutputView: View {
    @Environment(\.dismiss) private var dismiss
    let output: String

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Info header
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(.blue)
                        Text("This is the raw AI output for debugging")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)

                    // Raw output
                    if output.isEmpty {
                        Text("No output generated yet")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 40)
                    } else {
                        Text(output)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(uiColor: .tertiarySystemGroupedBackground))
                            .cornerRadius(8)
                    }

                    // Copy button
                    if !output.isEmpty {
                        Button(action: {
                            UIPasteboard.general.string = output
                        }) {
                            Label("Copy to Clipboard", systemImage: "doc.on.doc")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
            }
            .navigationTitle("Raw AI Output")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
