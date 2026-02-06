import SwiftUI
import SwiftData

// MARK: - Plan Builder State
enum PlanBuilderStep: Int, CaseIterable {
    case setup = 0
    case planning = 1
    case review = 2

    var title: String {
        switch self {
        case .setup: return "Setup"
        case .planning: return "Plan Meals"
        case .review: return "Review"
        }
    }
}

// MARK: - Plan Builder Mode
enum PlanBuilderMode {
    case manual      // Step-by-step interactive flow
    case automatic   // Agentic auto-generation
}

// MARK: - Generation Mode
enum GenerationMode: String, CaseIterable {
    case allAI = "All AI"
    case mixed = "Mixed"
    case allCurated = "All Curated"

    var description: String {
        switch self {
        case .allAI: return "Generate all meals with AI"
        case .mixed: return "AI with curated fallbacks"
        case .allCurated: return "Use curated meal library"
        }
    }

    var icon: String {
        switch self {
        case .allAI: return "sparkles"
        case .mixed: return "sparkles.rectangle.stack"
        case .allCurated: return "book.closed.fill"
        }
    }
}

// MARK: - Plan Configuration
struct PlanConfiguration {
    var name: String = "My Meal Plan"
    var goal: GoalType = .maintenance
    var dailyCalories: Int = 2000
    var daysCount: Int = 7
    var restrictions: [String] = []
    var startDate: Date = Date()

    // New: Custom prompt for AI generation
    var customPrompt: String = ""

    // New: Generation mode
    var generationMode: GenerationMode = .mixed

    // Selected meal types (default: all 5)
    var selectedMealTypes: Set<MealType> = Set(MealType.allCases)

    /// Meal types in sorted order for generation
    var mealTypeOrder: [MealType] {
        selectedMealTypes.sorted { $0.sortOrder < $1.sortOrder }
    }

    var dayNames: [String] {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return (0..<daysCount).map { offset in
            let date = Calendar.current.date(byAdding: .day, value: offset, to: startDate) ?? startDate
            return formatter.string(from: date)
        }
    }
}

// MARK: - Planned Day
struct PlannedDay: Identifiable {
    let id = UUID()
    var dayName: String
    var date: Date
    var meals: [PlannedMeal] = []

    var totalCalories: Int {
        meals.reduce(0) { $0 + $1.calories }
    }

    var totalProtein: Int {
        meals.reduce(0) { $0 + $1.protein }
    }

    var isComplete: Bool {
        meals.count >= 4 // breakfast, lunch, dinner, snack
    }
}

// MARK: - Planned Meal
struct PlannedMeal: Identifiable {
    let id = UUID()
    var type: MealType
    var name: String
    var calories: Int
    var protein: Int
    var carbs: Int
    var fat: Int
    var ingredients: [MealIngredient]
    var prepTimeMinutes: Int = 20
    var difficulty: MealDifficulty = .medium
    var cookingInstructions: [String] = []
    var isAccepted: Bool = false

    /// Legacy initializer for string-based ingredients
    init(type: MealType, name: String, calories: Int, protein: Int, carbs: Int, fat: Int, ingredients: [String], prepTimeMinutes: Int = 20, difficulty: MealDifficulty = .medium, isAccepted: Bool = false) {
        self.type = type
        self.name = name
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.ingredients = ingredients.map { MealIngredient.fromLegacyString($0) }
        self.prepTimeMinutes = prepTimeMinutes
        self.difficulty = difficulty
        self.isAccepted = isAccepted
    }

    /// Structured initializer for MealIngredient-based ingredients
    init(type: MealType, name: String, calories: Int, protein: Int, carbs: Int, fat: Int, structuredIngredients: [MealIngredient], prepTimeMinutes: Int = 20, difficulty: MealDifficulty = .medium, isAccepted: Bool = false) {
        self.type = type
        self.name = name
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.ingredients = structuredIngredients
        self.prepTimeMinutes = prepTimeMinutes
        self.difficulty = difficulty
        self.isAccepted = isAccepted
    }
}

// MARK: - Interactive Plan Builder View
struct InteractivePlanBuilderView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query var userProfiles: [UserProfile]

    @State private var currentStep: PlanBuilderStep = .setup
    @State private var config = PlanConfiguration()
    @State private var plannedDays: [PlannedDay] = []
    @State private var currentDayIndex = 0
    @State private var currentMealType: MealType = .breakfast
    @State private var isGenerating = false
    @State private var showError = false
    @State private var errorMessage = ""

    // Agentic generation mode
    @State private var builderMode: PlanBuilderMode = .manual
    @State private var agenticGenerator = AgenticPlanGenerator()

    private var userProfile: UserProfile? { userProfiles.first }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Progress indicator
                progressIndicator

                // Content based on step
                switch currentStep {
                case .setup:
                    PlanSetupStep(
                        config: $config,
                        onAutoGenerate: {
                            builderMode = .automatic
                            initializeDays()
                            withAnimation { currentStep = .planning }
                        },
                        onManualBuild: {
                            builderMode = .manual
                            initializeDays()
                            withAnimation { currentStep = .planning }
                        }
                    )
                case .planning:
                    if builderMode == .automatic {
                        AgenticGenerationView(
                            generator: agenticGenerator,
                            config: config,
                            userProfile: userProfile,
                            onComplete: { days in
                                plannedDays = days
                                withAnimation { currentStep = .review }
                            },
                            onCancel: {
                                withAnimation {
                                    builderMode = .manual
                                    currentStep = .setup
                                }
                            }
                        )
                    } else {
                        DayPlanningStep(
                            config: config,
                            plannedDays: $plannedDays,
                            currentDayIndex: $currentDayIndex,
                            currentMealType: $currentMealType,
                            isGenerating: $isGenerating,
                            onComplete: {
                                withAnimation { currentStep = .review }
                            },
                            onBack: {
                                withAnimation { currentStep = .setup }
                            }
                        )
                    }
                case .review:
                    PlanReviewStep(
                        config: config,
                        plannedDays: plannedDays,
                        onSave: savePlan,
                        onBack: {
                            withAnimation { currentStep = .planning }
                        }
                    )
                }
            }
            .navigationTitle("Create Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .onAppear {
                // Pre-fill from user profile
                if let profile = userProfile {
                    config.dailyCalories = profile.dailyCalorieTarget ?? 2000
                    config.goal = profile.goalType ?? .maintenance
                    config.restrictions = profile.dietaryRestrictionsArray
                }
            }
        }
    }

    // MARK: - Progress Indicator
    private var progressIndicator: some View {
        HStack(spacing: 0) {
            ForEach(PlanBuilderStep.allCases, id: \.rawValue) { step in
                VStack(spacing: 4) {
                    Circle()
                        .fill(step.rawValue <= currentStep.rawValue ? Color.blue : Color.gray.opacity(0.3))
                        .frame(width: 32, height: 32)
                        .overlay {
                            if step.rawValue < currentStep.rawValue {
                                Image(systemName: "checkmark")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.white)
                            } else {
                                Text("\(step.rawValue + 1)")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(step.rawValue <= currentStep.rawValue ? .white : .secondary)
                            }
                        }

                    Text(step.title)
                        .font(.caption2)
                        .foregroundStyle(step.rawValue <= currentStep.rawValue ? .primary : .secondary)
                }

                if step != PlanBuilderStep.allCases.last {
                    Rectangle()
                        .fill(step.rawValue < currentStep.rawValue ? Color.blue : Color.gray.opacity(0.3))
                        .frame(height: 2)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
    }

    // MARK: - Initialize Days
    private func initializeDays() {
        plannedDays = config.dayNames.enumerated().map { index, name in
            let date = Calendar.current.date(byAdding: .day, value: index, to: config.startDate) ?? config.startDate
            return PlannedDay(dayName: name, date: date)
        }
        currentDayIndex = 0
        currentMealType = .breakfast
    }

    // MARK: - Save Plan
    private func savePlan() {
        let plan = DietPlan(
            name: config.name,
            goal: config.goal,
            calories: config.dailyCalories
        )
        modelContext.insert(plan)

        for plannedDay in plannedDays {
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
                    fat: plannedMeal.fat
                )
                meal.ingredients = plannedMeal.ingredients
                meal.day = day
                modelContext.insert(meal)
            }
        }

        try? modelContext.save()

        dismiss()
    }
}

// MARK: - Plan Setup Step
struct PlanSetupStep: View {
    @Binding var config: PlanConfiguration
    let onAutoGenerate: () -> Void
    let onManualBuild: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 50))
                        .foregroundStyle(.blue)

                    Text("Let's Build Your Plan")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Configure your preferences below")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 20)

                VStack(spacing: 16) {
                    // Plan name
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Plan Name")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        TextField("My Meal Plan", text: $config.name)
                            .textFieldStyle(.plain)
                            .padding()
                            .background(Color(uiColor: .tertiarySystemGroupedBackground))
                            .cornerRadius(12)
                    }

                    // Goal picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your Goal")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            ForEach([GoalType.weightLoss, .maintenance, .muscleGain], id: \.self) { goal in
                                GoalButton(
                                    goal: goal,
                                    isSelected: config.goal == goal
                                ) {
                                    config.goal = goal
                                    // Adjust calories based on goal
                                    switch goal {
                                    case .weightLoss:
                                        config.dailyCalories = max(1200, config.dailyCalories - 300)
                                    case .muscleGain:
                                        config.dailyCalories = min(4000, config.dailyCalories + 300)
                                    default:
                                        break
                                    }
                                }
                            }
                        }
                    }

                    // Calories
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Daily Calories")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(config.dailyCalories) kcal")
                                .font(.headline)
                                .foregroundStyle(.blue)
                        }

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
                    .background(Color(uiColor: .tertiarySystemGroupedBackground))
                    .cornerRadius(12)

                    // Days count
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Number of Days")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            ForEach([3, 5, 7], id: \.self) { days in
                                Button {
                                    config.daysCount = days
                                } label: {
                                    Text("\(days) days")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 12)
                                        .background(config.daysCount == days ? Color.blue : Color(uiColor: .tertiarySystemGroupedBackground))
                                        .foregroundStyle(config.daysCount == days ? .white : .primary)
                                        .cornerRadius(10)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)

                // Advanced Options (Custom Prompt & Generation Mode)
                AdvancedOptionsSection(config: $config)

                Spacer(minLength: 20)

                // Generation Mode Selection
                VStack(spacing: 16) {
                    Text("How would you like to build?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    // Auto Generate Button (Recommended)
                    Button(action: onAutoGenerate) {
                        VStack(spacing: 8) {
                            HStack {
                                Image(systemName: "wand.and.stars")
                                    .font(.title3)
                                Text("Auto Generate")
                                    .font(.headline)
                                Spacer()
                                Text("Recommended")
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.white.opacity(0.2))
                                    .cornerRadius(8)
                            }

                            Text("AI creates your complete plan automatically")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.8))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
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

                    // Manual Build Button
                    Button(action: onManualBuild) {
                        HStack {
                            Image(systemName: "hand.tap.fill")
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Build Step by Step")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text("Review each meal individually")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.tertiary)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color(uiColor: .tertiarySystemGroupedBackground))
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

// MARK: - Goal Button
struct GoalButton: View {
    let goal: GoalType
    let isSelected: Bool
    let action: () -> Void

    var icon: String {
        switch goal {
        case .weightLoss: return "arrow.down.circle.fill"
        case .maintenance: return "equal.circle.fill"
        case .muscleGain: return "arrow.up.circle.fill"
        case .keto: return "flame.circle.fill"
        }
    }

    var color: Color {
        switch goal {
        case .weightLoss: return .green
        case .maintenance: return .blue
        case .muscleGain: return .orange
        case .keto: return .purple
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(isSelected ? .white : color)

                Text(goal.rawValue)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(isSelected ? .white : .primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(isSelected ? color : Color(uiColor: .tertiarySystemGroupedBackground))
            .cornerRadius(12)
        }
    }
}

// MARK: - Advanced Options Section
struct AdvancedOptionsSection: View {
    @Binding var config: PlanConfiguration
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 12) {
            // Expand/Collapse Header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "slider.horizontal.3")
                        .font(.subheadline)
                        .foregroundStyle(.blue)

                    Text("Customize Generation")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color(uiColor: .tertiarySystemGroupedBackground))
                .cornerRadius(12)
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 16) {
                    // Custom Prompt Field
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "text.bubble")
                                .foregroundStyle(.purple)
                            Text("Custom Instructions")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        TextField("e.g., Asian-inspired, high protein, quick meals...", text: $config.customPrompt, axis: .vertical)
                            .textFieldStyle(.plain)
                            .lineLimit(2...4)
                            .padding()
                            .background(Color(uiColor: .tertiarySystemGroupedBackground))
                            .cornerRadius(10)

                        Text("Tell the AI what kind of meals you want")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    // Generation Mode Picker
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "gearshape.2")
                                .foregroundStyle(.orange)
                            Text("Generation Mode")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 8) {
                            ForEach(GenerationMode.allCases, id: \.self) { mode in
                                GenerationModeButton(
                                    mode: mode,
                                    isSelected: config.generationMode == mode
                                ) {
                                    config.generationMode = mode
                                }
                            }
                        }

                        Text(config.generationMode.description)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding()
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .cornerRadius(12)
                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - Generation Mode Button
struct GenerationModeButton: View {
    let mode: GenerationMode
    let isSelected: Bool
    let action: () -> Void

    var color: Color {
        switch mode {
        case .allAI: return .purple
        case .mixed: return .blue
        case .allCurated: return .orange
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: mode.icon)
                    .font(.title3)
                    .foregroundStyle(isSelected ? .white : color)

                Text(mode.rawValue)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(isSelected ? .white : .primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(isSelected ? color : Color(uiColor: .tertiarySystemGroupedBackground))
            .cornerRadius(10)
        }
    }
}

#Preview {
    InteractivePlanBuilderView()
}
