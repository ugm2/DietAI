import SwiftUI
import SwiftData

// MARK: - Plan Wizard (5-Step Flow)
struct PlanWizardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query var userProfiles: [UserProfile]

    @State private var currentStep = 0
    @State private var wizardConfig = WizardConfiguration()
    @State private var isGenerating = false
    @State private var generationProgress: Double = 0
    @State private var generationStatus = ""
    @State private var generatedPlan: DietPlan?
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isDownloadingModel = false

    @State private var agenticGenerator = AgenticPlanGenerator()
    private let modelManager = ModelManager.shared

    private var userProfile: UserProfile? { userProfiles.first }
    private let totalSteps = 6

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Progress indicator
                WizardProgressBar(currentStep: currentStep, totalSteps: totalSteps)
                    .padding(.horizontal)
                    .padding(.top)

                // Content
                TabView(selection: $currentStep) {
                    GoalSelectionStep(
                        selectedGoal: $wizardConfig.goal,
                        onNext: nextStep
                    )
                    .tag(0)

                    PreferencesStep(
                        config: $wizardConfig,
                        onNext: nextStep,
                        onBack: previousStep
                    )
                    .tag(1)

                    MealTypeSelectionStep(
                        selectedMealTypes: $wizardConfig.selectedMealTypes,
                        onNext: nextStep,
                        onBack: previousStep
                    )
                    .tag(2)

                    RestrictionsStep(
                        restrictions: $wizardConfig.restrictions,
                        avoidedIngredients: $wizardConfig.avoidedIngredients,
                        onNext: nextStep,
                        onBack: previousStep
                    )
                    .tag(3)

                    NotesStep(
                        notes: $wizardConfig.userNotes,
                        onNext: nextStep,
                        onBack: previousStep
                    )
                    .tag(4)

                    SummaryAndGenerateStep(
                        config: wizardConfig,
                        isGenerating: $isGenerating,
                        progress: $generationProgress,
                        status: $generationStatus,
                        onGenerate: generatePlan,
                        onBack: previousStep
                    )
                    .tag(5)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: currentStep)
            }
            .navigationTitle(stepTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isGenerating)
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .onAppear {
                loadDefaultsFromProfile()
            }
        }
        .interactiveDismissDisabled(isGenerating || isDownloadingModel)
        .fullScreenCover(isPresented: $isDownloadingModel) {
            ModelDownloadView(
                modelManager: modelManager,
                onComplete: {
                    isDownloadingModel = false
                    // Start generation after model is ready
                    startGeneration()
                },
                onCancel: {
                    isDownloadingModel = false
                }
            )
            .interactiveDismissDisabled()
        }
    }

    private var stepTitle: String {
        switch currentStep {
        case 0: return "Step 1 of 6"
        case 1: return "Step 2 of 6"
        case 2: return "Step 3 of 6"
        case 3: return "Step 4 of 6"
        case 4: return "Step 5 of 6"
        case 5: return "Step 6 of 6"
        default: return "Create Plan"
        }
    }

    private func nextStep() {
        withAnimation {
            currentStep = min(currentStep + 1, totalSteps - 1)
        }
    }

    private func previousStep() {
        withAnimation {
            currentStep = max(currentStep - 1, 0)
        }
    }

    private func loadDefaultsFromProfile() {
        guard let profile = userProfile else { return }
        wizardConfig.dailyCalories = profile.dailyCalorieTarget ?? 2000
        wizardConfig.maxPrepTimeMinutes = profile.defaultPrepTimeMinutes
        wizardConfig.difficulty = profile.defaultDifficulty
        wizardConfig.budgetLevel = profile.defaultBudget
        wizardConfig.batchCookingEnabled = profile.prefersBatchCooking
        wizardConfig.selectedMealTypes = profile.selectedMealTypes
        wizardConfig.restrictions = Set(profile.dietaryRestrictionsArray)
        wizardConfig.avoidedIngredients = Set(profile.dislikedIngredients)
    }

    private func generatePlan() {
        // First, ensure model is loaded
        if !modelManager.isModelLoaded {
            // Show download view - it will call startGeneration() when done
            isDownloadingModel = true
            return
        }

        // Model already loaded, proceed directly
        startGeneration()
    }

    private func startGeneration() {
        Task {
            await MainActor.run {
                isGenerating = true
                generationProgress = 0
                generationStatus = "Starting plan generation..."
            }

            do {
                // Build configuration for the agentic generator
                let planConfig = PlanConfiguration(
                    name: "Week Plan",
                    goal: wizardConfig.goal,
                    dailyCalories: wizardConfig.dailyCalories,
                    daysCount: 7,
                    restrictions: Array(wizardConfig.restrictions),
                    customPrompt: buildCustomPrompt(),
                    selectedMealTypes: wizardConfig.selectedMealTypes
                )

                // Start a progress monitoring task
                let progressTask = Task {
                    while !Task.isCancelled && agenticGenerator.isGenerating {
                        await MainActor.run {
                            generationProgress = agenticGenerator.progress
                            generationStatus = agenticGenerator.phase.displayText
                        }
                        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s
                    }
                }

                // Generate the plan
                let generatedDays = try await agenticGenerator.generatePlan(
                    config: planConfig,
                    userProfile: userProfile
                )

                progressTask.cancel()

                // Save the plan
                await MainActor.run {
                    savePlan(days: generatedDays)
                    isGenerating = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isGenerating = false
                }
            }
        }
    }

    private func buildCustomPrompt() -> String {
        var prompts: [String] = []

        // Prep time
        prompts.append("Maximum prep time per meal: \(wizardConfig.maxPrepTimeMinutes) minutes")

        // Difficulty
        prompts.append("Cooking difficulty: \(wizardConfig.difficulty.rawValue)")

        // Budget
        switch wizardConfig.budgetLevel {
        case .low:
            prompts.append("Budget: budget-friendly, affordable ingredients")
        case .moderate:
            prompts.append("Budget: moderate, standard grocery items")
        case .high:
            prompts.append("Budget: no limit, premium ingredients allowed")
        }

        // Batch cooking
        if wizardConfig.batchCookingEnabled {
            prompts.append("Prefer batch cooking friendly meals that can be prepped ahead")
        }

        // Meal types
        let mealTypeNames = wizardConfig.selectedMealTypes
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { $0.rawValue }
        prompts.append("Meal types to include: \(mealTypeNames.joined(separator: ", "))")

        // Avoided ingredients
        if !wizardConfig.avoidedIngredients.isEmpty {
            prompts.append("Avoid these ingredients: \(wizardConfig.avoidedIngredients.joined(separator: ", "))")
        }

        // User notes
        if !wizardConfig.userNotes.isEmpty {
            prompts.append("Additional notes: \(wizardConfig.userNotes)")
        }

        return prompts.joined(separator: ". ")
    }

    private func savePlan(days: [PlannedDay]) {
        #if DEBUG
        print("💾 savePlan called with \(days.count) days")
        for (i, day) in days.enumerated() {
            print("   Day \(i + 1): \(day.dayName) - \(day.meals.count) meals")
        }
        #endif

        let plan = DietPlan(
            name: "Week Plan",
            goal: wizardConfig.goal,
            calories: wizardConfig.dailyCalories,
            maxPrepTimeMinutes: wizardConfig.maxPrepTimeMinutes,
            difficultyPreference: wizardConfig.difficulty,
            budgetLevel: wizardConfig.budgetLevel,
            batchCookingEnabled: wizardConfig.batchCookingEnabled,
            userNotes: wizardConfig.userNotes.isEmpty ? nil : wizardConfig.userNotes,
            selectedMealTypes: wizardConfig.selectedMealTypes
        )
        modelContext.insert(plan)

        for plannedDay in days {
            let day = DailyPlan(date: plannedDay.date, dayName: plannedDay.dayName)
            day.plan = plan
            modelContext.insert(day)

            for plannedMeal in plannedDay.meals {
                let meal = Meal(
                    type: plannedMeal.type,
                    name: plannedMeal.name,
                    calories: plannedMeal.calories,
                    protein: plannedMeal.protein,
                    carbs: plannedMeal.carbs,
                    fat: plannedMeal.fat,
                    prepTimeMinutes: wizardConfig.maxPrepTimeMinutes,
                    difficulty: wizardConfig.difficulty
                )
                meal.ingredients = plannedMeal.ingredients
                meal.day = day
                modelContext.insert(meal)
            }
        }

        // Update user defaults from this plan
        if let profile = userProfile {
            profile.defaultPrepTimeMinutes = wizardConfig.maxPrepTimeMinutes
            profile.defaultDifficulty = wizardConfig.difficulty
            profile.defaultBudget = wizardConfig.budgetLevel
            profile.prefersBatchCooking = wizardConfig.batchCookingEnabled
            profile.selectedMealTypes = wizardConfig.selectedMealTypes
        }

        try? modelContext.save()
    }
}

// MARK: - Wizard Configuration
struct WizardConfiguration {
    var goal: GoalType = .maintenance
    var dailyCalories: Int = 2000
    var maxPrepTimeMinutes: Int = 30
    var difficulty: MealDifficulty = .easy
    var budgetLevel: BudgetLevel = .moderate
    var batchCookingEnabled: Bool = false
    var selectedMealTypes: Set<MealType> = Set(MealType.allCases)
    var restrictions: Set<String> = []
    var avoidedIngredients: Set<String> = []
    var userNotes: String = ""
}

// MARK: - Wizard Progress Bar
struct WizardProgressBar: View {
    let currentStep: Int
    let totalSteps: Int

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.gray.opacity(0.2))

                Capsule()
                    .fill(Color.blue)
                    .frame(width: geo.size.width * Double(currentStep + 1) / Double(totalSteps))
                    .animation(.spring(response: 0.4), value: currentStep)
            }
        }
        .frame(height: 6)
    }
}

// MARK: - Step 1: Goal Selection
struct GoalSelectionStep: View {
    @Binding var selectedGoal: GoalType
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Text("What's your goal?")
                    .font(.title)
                    .fontWeight(.bold)

                Text("This helps us customize your meal plans")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 40)

            // Goal options
            VStack(spacing: 12) {
                WizardGoalCard(
                    goal: .weightLoss,
                    icon: "arrow.down.circle.fill",
                    color: .green,
                    description: "Create a calorie deficit",
                    isSelected: selectedGoal == .weightLoss
                ) {
                    selectedGoal = .weightLoss
                }

                WizardGoalCard(
                    goal: .muscleGain,
                    icon: "figure.strengthtraining.traditional",
                    color: .blue,
                    description: "High protein, calorie surplus",
                    isSelected: selectedGoal == .muscleGain
                ) {
                    selectedGoal = .muscleGain
                }

                WizardGoalCard(
                    goal: .maintenance,
                    icon: "equal.circle.fill",
                    color: .orange,
                    description: "Balanced nutrition",
                    isSelected: selectedGoal == .maintenance
                ) {
                    selectedGoal = .maintenance
                }
            }
            .padding(.horizontal)

            Spacer()

            // Navigation
            Button(action: onNext) {
                HStack {
                    Text("Next")
                    Image(systemName: "chevron.right")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundStyle(.white)
                .cornerRadius(14)
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
    }
}

struct WizardGoalCard: View {
    let goal: GoalType
    let icon: String
    let color: Color
    let description: String
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                    .frame(width: 50, height: 50)
                    .background(color.opacity(0.15))
                    .cornerRadius(12)

                VStack(alignment: .leading, spacing: 2) {
                    Text(goal.rawValue)
                        .font(.headline)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? .blue : .secondary)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Step 2: Preferences
struct PreferencesStep: View {
    @Binding var config: WizardConfiguration
    let onNext: () -> Void
    let onBack: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Calories
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Daily calories")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(config.dailyCalories)")
                            .font(.headline)
                            .foregroundStyle(.blue)
                    }

                    Text("(Recommended based on your profile)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    Slider(
                        value: Binding(
                            get: { Double(config.dailyCalories) },
                            set: { config.dailyCalories = Int($0) }
                        ),
                        in: 1200...4000,
                        step: 100
                    )
                    .tint(.blue)
                }
                .padding()
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .cornerRadius(16)

                // Prep time
                VStack(alignment: .leading, spacing: 12) {
                    Text("Max prep time per meal")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        ForEach([15, 30, 60], id: \.self) { time in
                            PrepTimeButton(
                                minutes: time,
                                isSelected: config.maxPrepTimeMinutes == time
                            ) {
                                config.maxPrepTimeMinutes = time
                            }
                        }

                        PrepTimeButton(
                            minutes: 0,
                            label: "Any",
                            isSelected: config.maxPrepTimeMinutes == 0
                        ) {
                            config.maxPrepTimeMinutes = 0
                        }
                    }
                }
                .padding()
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .cornerRadius(16)

                // Difficulty
                VStack(alignment: .leading, spacing: 12) {
                    Text("Cooking difficulty")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        ForEach(MealDifficulty.allCases, id: \.self) { diff in
                            DifficultyButton(
                                difficulty: diff,
                                isSelected: config.difficulty == diff
                            ) {
                                config.difficulty = diff
                            }
                        }
                    }
                }
                .padding()
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .cornerRadius(16)

                // Budget
                VStack(alignment: .leading, spacing: 12) {
                    Text("Budget")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        ForEach(BudgetLevel.allCases, id: \.self) { budget in
                            BudgetButton(
                                budget: budget,
                                isSelected: config.budgetLevel == budget
                            ) {
                                config.budgetLevel = budget
                            }
                        }
                    }
                }
                .padding()
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .cornerRadius(16)

                // Batch cooking toggle
                Toggle(isOn: $config.batchCookingEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Batch cooking friendly")
                            .font(.subheadline)
                        Text("Meals that can be prepped ahead")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .cornerRadius(16)

                Spacer(minLength: 100)
            }
            .padding(.horizontal)
            .padding(.top, 20)
        }
        .safeAreaInset(edge: .bottom) {
            // Navigation
            HStack(spacing: 16) {
                Button(action: onBack) {
                    HStack {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .foregroundStyle(.primary)
                    .cornerRadius(14)
                }

                Button(action: onNext) {
                    HStack {
                        Text("Next")
                        Image(systemName: "chevron.right")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .cornerRadius(14)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 16)
            .background(.ultraThinMaterial)
        }
    }
}

struct PrepTimeButton: View {
    let minutes: Int
    var label: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label ?? "\(minutes) min")
                .font(.subheadline)
                .fontWeight(.medium)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(isSelected ? Color.blue : Color(uiColor: .tertiarySystemGroupedBackground))
                .foregroundStyle(isSelected ? .white : .primary)
                .cornerRadius(10)
        }
    }
}

struct DifficultyButton: View {
    let difficulty: MealDifficulty
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(difficulty.rawValue)
                .font(.subheadline)
                .fontWeight(.medium)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(isSelected ? Color.blue : Color(uiColor: .tertiarySystemGroupedBackground))
                .foregroundStyle(isSelected ? .white : .primary)
                .cornerRadius(10)
        }
    }
}

struct BudgetButton: View {
    let budget: BudgetLevel
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(budget.rawValue)
                    .font(.headline)
                Text(budget.displayName)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(isSelected ? Color.blue : Color(uiColor: .tertiarySystemGroupedBackground))
            .foregroundStyle(isSelected ? .white : .primary)
            .cornerRadius(10)
        }
    }
}

// MARK: - Step 3: Meal Type Selection
struct MealTypeSelectionStep: View {
    @Binding var selectedMealTypes: Set<MealType>
    let onNext: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Text("Which meals to include?")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Select the meal types for your plan")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 20)

            // Meal type grid
            VStack(spacing: 12) {
                ForEach(MealType.allCases, id: \.self) { mealType in
                    MealTypeToggleCard(
                        mealType: mealType,
                        isSelected: selectedMealTypes.contains(mealType)
                    ) {
                        if selectedMealTypes.contains(mealType) {
                            // Prevent deselecting all
                            if selectedMealTypes.count > 1 {
                                selectedMealTypes.remove(mealType)
                            }
                        } else {
                            selectedMealTypes.insert(mealType)
                        }
                    }
                }
            }
            .padding(.horizontal)

            // Selection summary
            HStack {
                Image(systemName: "info.circle")
                    .foregroundStyle(.blue)
                Text("\(selectedMealTypes.count) meal type\(selectedMealTypes.count == 1 ? "" : "s") selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal)

            Spacer()

            // Navigation
            HStack(spacing: 16) {
                Button(action: onBack) {
                    HStack {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .foregroundStyle(.primary)
                    .cornerRadius(14)
                }

                Button(action: onNext) {
                    HStack {
                        Text("Next")
                        Image(systemName: "chevron.right")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .cornerRadius(14)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
    }
}

struct MealTypeToggleCard: View {
    let mealType: MealType
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 16) {
                Image(systemName: mealType.icon)
                    .font(.title2)
                    .foregroundStyle(mealType.color)
                    .frame(width: 50, height: 50)
                    .background(mealType.color.opacity(0.15))
                    .cornerRadius(12)

                VStack(alignment: .leading, spacing: 2) {
                    Text(mealType.rawValue)
                        .font(.headline)
                    Text(mealTypeDescription(mealType))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? .blue : .secondary)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func mealTypeDescription(_ type: MealType) -> String {
        switch type {
        case .breakfast: return "Start your day right"
        case .brunch: return "Late morning meal"
        case .lunch: return "Midday energy boost"
        case .snack: return "Between-meal bites"
        case .dinner: return "End-of-day nourishment"
        }
    }
}

// MARK: - Step 4: Restrictions
struct RestrictionsStep: View {
    @Binding var restrictions: Set<String>
    @Binding var avoidedIngredients: Set<String>
    let onNext: () -> Void
    let onBack: () -> Void

    @State private var newIngredient = ""
    @FocusState private var isTextFieldFocused: Bool

    let commonRestrictions = [
        ("Vegetarian", "leaf.fill", Color.green),
        ("Vegan", "leaf.circle.fill", Color.green),
        ("Gluten-free", "xmark.circle.fill", Color.orange),
        ("Dairy-free", "drop.fill", Color.blue),
        ("Nut-free", "exclamationmark.triangle.fill", Color.red),
        ("Low-carb / Keto", "flame.fill", Color.purple),
        ("Halal", "checkmark.seal.fill", Color.indigo),
        ("Kosher", "star.fill", Color.purple)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Text("Any dietary restrictions?")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Select all that apply")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 20)

                // Restrictions grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(commonRestrictions, id: \.0) { restriction, icon, color in
                        RestrictionToggleChip(
                            name: restriction,
                            icon: icon,
                            color: color,
                            isSelected: restrictions.contains(restriction)
                        ) {
                            if restrictions.contains(restriction) {
                                restrictions.remove(restriction)
                            } else {
                                restrictions.insert(restriction)
                            }
                        }
                    }
                }

                // Avoided ingredients
                VStack(alignment: .leading, spacing: 12) {
                    Text("Ingredients to avoid")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    // Input field
                    HStack {
                        TextField("e.g., mushrooms", text: $newIngredient)
                            .textFieldStyle(.plain)
                            .focused($isTextFieldFocused)
                            .submitLabel(.done)
                            .onSubmit {
                                addIngredient()
                            }

                        Button(action: addIngredient) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(.blue)
                        }
                        .disabled(newIngredient.isEmpty)
                    }
                    .padding()
                    .background(Color(uiColor: .tertiarySystemGroupedBackground))
                    .cornerRadius(12)

                    // Tags
                    if !avoidedIngredients.isEmpty {
                        FlowLayoutView(spacing: 8) {
                            ForEach(Array(avoidedIngredients), id: \.self) { ingredient in
                                HStack(spacing: 4) {
                                    Text(ingredient)
                                        .font(.caption)
                                    Button {
                                        avoidedIngredients.remove(ingredient)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.caption)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(16)
                            }
                        }
                    }
                }
                .padding()
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .cornerRadius(16)

                Spacer(minLength: 100)
            }
            .padding(.horizontal)
        }
        .keyboardDismissible()
        .onTapGesture {
            isTextFieldFocused = false
        }
        .safeAreaInset(edge: .bottom) {
            // Navigation
            HStack(spacing: 16) {
                Button(action: onBack) {
                    HStack {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .foregroundStyle(.primary)
                    .cornerRadius(14)
                }

                Button(action: onNext) {
                    HStack {
                        Text(restrictions.isEmpty && avoidedIngredients.isEmpty ? "Skip" : "Next")
                        Image(systemName: "chevron.right")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .cornerRadius(14)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 16)
            .background(.ultraThinMaterial)
        }
    }

    private func addIngredient() {
        let trimmed = newIngredient.trimmingCharacters(in: .whitespaces).lowercased()
        if !trimmed.isEmpty {
            avoidedIngredients.insert(trimmed)
            newIngredient = ""
        }
    }
}

struct RestrictionToggleChip: View {
    let name: String
    let icon: String
    let color: Color
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(isSelected ? .white : color)
                Text(name)
                    .font(.subheadline)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(isSelected ? color : Color(uiColor: .secondarySystemGroupedBackground))
            .foregroundStyle(isSelected ? .white : .primary)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

// Simple flow layout for tags
struct FlowLayoutView<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .fixedSize(horizontal: true, vertical: false)
    }
}

// MARK: - Step 4: Notes
struct NotesStep: View {
    @Binding var notes: String
    let onNext: () -> Void
    let onBack: () -> Void
    @FocusState private var isEditorFocused: Bool

    let examples = [
        "I usually eat lunch at my desk",
        "I have a family of 4",
        "I prefer cold lunches",
        "I like to cook once on Sundays"
    ]

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Text("Anything else we should know?")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Help the AI understand your lifestyle and preferences better")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 20)

            // Text editor
            VStack(alignment: .leading, spacing: 8) {
                TextEditor(text: $notes)
                    .frame(minHeight: 150)
                    .padding(8)
                    .background(Color(uiColor: .tertiarySystemGroupedBackground))
                    .cornerRadius(12)
                    .scrollContentBackground(.hidden)
                    .focused($isEditorFocused)
            }
            .padding(.horizontal)

            // Examples
            VStack(alignment: .leading, spacing: 8) {
                Text("Examples:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(examples, id: \.self) { example in
                        HStack(spacing: 8) {
                            Image(systemName: "lightbulb.fill")
                                .font(.caption)
                                .foregroundStyle(.yellow)
                            Text(example)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.horizontal)

            Spacer()

            // Navigation
            HStack(spacing: 16) {
                Button(action: onBack) {
                    HStack {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .foregroundStyle(.primary)
                    .cornerRadius(14)
                }

                Button(action: onNext) {
                    HStack {
                        Text(notes.isEmpty ? "Skip" : "Next")
                        Image(systemName: "chevron.right")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .cornerRadius(14)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .keyboardDismissToolbar()
        .onTapGesture {
            isEditorFocused = false
        }
    }
}

// MARK: - Step 5: Summary & Generate
struct SummaryAndGenerateStep: View {
    let config: WizardConfiguration
    @Binding var isGenerating: Bool
    @Binding var progress: Double
    @Binding var status: String
    let onGenerate: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            if isGenerating {
                // Generation progress
                VStack(spacing: 24) {
                    Spacer()

                    // Animation
                    ZStack {
                        Circle()
                            .stroke(Color.gray.opacity(0.2), lineWidth: 8)
                            .frame(width: 120, height: 120)

                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(Color.blue, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .frame(width: 120, height: 120)
                            .rotationEffect(.degrees(-90))
                            .animation(.easeInOut, value: progress)

                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 40))
                            .foregroundStyle(.blue)
                    }

                    VStack(spacing: 8) {
                        Text("Creating your personalized meal plan...")
                            .font(.headline)

                        Text(status)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    // Progress bar
                    VStack(spacing: 4) {
                        ProgressView(value: progress)
                            .tint(.blue)

                        Text("Day \(Int(progress * 7) + 1) of 7")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 40)

                    Spacer()
                }
            } else {
                // Summary
                ScrollView {
                    VStack(spacing: 20) {
                        // Header
                        VStack(spacing: 8) {
                            Text("Ready to create your plan!")
                                .font(.title2)
                                .fontWeight(.bold)

                            Text("Review your preferences below")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 20)

                        // Summary card
                        VStack(spacing: 16) {
                            SummaryRow(label: "Goal", value: config.goal.rawValue, icon: "flag.fill", color: .blue)
                            SummaryRow(label: "Calories", value: "\(config.dailyCalories)/day", icon: "flame.fill", color: .orange)
                            SummaryRow(label: "Max prep", value: config.maxPrepTimeMinutes == 0 ? "Any" : "\(config.maxPrepTimeMinutes) min", icon: "clock.fill", color: .green)
                            SummaryRow(label: "Difficulty", value: config.difficulty.rawValue, icon: "gauge.medium", color: .purple)
                            SummaryRow(label: "Budget", value: config.budgetLevel.displayName, icon: "dollarsign.circle.fill", color: .green)

                            if config.batchCookingEnabled {
                                SummaryRow(label: "Batch cook", value: "Yes", icon: "tray.full.fill", color: .indigo)
                            }

                            if !config.restrictions.isEmpty {
                                SummaryRow(
                                    label: "Restrictions",
                                    value: config.restrictions.joined(separator: ", "),
                                    icon: "checkmark.seal.fill",
                                    color: .red
                                )
                            }

                            if !config.userNotes.isEmpty {
                                SummaryRow(
                                    label: "Notes",
                                    value: String(config.userNotes.prefix(50)) + (config.userNotes.count > 50 ? "..." : ""),
                                    icon: "text.quote",
                                    color: .gray
                                )
                            }
                        }
                        .padding()
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .cornerRadius(16)
                        .padding(.horizontal)

                        Spacer(minLength: 100)
                    }
                }

                // Navigation (only when not generating)
                VStack(spacing: 12) {
                    Button(action: onGenerate) {
                        HStack {
                            Image(systemName: "wand.and.stars")
                            Text("Generate Plan")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(
                                colors: [.purple, .blue],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundStyle(.white)
                        .cornerRadius(14)
                    }

                    Button(action: onBack) {
                        HStack {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .foregroundStyle(.primary)
                        .cornerRadius(14)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
        }
    }
}

struct SummaryRow: View {
    let label: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 24)

            Text(label)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .fontWeight(.medium)
                .multilineTextAlignment(.trailing)
        }
    }
}

#Preview {
    PlanWizardView()
}
