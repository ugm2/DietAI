import SwiftUI
import SwiftData

// MARK: - Plan View (Integrated Plan Builder + Viewer)
struct PlanView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DietPlan.createdAt, order: .reverse) var plans: [DietPlan]
    @Query var userProfiles: [UserProfile]

    @State private var showCreateWizard = false
    @State private var selectedDayIndex = 0

    private var currentPlan: DietPlan? { plans.first }
    private var userProfile: UserProfile? { userProfiles.first }

    var body: some View {
        NavigationStack {
            Group {
                if let plan = currentPlan {
                    // Has plan - show plan viewer
                    PlanViewerContent(
                        plan: plan,
                        selectedDayIndex: $selectedDayIndex,
                        onCreateNew: { showCreateWizard = true }
                    )
                } else {
                    // No plan - show empty state with create button
                    noPlanView
                }
            }
            .navigationTitle(currentPlan != nil ? "Your Plan" : "Plan")
            .toolbar {
                if currentPlan != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button(action: { showCreateWizard = true }) {
                                Label("Create New Plan", systemImage: "plus")
                            }

                            NavigationLink {
                                ShoppingListView()
                            } label: {
                                Label("Shopping List", systemImage: "cart")
                            }

                            Divider()

                            Button(role: .destructive) {
                                deletePlan()
                            } label: {
                                Label("Delete Plan", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .sheet(isPresented: $showCreateWizard) {
                PlanWizardView()
            }
        }
    }

    // MARK: - No Plan Empty State
    private var noPlanView: some View {
        ContentUnavailableView {
            Label("No Meal Plan", systemImage: "list.bullet.clipboard")
        } description: {
            Text("Create your first personalized AI meal plan")
        } actions: {
            Button(action: { showCreateWizard = true }) {
                HStack {
                    Image(systemName: "wand.and.stars")
                    Text("Create Plan")
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func deletePlan() {
        if let plan = currentPlan {
            modelContext.delete(plan)
            try? modelContext.save()
        }
    }
}

// MARK: - Plan Viewer Content
struct PlanViewerContent: View {
    let plan: DietPlan
    @Binding var selectedDayIndex: Int
    let onCreateNew: () -> Void

    @State private var showTweakSheet = false

    private var sortedDays: [DailyPlan] {
        plan.days.sorted { $0.date < $1.date }
    }

    private var selectedDay: DailyPlan? {
        guard selectedDayIndex < sortedDays.count else { return nil }
        return sortedDays[selectedDayIndex]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Plan summary card
                planSummaryCard

                // Day selector
                daySelector

                // Selected day meals
                if let day = selectedDay {
                    dayMealsSection(day)
                }

                // Quick actions
                quickActionsSection
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    // MARK: - Plan Summary Card
    private var planSummaryCard: some View {
        VStack(spacing: 16) {
            // Date range header
            if let firstDay = sortedDays.first, let lastDay = sortedDays.last {
                Text(weekRangeString(from: firstDay.date, to: lastDay.date))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Goal: \(plan.goal)")
                        .font(.headline)

                    HStack(spacing: 8) {
                        Label("\(plan.dailyCaloriesTarget) kcal", systemImage: "flame.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)

                        if plan.maxPrepTimeMinutes > 0 {
                            Text("•")
                                .foregroundStyle(.tertiary)

                            Label("≤\(plan.maxPrepTimeMinutes) min", systemImage: "clock.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                // Completion ring
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 6)

                    Circle()
                        .trim(from: 0, to: completionProgress)
                        .stroke(Color.green, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))

                    Text("\(Int(completionProgress * 100))%")
                        .font(.caption2)
                        .fontWeight(.semibold)
                }
                .frame(width: 50, height: 50)
            }

            // Week progress indicator
            HStack(spacing: 4) {
                ForEach(sortedDays.indices, id: \.self) { index in
                    let day = sortedDays[index]
                    let loggedCount = day.meals.filter { $0.isLogged }.count
                    let totalCount = day.meals.count

                    Circle()
                        .fill(progressColor(for: day, loggedCount: loggedCount, totalCount: totalCount))
                        .frame(width: 8, height: 8)
                }

                Spacer()

                if let todayIndex = sortedDays.firstIndex(where: { isToday($0) }) {
                    Text("Day \(todayIndex + 1) of \(sortedDays.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(16)
    }

    private var completionProgress: Double {
        let totalMeals = sortedDays.flatMap { $0.meals }.count
        let loggedMeals = sortedDays.flatMap { $0.meals }.filter { $0.isLogged }.count
        guard totalMeals > 0 else { return 0 }
        return Double(loggedMeals) / Double(totalMeals)
    }

    private func weekRangeString(from start: Date, to end: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "Week of \(formatter.string(from: start)) - \(formatter.string(from: end))"
    }

    private func progressColor(for day: DailyPlan, loggedCount: Int, totalCount: Int) -> Color {
        if isToday(day) {
            return .blue
        } else if isPast(day) {
            if loggedCount >= totalCount && totalCount > 0 {
                return .green
            } else if loggedCount > 0 {
                return .orange
            } else {
                return .gray.opacity(0.3)
            }
        } else {
            return .gray.opacity(0.3)
        }
    }

    // MARK: - Day Selector
    private var daySelector: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(sortedDays.enumerated()), id: \.element.id) { index, day in
                        DaySelectorPill(
                            dayName: day.dayName,
                            isSelected: index == selectedDayIndex,
                            isToday: isToday(day),
                            isPast: isPast(day),
                            calories: day.meals.reduce(0) { $0 + $1.calories },
                            loggedMeals: day.meals.filter { $0.isLogged }.count,
                            totalMeals: day.meals.count
                        ) {
                            withAnimation { selectedDayIndex = index }
                        }
                        .id(index)
                    }
                }
                .padding(.horizontal, 4)
            }
            .onAppear {
                // Auto-select today
                if let todayIndex = sortedDays.firstIndex(where: { isToday($0) }) {
                    selectedDayIndex = todayIndex
                    proxy.scrollTo(todayIndex, anchor: .center)
                }
            }
        }
    }

    // MARK: - Day Meals Section
    private func dayMealsSection(_ day: DailyPlan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(day.dayName)
                    .font(.headline)

                Spacer()

                Text("\(day.meals.reduce(0) { $0 + $1.calories }) kcal")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ForEach(day.meals.sorted { mealOrder($0.type) < mealOrder($1.type) }) { meal in
                NavigationLink {
                    MealDetailView(meal: meal, dailyPlan: day)
                } label: {
                    PlanMealCard(meal: meal)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Quick Actions
    private var quickActionsSection: some View {
        VStack(spacing: 12) {
            // Tweak Plan button
            Button {
                showTweakSheet = true
            } label: {
                HStack {
                    Image(systemName: "wand.and.sparkles")
                        .foregroundStyle(.purple)
                    Text("Tweak Plan")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }
                .padding()
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .cornerRadius(12)
            }
            .buttonStyle(.plain)

            NavigationLink {
                ShoppingListView()
            } label: {
                HStack {
                    Image(systemName: "cart.fill")
                        .foregroundStyle(.green)
                    Text("Generate Shopping List")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }
                .padding()
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .cornerRadius(12)
            }
            .buttonStyle(.plain)

            Button(action: onCreateNew) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.blue)
                    Text("Create New Plan")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }
                .padding()
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $showTweakSheet) {
            TweakPlanSheet(plan: plan)
                .presentationDetents([.large])
        }
    }

    // MARK: - Helpers
    private func isToday(_ day: DailyPlan) -> Bool {
        Calendar.current.isDateInToday(day.date)
    }

    private func isPast(_ day: DailyPlan) -> Bool {
        day.date < Calendar.current.startOfDay(for: Date())
    }

    private func mealOrder(_ type: MealType) -> Int {
        type.sortOrder
    }
}

// MARK: - Day Selector Pill
struct DaySelectorPill: View {
    let dayName: String
    let isSelected: Bool
    let isToday: Bool
    let isPast: Bool
    let calories: Int
    let loggedMeals: Int
    let totalMeals: Int
    let action: () -> Void

    private var progressStatus: DayProgressStatus {
        if isPast || isToday {
            if loggedMeals == 0 {
                return .notStarted
            } else if loggedMeals >= totalMeals {
                return .complete
            } else {
                return .partial
            }
        }
        return .future
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                // Day letter
                Text(String(dayName.prefix(1)))
                    .font(.subheadline)
                    .fontWeight(isSelected ? .bold : .medium)

                // Progress indicator
                progressIndicator

                // Calories
                if isSelected {
                    Text("\(calories)")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .padding(.horizontal, isSelected ? 14 : 10)
            .padding(.vertical, 10)
            .background(isSelected ? Color.blue : Color(uiColor: .secondarySystemGroupedBackground))
            .foregroundStyle(isSelected ? .white : .primary)
            .cornerRadius(12)
        }
    }

    @ViewBuilder
    private var progressIndicator: some View {
        switch progressStatus {
        case .complete:
            Circle()
                .fill(isSelected ? Color.white : Color.green)
                .frame(width: 8, height: 8)
        case .partial:
            Circle()
                .strokeBorder(isSelected ? Color.white : Color.orange, lineWidth: 2)
                .background(Circle().fill(isSelected ? Color.white.opacity(0.3) : Color.orange.opacity(0.3)))
                .frame(width: 8, height: 8)
        case .notStarted:
            if isToday {
                Circle()
                    .fill(isSelected ? Color.white : Color.blue)
                    .frame(width: 8, height: 8)
            } else {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        case .future:
            Circle()
                .strokeBorder(Color.gray.opacity(0.3), lineWidth: 1)
                .frame(width: 8, height: 8)
        }
    }
}

enum DayProgressStatus {
    case complete   // All meals logged
    case partial    // Some meals logged
    case notStarted // No meals logged (past or today)
    case future     // Future day
}

// MARK: - Plan Meal Card
struct PlanMealCard: View {
    let meal: Meal

    var body: some View {
        HStack(spacing: 12) {
            // Meal type icon
            Image(systemName: mealIcon)
                .font(.title3)
                .foregroundStyle(mealColor)
                .frame(width: 40, height: 40)
                .background(mealColor.opacity(0.15))
                .cornerRadius(10)

            VStack(alignment: .leading, spacing: 4) {
                // Meal name with logged indicator
                HStack(spacing: 6) {
                    Text(meal.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if meal.isLogged {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }

                // Stats: calories, prep time, difficulty
                HStack(spacing: 8) {
                    Text("\(meal.calories) kcal")
                        .foregroundStyle(.secondary)

                    Text("•")
                        .foregroundStyle(.tertiary)

                    Text("\(meal.prepTimeMinutes) min")
                        .foregroundStyle(.secondary)

                    Text("•")
                        .foregroundStyle(.tertiary)

                    Text(meal.difficulty.rawValue)
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    private var mealIcon: String {
        meal.type.icon
    }

    private var mealColor: Color {
        meal.type.color
    }
}

// MARK: - Plan Builder Content (Integrated)
struct PlanBuilderContent: View {
    @Environment(\.modelContext) private var modelContext
    let userProfile: UserProfile?
    let onComplete: () -> Void
    let onCancel: (() -> Void)?

    @State private var currentStep: PlanBuilderStep = .setup
    @State private var config = PlanConfiguration()
    @State private var plannedDays: [PlannedDay] = []
    @State private var currentDayIndex = 0
    @State private var currentMealType: MealType = .breakfast
    @State private var isGenerating = false

    // Agentic generation mode
    @State private var builderMode: PlanBuilderMode = .manual
    @State private var agenticGenerator = AgenticPlanGenerator()

    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator
            progressIndicator

            // Content
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
                        onComplete: { withAnimation { currentStep = .review } },
                        onBack: { withAnimation { currentStep = .setup } }
                    )
                }
            case .review:
                PlanReviewStep(
                    config: config,
                    plannedDays: plannedDays,
                    onSave: savePlan,
                    onBack: { withAnimation { currentStep = .planning } }
                )
            }
        }
        .toolbar {
            if let cancel = onCancel {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: cancel)
                }
            }
        }
        .onAppear {
            if let profile = userProfile {
                config.dailyCalories = profile.dailyCalorieTarget ?? 2000
                config.goal = profile.goalType ?? .maintenance
                config.restrictions = profile.dietaryRestrictionsArray
            }
        }
    }

    private var progressIndicator: some View {
        HStack(spacing: 0) {
            ForEach(PlanBuilderStep.allCases, id: \.rawValue) { step in
                VStack(spacing: 4) {
                    Circle()
                        .fill(step.rawValue <= currentStep.rawValue ? Color.blue : Color.gray.opacity(0.3))
                        .frame(width: 28, height: 28)
                        .overlay {
                            if step.rawValue < currentStep.rawValue {
                                Image(systemName: "checkmark")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.white)
                            } else {
                                Text("\(step.rawValue + 1)")
                                    .font(.caption2)
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

    private func initializeDays() {
        plannedDays = config.dayNames.enumerated().map { index, name in
            let date = Calendar.current.date(byAdding: .day, value: index, to: config.startDate) ?? config.startDate
            return PlannedDay(dayName: name, date: date)
        }
    }

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

        onComplete()
    }
}
