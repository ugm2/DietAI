import SwiftUI

// MARK: - Day Planning Step
struct DayPlanningStep: View {
    let config: PlanConfiguration
    @Binding var plannedDays: [PlannedDay]
    @Binding var currentDayIndex: Int
    @Binding var currentMealType: MealType
    @Binding var isGenerating: Bool

    let onComplete: () -> Void
    let onBack: () -> Void

    @State private var currentSuggestion: PlannedMeal?
    @State private var showMealOptions = false
    @State private var modelManager = ModelManager.shared
    @State private var isLoadingModel = false
    @State private var useAI = true

    private var currentDay: PlannedDay? {
        guard currentDayIndex < plannedDays.count else { return nil }
        return plannedDays[currentDayIndex]
    }

    private var mealTypes: [MealType] {
        [.breakfast, .lunch, .snack, .dinner]
    }

    private var progress: Double {
        let totalMeals = plannedDays.count * 4
        let completedMeals = plannedDays.reduce(0) { $0 + $1.meals.count }
        return totalMeals > 0 ? Double(completedMeals) / Double(totalMeals) : 0
    }

    private var isCurrentMealAccepted: Bool {
        currentDay?.meals.contains(where: { $0.type == currentMealType }) ?? false
    }

    var body: some View {
        VStack(spacing: 0) {
            // Day selector
            daySelectorBar

            ScrollView {
                VStack(spacing: 20) {
                    // AI Status Banner
                    aiStatusBanner

                    // Progress summary
                    progressCard

                    // Current day meals overview
                    if let day = currentDay {
                        currentDayOverview(day)
                    }

                    // Meal suggestion area
                    mealSuggestionArea

                    Spacer(minLength: 100)
                }
                .padding()
            }

            // Bottom actions
            bottomActions
        }
    }

    // MARK: - Day Selector Bar
    private var daySelectorBar: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(plannedDays.enumerated()), id: \.element.id) { index, day in
                        DaySelectorButton(
                            dayName: day.dayName,
                            isSelected: index == currentDayIndex,
                            isComplete: day.isComplete
                        ) {
                            withAnimation { currentDayIndex = index }
                            currentMealType = nextUnplannedMealType(for: day)
                        }
                        .id(index)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .onChange(of: currentDayIndex) { _, newIndex in
                withAnimation {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
    }

    // MARK: - AI Status Banner
    @ViewBuilder
    private var aiStatusBanner: some View {
        if isLoadingModel {
            HStack(spacing: 12) {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Loading AI model...")
                    .font(.subheadline)
                Spacer()
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(12)
        } else if !modelManager.isModelLoaded {
            HStack(spacing: 12) {
                Image(systemName: "cpu")
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text("AI Model Not Loaded")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("Using curated meal suggestions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Load AI") {
                    loadModel()
                }
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.blue)
                .foregroundStyle(.white)
                .cornerRadius(8)
            }
            .padding()
            .background(Color.orange.opacity(0.1))
            .cornerRadius(12)
        } else {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("AI Ready")
                    .font(.caption)
                    .fontWeight(.medium)
                Text("• Generating personalized meals")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(12)
            .background(Color.green.opacity(0.1))
            .cornerRadius(12)
        }
    }

    private func loadModel() {
        isLoadingModel = true
        Task {
            await modelManager.loadModel()
            isLoadingModel = false
        }
    }

    // MARK: - Progress Card
    private var progressCard: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Building Your Plan")
                        .font(.headline)

                    Text("\(Int(progress * 100))% complete")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 6)

                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Color.green, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 50, height: 50)
            }

            // Nutrition summary
            if let day = currentDay, !day.meals.isEmpty {
                HStack(spacing: 16) {
                    NutritionPill(label: "Calories", value: "\(day.totalCalories)", target: config.dailyCalories, color: .orange)
                    NutritionPill(label: "Protein", value: "\(day.totalProtein)g", target: nil, color: .red)
                }
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(16)
    }

    // MARK: - Current Day Overview
    private func currentDayOverview(_ day: PlannedDay) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(day.dayName)
                .font(.headline)

            HStack(spacing: 8) {
                ForEach(mealTypes, id: \.self) { type in
                    MealTypeChip(
                        type: type,
                        isPlanned: day.meals.contains(where: { $0.type == type }),
                        isSelected: type == currentMealType
                    ) {
                        withAnimation { currentMealType = type }
                        if !day.meals.contains(where: { $0.type == type }) {
                            generateMealSuggestion()
                        }
                    }
                }
            }

            // Show accepted meals
            ForEach(day.meals) { meal in
                AcceptedMealRow(meal: meal) {
                    // Remove meal
                    if let idx = plannedDays[currentDayIndex].meals.firstIndex(where: { $0.id == meal.id }) {
                        plannedDays[currentDayIndex].meals.remove(at: idx)
                    }
                }
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(16)
    }

    // MARK: - Meal Suggestion Area
    private var mealSuggestionArea: some View {
        VStack(spacing: 16) {
            if isCurrentMealAccepted {
                // Meal already accepted for this type
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(.green)

                    Text("\(currentMealType.rawValue) is set!")
                        .font(.headline)

                    Text("Select another meal type or move to the next day")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(40)
            } else if isGenerating {
                // Loading state
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)

                    Text("Creating \(currentMealType.rawValue.lowercased()) suggestion...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(40)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .cornerRadius(16)
            } else if let suggestion = currentSuggestion {
                // Show suggestion
                MealSuggestionCard(
                    meal: suggestion,
                    targetCalories: config.dailyCalories / 4,
                    onAccept: acceptSuggestion,
                    onRegenerate: generateMealSuggestion,
                    onCustomize: { showMealOptions = true }
                )
            } else {
                // Generate prompt
                Button(action: generateMealSuggestion) {
                    VStack(spacing: 12) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 40))
                            .foregroundStyle(.blue)

                        Text("Generate \(currentMealType.rawValue)")
                            .font(.headline)

                        Text("AI will suggest a meal based on your preferences")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(40)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .cornerRadius(16)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Bottom Actions
    private var bottomActions: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                HStack {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(uiColor: .tertiarySystemGroupedBackground))
                .foregroundStyle(.primary)
                .cornerRadius(12)
            }

            if progress >= 1.0 {
                Button(action: onComplete) {
                    HStack {
                        Text("Review Plan")
                        Image(systemName: "chevron.right")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
                }
            } else {
                Button(action: skipToNext) {
                    HStack {
                        Text("Skip")
                        Image(systemName: "chevron.right")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(uiColor: .tertiarySystemGroupedBackground))
                    .foregroundStyle(.secondary)
                    .cornerRadius(12)
                }
            }
        }
        .padding()
        .background(Color(uiColor: .systemBackground))
    }

    // MARK: - Actions
    private func generateMealSuggestion() {
        isGenerating = true
        currentSuggestion = nil

        Task {
            do {
                let suggestion = try await MealSuggestionService.shared.generateMealSuggestion(
                    type: currentMealType,
                    targetCalories: config.dailyCalories / 4,
                    goal: config.goal,
                    restrictions: config.restrictions,
                    existingMeals: currentDay?.meals ?? []
                )
                await MainActor.run {
                    currentSuggestion = suggestion
                    isGenerating = false
                }
            } catch {
                await MainActor.run {
                    // Fallback to a default suggestion
                    currentSuggestion = createFallbackMeal()
                    isGenerating = false
                }
            }
        }
    }

    private func acceptSuggestion() {
        guard let suggestion = currentSuggestion else { return }

        var acceptedMeal = suggestion
        acceptedMeal.isAccepted = true

        // Add to current day
        plannedDays[currentDayIndex].meals.append(acceptedMeal)

        // Clear suggestion and move to next
        currentSuggestion = nil
        moveToNext()
    }

    private func skipToNext() {
        currentSuggestion = nil
        moveToNext()
    }

    private func moveToNext() {
        // Find next unplanned meal in current day
        if let day = currentDay {
            if let nextType = mealTypes.first(where: { type in
                !day.meals.contains(where: { $0.type == type }) && type.rawValue > currentMealType.rawValue
            }) {
                currentMealType = nextType
                return
            }
        }

        // Move to next day
        if currentDayIndex < plannedDays.count - 1 {
            currentDayIndex += 1
            currentMealType = .breakfast
        }
    }

    private func nextUnplannedMealType(for day: PlannedDay) -> MealType {
        mealTypes.first(where: { type in
            !day.meals.contains(where: { $0.type == type })
        }) ?? .breakfast
    }

    private func createFallbackMeal() -> PlannedMeal {
        let targetCal = config.dailyCalories / 4
        return PlannedMeal(
            type: currentMealType,
            name: "\(currentMealType.rawValue) Option",
            calories: targetCal,
            protein: targetCal / 20,
            carbs: targetCal / 10,
            fat: targetCal / 30,
            ingredients: ["Customize your ingredients"]
        )
    }
}

// MARK: - Day Selector Button
struct DaySelectorButton: View {
    let dayName: String
    let isSelected: Bool
    let isComplete: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(String(dayName.prefix(3)))
                    .font(.caption)
                    .fontWeight(isSelected ? .bold : .regular)

                if isComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Circle()
                        .fill(isSelected ? Color.blue : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(isSelected ? Color.blue.opacity(0.15) : Color.clear)
            .cornerRadius(8)
        }
        .foregroundStyle(isSelected ? .blue : .primary)
    }
}

// MARK: - Meal Type Chip
struct MealTypeChip: View {
    let type: MealType
    let isPlanned: Bool
    let isSelected: Bool
    let action: () -> Void

    var icon: String {
        type.icon
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)

                if isPlanned {
                    Image(systemName: "checkmark")
                        .font(.caption2)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                isSelected ? Color.blue :
                isPlanned ? Color.green.opacity(0.2) :
                Color(uiColor: .tertiarySystemGroupedBackground)
            )
            .foregroundStyle(isSelected ? .white : isPlanned ? .green : .primary)
            .cornerRadius(20)
        }
    }
}

// MARK: - Nutrition Pill
struct NutritionPill: View {
    let label: String
    let value: String
    let target: Int?
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.caption)
                .fontWeight(.semibold)

            if let target = target {
                Text("/ \(target)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(color.opacity(0.1))
        .cornerRadius(20)
    }
}

// MARK: - Accepted Meal Row
struct AcceptedMealRow: View {
    let meal: PlannedMeal
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 2) {
                Text(meal.name)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text("\(meal.type.rawValue) • \(meal.calories) kcal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color.green.opacity(0.1))
        .cornerRadius(10)
    }
}
