import SwiftUI
import SwiftData

// MARK: - Today View (Primary Home Screen)
struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DietPlan.createdAt, order: .reverse) var plans: [DietPlan]
    @Query(sort: \MealLog.loggedAt, order: .reverse) var mealLogs: [MealLog]
    @Query var userProfiles: [UserProfile]

    @State private var showQuickActions = false
    @State private var showSettings = false
    @State private var showAddCustomMeal = false
    @State private var showBarcodeScanner = false

    // HealthKit activity data
    @State private var healthService = HealthKitService.shared
    @State private var enhancedActivity: EnhancedActivitySummary?
    @State private var smartTarget: SmartCalorieTarget?

    private var currentPlan: DietPlan? { plans.first }
    private var userProfile: UserProfile? { userProfiles.first }

    // Get today's daily plan
    private var todayDailyPlan: DailyPlan? {
        guard let plan = currentPlan else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        let todayName = formatter.string(from: Date())

        return plan.days.first(where: {
            $0.dayName.lowercased() == todayName.lowercased()
        })
    }

    // Get today's meals from plan
    private var todayMeals: [Meal] {
        guard let day = todayDailyPlan else { return [] }
        return day.meals.sorted { mealOrder($0.type) < mealOrder($1.type) }
    }

    // Get today's logged meals
    private var todayLogs: [MealLog] {
        let calendar = Calendar.current
        return mealLogs.filter { calendar.isDateInToday($0.loggedAt) }
    }

    // Calories consumed today
    private var caloriesConsumed: Int {
        todayLogs.reduce(0) { $0 + $1.calories }
    }

    // Base daily calorie target
    private var baseCalorieTarget: Int {
        userProfile?.dailyCalorieTarget ?? currentPlan?.dailyCaloriesTarget ?? 2000
    }

    // Active calories burned today (from HealthKit)
    private var activeCaloriesBurned: Int {
        enhancedActivity?.activeCalories ?? 0
    }

    // Use smart target if available, otherwise base target
    private var calorieTarget: Int {
        smartTarget?.total ?? baseCalorieTarget
    }

    // Only show bonus from actual workouts today (not weekly trend)
    private var activityBonus: Int {
        smartTarget?.workoutBonus ?? 0
    }

    // Next meal to eat
    private var upNextMeal: Meal? {
        let loggedMealIds = Set(todayLogs.compactMap { $0.originalMeal?.id })
        return todayMeals.first { !loggedMealIds.contains($0.id) }
    }

    // Remaining meals
    private var laterMeals: [Meal] {
        let loggedMealIds = Set(todayLogs.compactMap { $0.originalMeal?.id })
        return todayMeals.filter { meal in
            !loggedMealIds.contains(meal.id) && meal.id != upNextMeal?.id
        }
    }

    // Greeting based on time
    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ScrollView {
                    VStack(spacing: 24) {
                        // Daily Progress Card
                        dailyProgressCard

                        // Activity Summary (if HealthKit connected)
                        if healthService.isAuthorized, let activity = enhancedActivity, activity.activeCalories > 0 || !activity.workouts.isEmpty {
                            enhancedActivityCard(activity)
                        }

                        if currentPlan != nil {
                            // Up Next Meal
                            if let meal = upNextMeal {
                                upNextSection(meal)
                            }

                            // Later Today
                            if !laterMeals.isEmpty {
                                laterTodaySection
                            }

                            // Completed Meals
                            if !todayLogs.isEmpty {
                                completedSection
                            }
                        } else {
                            // No Plan - Prompt to create
                            noPlanCard
                        }

                        Spacer(minLength: 100)
                    }
                    .padding()
                }

                // Quick Actions FAB
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        quickActionsFAB
                    }
                }
                .padding()
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(greeting)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .sheet(isPresented: $showQuickActions) {
                QuickActionsSheet()
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showAddCustomMeal) {
                AddCustomMealSheet()
            }
            .sheet(isPresented: $showBarcodeScanner) {
                BarcodeScannerSheet()
            }
            .task {
                // Load enhanced HealthKit activity data if authorized
                await loadActivityData()
            }
            .refreshable {
                // Refresh activity data on pull-to-refresh
                await loadActivityData()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                // Auto-refresh activity data when app returns from background
                Task {
                    await loadActivityData()
                }
            }
        }
    }

    // MARK: - Daily Progress Card
    private var dailyProgressCard: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Today's Progress")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(caloriesConsumed)")
                            .font(.system(size: 42, weight: .bold, design: .rounded))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("/ \(calorieTarget) kcal")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            if healthService.isAuthorized && activityBonus > 0 {
                                Text("+\(activityBonus) from activity")
                                    .font(.caption2)
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }

                Spacer()

                // Progress Ring
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 10)

                    Circle()
                        .trim(from: 0, to: min(Double(caloriesConsumed) / Double(calorieTarget), 1.0))
                        .stroke(progressColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))

                    VStack(spacing: 0) {
                        Text("\(Int(Double(caloriesConsumed) / Double(calorieTarget) * 100))")
                            .font(.title3)
                            .fontWeight(.bold)
                        Text("%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 70, height: 70)
            }

            // Workout-adjusted target breakdown (only when actual workouts today)
            if healthService.isAuthorized && (smartTarget?.workoutBonus ?? 0) > 0 {
                workoutImpactBreakdown
            }

            // Macro summary
            HStack(spacing: 12) {
                MacroMiniCard(label: "Protein", value: todayLogs.reduce(0) { $0 + $1.protein }, unit: "g", color: .red)
                MacroMiniCard(label: "Carbs", value: todayLogs.reduce(0) { $0 + $1.carbs }, unit: "g", color: .blue)
                MacroMiniCard(label: "Fat", value: todayLogs.reduce(0) { $0 + $1.fat }, unit: "g", color: .yellow)
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(20)
    }

    // MARK: - Workout Impact Breakdown
    private var workoutImpactBreakdown: some View {
        VStack(spacing: 8) {
            Divider()

            HStack(spacing: 16) {
                // Base target
                VStack(spacing: 2) {
                    Text("\(baseCalorieTarget)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("base")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Image(systemName: "plus")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Activity bonus
                VStack(spacing: 2) {
                    Text("+\(activityBonus)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.blue)
                    Text("activity")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Image(systemName: "equal")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Total
                VStack(spacing: 2) {
                    Text("\(calorieTarget)")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(.green)
                    Text("total")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Protein boost indicator (if strength training)
                if let target = smartTarget, target.proteinBoostPerKg > 0 {
                    VStack(spacing: 2) {
                        Image(systemName: "bolt.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Text("+protein")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private var progressColor: Color {
        let progress = Double(caloriesConsumed) / Double(calorieTarget)
        if progress < 0.5 { return .green }
        if progress < 0.85 { return .blue }
        if progress <= 1.0 { return .orange }
        return .red
    }

    // MARK: - Enhanced Activity Card
    private func enhancedActivityCard(_ activity: EnhancedActivitySummary) -> some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Label("Today's Activity", systemImage: "figure.run")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                Spacer()
                NavigationLink {
                    ActivityDetailView(activity: activity, smartTarget: smartTarget)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            // Workout badges (if any)
            if !activity.workouts.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(activity.workouts) { workout in
                            WorkoutBadge(workout: workout)
                        }
                    }
                }
            }

            // Stats row
            HStack(spacing: 16) {
                ActivityStatItem(
                    icon: "flame.fill",
                    value: "\(activity.activeCalories)",
                    label: "burned",
                    color: .orange
                )

                Divider().frame(height: 30)

                ActivityStatItem(
                    icon: "figure.walk",
                    value: "\(activity.steps)",
                    label: "steps",
                    color: .green
                )

                // Only show budget bonus if there are actual workouts today
                if activityBonus > 0 {
                    Divider().frame(height: 30)

                    ActivityStatItem(
                        icon: "plus.circle.fill",
                        value: "+\(activityBonus)",
                        label: "budget",
                        color: .blue
                    )
                }
            }

            // Recovery window banner (if strength training recently)
            if activity.hasActiveRecoveryWindow {
                RecoveryWindowBanner()
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(16)
    }

    // MARK: - Load Activity Data
    private func loadActivityData() async {
        // Ensure authorization status is checked on each load
        healthService.checkAuthorizationStatus()

        guard healthService.isAuthorized else { return }

        let activity = await healthService.fetchEnhancedActivitySummary()
        enhancedActivity = activity

        // Calculate smart calorie target
        let goal = userProfile?.goalType ?? .maintenance
        smartTarget = healthService.calculateSmartCalorieTarget(
            baseTarget: baseCalorieTarget,
            goal: goal,
            activitySummary: activity
        )
    }

    // MARK: - Up Next Section
    private func upNextSection(_ meal: Meal) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Up Next")
                    .font(.headline)
                Spacer()
                Text(meal.type.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            UpNextMealCard(meal: meal, dailyPlan: todayDailyPlan) {
                logMeal(meal)
            }
        }
    }

    // MARK: - Later Today Section
    private var laterTodaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Later Today")
                .font(.headline)

            ForEach(laterMeals) { meal in
                NavigationLink {
                    MealDetailView(meal: meal, dailyPlan: todayDailyPlan)
                } label: {
                    LaterMealRow(meal: meal)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Completed Section
    private var completedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Completed")
                    .font(.headline)
                Spacer()
                Text("\(todayLogs.count) meals")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(todayLogs.prefix(3)) { log in
                CompletedMealRow(log: log)
            }
        }
    }

    // MARK: - No Plan Card
    private var noPlanCard: some View {
        VStack(spacing: 20) {
            Image(systemName: "fork.knife.circle")
                .font(.system(size: 60))
                .foregroundStyle(.blue.opacity(0.6))

            VStack(spacing: 8) {
                Text("No Meal Plan Yet")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("Create a personalized plan to see your daily meals here")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            NavigationLink {
                PlanView()
            } label: {
                HStack {
                    Image(systemName: "sparkles")
                    Text("Create Your Plan")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundStyle(.white)
                .cornerRadius(14)
            }
        }
        .padding(32)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(20)
    }

    // MARK: - Quick Actions FAB
    private var quickActionsFAB: some View {
        Button(action: { showQuickActions = true }) {
            Image(systemName: "fork.knife")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .frame(width: 60, height: 60)
                .background(
                    LinearGradient(
                        colors: [.orange, .red],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(Circle())
                .shadow(color: .orange.opacity(0.4), radius: 8, y: 4)
        }
    }

    // MARK: - Helpers
    private func mealOrder(_ type: MealType) -> Int {
        type.sortOrder
    }

    private func logMeal(_ meal: Meal) {
        let log = MealLog(meal: meal)
        modelContext.insert(log)

        // Mark the meal as logged
        meal.markAsLogged()

        try? modelContext.save()
    }
}

// MARK: - Supporting Views

struct MacroMiniCard: View {
    let label: String
    let value: Int
    let unit: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 2) {
                Text("\(value)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.1))
        .cornerRadius(10)
    }
}

struct UpNextMealCard: View {
    let meal: Meal
    let dailyPlan: DailyPlan?
    let onLog: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            // Navigation to detail
            NavigationLink {
                MealDetailView(meal: meal, dailyPlan: dailyPlan)
            } label: {
                HStack(spacing: 16) {
                    // Meal icon
                    Image(systemName: mealIcon)
                        .font(.title)
                        .foregroundStyle(mealColor)
                        .frame(width: 50, height: 50)
                        .background(mealColor.opacity(0.15))
                        .cornerRadius(12)

                    // Meal info
                    VStack(alignment: .leading, spacing: 4) {
                        Text(meal.name)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        HStack(spacing: 8) {
                            Text("\(meal.calories) kcal")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Text("\u{2022}")
                                .foregroundStyle(.tertiary)

                            Text("\(meal.prepTimeMinutes) min")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Text("\u{2022}")
                                .foregroundStyle(.tertiary)

                            Text(meal.difficulty.rawValue)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)

            // Log button
            Button(action: onLog) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.green)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(16)
    }

    private var mealIcon: String {
        meal.type.icon
    }

    private var mealColor: Color {
        meal.type.color
    }
}

struct LaterMealRow: View {
    let meal: Meal

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: mealIcon)
                .foregroundStyle(mealColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(meal.name)
                    .font(.subheadline)
                    .foregroundStyle(.primary)

                HStack(spacing: 6) {
                    Text("\(meal.calories) kcal")
                    Text("\u{2022}")
                    Text("\(meal.prepTimeMinutes) min")
                    Text("\u{2022}")
                    Text(meal.difficulty.rawValue)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
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

struct CompletedMealRow: View {
    let log: MealLog

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)

            Text(log.mealName)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Text("\(log.calories) kcal")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color.green.opacity(0.05))
        .cornerRadius(12)
    }
}

// MARK: - Activity Supporting Views

struct WorkoutBadge: View {
    let workout: WorkoutSummary

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: workout.category.icon)
                .font(.caption)

            VStack(alignment: .leading, spacing: 0) {
                Text(workout.category.rawValue)
                    .font(.caption2)
                    .fontWeight(.medium)
                Text("\(Int(workout.durationMinutes))m \u{2022} \(workout.calories) kcal")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(badgeColor.opacity(0.15))
        .foregroundStyle(badgeColor)
        .cornerRadius(8)
    }

    private var badgeColor: Color {
        switch workout.category {
        case .strength: return .purple
        case .cardio: return .red
        case .hiit: return .orange
        case .yoga: return .green
        case .endurance: return .blue
        case .sports: return .cyan
        case .mixed: return .gray
        case .recovery: return .mint
        }
    }
}

struct ActivityStatItem: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.headline)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct RecoveryWindowBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(.purple)

            VStack(alignment: .leading, spacing: 2) {
                Text("Recovery Window Active")
                    .font(.caption)
                    .fontWeight(.semibold)
                Text("Protein-rich meal recommended")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(10)
        .background(Color.purple.opacity(0.1))
        .cornerRadius(10)
    }
}

// MARK: - AI Assistant Sheet
struct QuickActionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DietPlan.createdAt, order: .reverse) var plans: [DietPlan]
    @Query var userProfiles: [UserProfile]

    private var userProfile: UserProfile? { userProfiles.first }
    private var currentPlan: DietPlan? { plans.first }

    // State for sheets
    @State private var showSwapSheet = false
    @State private var showUseIngredientsSheet = false
    @State private var showBarcodeScanner = false
    @State private var showAddCustomMeal = false
    @State private var showFoodCamera = false
    @State private var isSwapping = false
    @State private var alternatives: [PlannedMeal] = []
    @State private var isDownloadingModel = false
    @State private var pendingAction: QuickActionType? = nil
    @State private var showSuccessMessage = false
    @State private var successMessage = ""

    private let modelManager = ModelManager.shared

    enum QuickActionType {
        case swap, useIngredients, scanBarcode, quickAdd, snapToLog

        var accentColor: Color {
            switch self {
            case .swap: return .purple
            case .useIngredients: return .green
            case .scanBarcode: return .blue
            case .quickAdd: return .orange
            case .snapToLog: return .pink
            }
        }
    }

    // Get today's daily plan
    private var todayDailyPlan: DailyPlan? {
        guard let plan = currentPlan else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        let todayName = formatter.string(from: Date())

        return plan.days.first(where: {
            $0.dayName.lowercased() == todayName.lowercased()
        })
    }

    // Get today's meals
    private var todayMeals: [Meal] {
        guard let day = todayDailyPlan else { return [] }
        return day.meals.sorted { mealOrder($0.type) < mealOrder($1.type) }
    }

    // Get next upcoming meal
    private var upNextMeal: Meal? {
        todayMeals.first { !$0.isLogged }
    }

    private func mealOrder(_ type: MealType) -> Int {
        type.sortOrder
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    Image(systemName: "fork.knife")
                        .font(.system(size: 50))
                        .foregroundStyle(.orange)

                    Text("Quick Actions")
                        .font(.title2)
                        .fontWeight(.bold)

                    if let meal = upNextMeal {
                        Text("For \(meal.type.rawValue): \(meal.name)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    } else if currentPlan == nil {
                        Text("Create a meal plan to use swap & ingredients")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    } else {
                        Text("All meals completed for today!")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.top, 40)

                // Quick actions
                VStack(spacing: 12) {
                    QuickActionButton(
                        icon: "arrow.triangle.2.circlepath",
                        title: "Swap Meal",
                        description: "Get alternative meal suggestions",
                        color: QuickActionType.swap.accentColor,
                        isEnabled: upNextMeal != nil
                    ) {
                        handleQuickAction(.swap)
                    }

                    QuickActionButton(
                        icon: "leaf.fill",
                        title: "Use Ingredients",
                        description: "Create meal from what you have",
                        color: QuickActionType.useIngredients.accentColor,
                        isEnabled: upNextMeal != nil
                    ) {
                        handleQuickAction(.useIngredients)
                    }

                    QuickActionButton(
                        icon: "barcode.viewfinder",
                        title: "Scan Barcode",
                        description: "Log food from barcode",
                        color: QuickActionType.scanBarcode.accentColor,
                        isEnabled: true
                    ) {
                        handleQuickAction(.scanBarcode)
                    }

                    QuickActionButton(
                        icon: "plus.circle.fill",
                        title: "Quick Add",
                        description: "Manually log calories and macros",
                        color: QuickActionType.quickAdd.accentColor,
                        isEnabled: true
                    ) {
                        handleQuickAction(.quickAdd)
                    }

                    QuickActionButton(
                        icon: "camera.viewfinder",
                        title: "Snap to Log",
                        description: "Take a photo to estimate calories",
                        color: QuickActionType.snapToLog.accentColor,
                        isEnabled: true
                    ) {
                        handleQuickAction(.snapToLog)
                    }
                }
                .padding(.horizontal)

                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showSwapSheet) {
                if let meal = upNextMeal {
                    MealSwapSheet(
                        originalMeal: meal,
                        alternatives: alternatives,
                        isLoading: isSwapping,
                        onSelect: { newMeal in
                            swapMeal(meal, with: newMeal)
                        },
                        onRegenerate: { preference in
                            Task { await generateAlternatives(for: meal, preference: preference) }
                        },
                        accentColor: QuickActionType.swap.accentColor
                    )
                    .presentationDetents([.large])
                }
            }
            .sheet(isPresented: $showUseIngredientsSheet) {
                if let meal = upNextMeal {
                    UseIngredientsSheet(
                        meal: meal,
                        onGenerate: { newMeal in
                            applyMealChanges(to: meal, from: newMeal)
                        },
                        accentColor: QuickActionType.useIngredients.accentColor
                    )
                    .presentationDetents([.large])
                }
            }
            .sheet(isPresented: $showBarcodeScanner) {
                BarcodeScannerSheet()
            }
            .sheet(isPresented: $showAddCustomMeal) {
                AddCustomMealSheet()
            }
            .sheet(isPresented: $showFoodCamera) {
                FoodCameraSheet(accentColor: QuickActionType.snapToLog.accentColor)
            }
            .fullScreenCover(isPresented: $isDownloadingModel) {
                ModelDownloadView(
                    modelManager: modelManager,
                    onComplete: {
                        isDownloadingModel = false
                        // Continue with pending action after model is ready
                        if let action = pendingAction {
                            executePendingAction(action)
                        }
                    },
                    onCancel: {
                        isDownloadingModel = false
                        pendingAction = nil
                    }
                )
                .interactiveDismissDisabled()
            }
            .overlay(alignment: .top) {
                if showSuccessMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                        Text(successMessage)
                    }
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.green)
                    .cornerRadius(20)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 8)
                }
            }
            .animation(.easeInOut, value: showSuccessMessage)
        }
    }

    // MARK: - Action Handling

    private func handleQuickAction(_ action: QuickActionType) {
        // For swap action, check if model needs to be downloaded first
        if action == .swap && !modelManager.isModelLoaded {
            pendingAction = action
            isDownloadingModel = true
            return
        }

        executePendingAction(action)
    }

    private func executePendingAction(_ action: QuickActionType) {
        pendingAction = nil

        switch action {
        case .swap:
            showSwapSheet = true
            if let meal = upNextMeal {
                Task { await generateAlternatives(for: meal, preference: "") }
            }
        case .useIngredients:
            showUseIngredientsSheet = true
        case .scanBarcode:
            showBarcodeScanner = true
        case .quickAdd:
            showAddCustomMeal = true
        case .snapToLog:
            showFoodCamera = true
        }
    }

    // MARK: - AI Actions

    private func generateAlternatives(for meal: Meal, preference: String) async {
        isSwapping = true

        do {
            let service = MealSuggestionService.shared
            var newAlternatives: [PlannedMeal] = []

            // Generate 3 alternatives
            for _ in 0..<3 {
                let alternative = try await service.generateMealSuggestionWithPreference(
                    type: meal.type,
                    targetCalories: meal.calories,
                    goal: .maintenance,
                    restrictions: [],
                    existingMeals: [],
                    userPreference: preference
                )
                if !newAlternatives.contains(where: { $0.name == alternative.name }) && alternative.name != meal.name {
                    newAlternatives.append(alternative)
                }
            }

            alternatives = newAlternatives
        } catch {
            alternatives = generateFallbackAlternatives(for: meal, preference: preference)
        }

        isSwapping = false
    }

    private func generateFallbackAlternatives(for meal: Meal, preference: String) -> [PlannedMeal] {
        let defaultFallbacks: [MealType: [(String, [String], Int, Int, Int, Int)]] = [
            .breakfast: [
                ("Avocado Toast with Eggs", ["avocado", "eggs", "whole grain bread", "cherry tomatoes"], meal.calories, meal.protein, meal.carbs, meal.fat),
                ("Protein Smoothie Bowl", ["protein powder", "banana", "berries", "granola"], meal.calories, meal.protein, meal.carbs, meal.fat),
                ("Veggie Omelette", ["eggs", "spinach", "mushrooms", "feta cheese"], meal.calories, meal.protein, meal.carbs, meal.fat)
            ],
            .lunch: [
                ("Mediterranean Quinoa Bowl", ["quinoa", "chickpeas", "cucumber", "feta", "olives"], meal.calories, meal.protein, meal.carbs, meal.fat),
                ("Asian Chicken Salad", ["chicken breast", "mixed greens", "mandarin", "sesame dressing"], meal.calories, meal.protein, meal.carbs, meal.fat),
                ("Turkey Avocado Wrap", ["turkey", "avocado", "whole wheat wrap", "lettuce"], meal.calories, meal.protein, meal.carbs, meal.fat)
            ],
            .dinner: [
                ("Grilled Salmon with Vegetables", ["salmon", "asparagus", "lemon", "olive oil"], meal.calories, meal.protein, meal.carbs, meal.fat),
                ("Chicken Stir Fry", ["chicken", "broccoli", "bell peppers", "brown rice"], meal.calories, meal.protein, meal.carbs, meal.fat),
                ("Lean Beef Tacos", ["lean beef", "corn tortillas", "lettuce", "salsa"], meal.calories, meal.protein, meal.carbs, meal.fat)
            ],
            .snack: [
                ("Greek Yogurt with Berries", ["greek yogurt", "mixed berries", "honey"], meal.calories, meal.protein, meal.carbs, meal.fat),
                ("Apple with Almond Butter", ["apple", "almond butter"], meal.calories, meal.protein, meal.carbs, meal.fat),
                ("Cottage Cheese & Fruit", ["cottage cheese", "pineapple", "walnuts"], meal.calories, meal.protein, meal.carbs, meal.fat)
            ]
        ]

        let options = defaultFallbacks[meal.type] ?? defaultFallbacks[.snack] ?? []
        return options.filter { $0.0 != meal.name }.map { option in
            PlannedMeal(
                type: meal.type,
                name: option.0,
                calories: option.2,
                protein: option.3,
                carbs: option.4,
                fat: option.5,
                ingredients: option.1
            )
        }
    }

    private func swapMeal(_ meal: Meal, with newMeal: PlannedMeal) {
        meal.name = newMeal.name
        meal.calories = newMeal.calories
        meal.protein = newMeal.protein
        meal.carbs = newMeal.carbs
        meal.fat = newMeal.fat
        meal.ingredients = newMeal.ingredients

        try? modelContext.save()
        showSwapSheet = false

        // Show success and dismiss
        successMessage = "Swapped to \(newMeal.name)"
        showSuccessMessage = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            dismiss()
        }
    }

    private func applyMealChanges(to meal: Meal, from newMeal: PlannedMeal) {
        meal.name = newMeal.name
        meal.calories = newMeal.calories
        meal.protein = newMeal.protein
        meal.carbs = newMeal.carbs
        meal.fat = newMeal.fat
        meal.ingredients = newMeal.ingredients
        try? modelContext.save()

        // Show success and dismiss
        successMessage = "Meal updated to \(newMeal.name)"
        showSuccessMessage = true

        // Dismiss the AI sheet after a short delay to show feedback
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            dismiss()
        }
    }
}

struct QuickActionButton: View {
    let icon: String
    let title: String
    let description: String
    var color: Color = .purple
    var isEnabled: Bool = true
    var action: (() -> Void)? = nil

    var body: some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(isEnabled ? color : .gray)
                    .frame(width: 40, height: 40)
                    .background((isEnabled ? color : Color.gray).opacity(0.1))
                    .cornerRadius(10)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(isEnabled ? .primary : .secondary)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1.0 : 0.6)
    }
}

struct SuggestionButton: View {
    let text: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(text)
                    .font(.subheadline)
                Spacer()
                Image(systemName: "arrow.right.circle.fill")
                    .foregroundStyle(.purple)
            }
            .padding()
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Meal Options Sheet
struct MealOptionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let meal: Meal
    let onLog: () -> Void
    let onSwap: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Meal details
                VStack(spacing: 12) {
                    Image(systemName: mealIcon)
                        .font(.system(size: 50))
                        .foregroundStyle(mealColor)

                    Text(meal.name)
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("\(meal.calories) kcal • \(meal.protein)g protein")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 20)

                // Ingredients
                if !meal.ingredients.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ingredients")
                            .font(.headline)

                        ForEach(meal.ingredients) { ingredient in
                            HStack {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 6, height: 6)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ingredient.name.capitalized)
                                        .font(.subheadline)
                                    if !ingredient.quantity.isEmpty {
                                        Text(ingredient.quantity)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .cornerRadius(12)
                }

                Spacer()

                // Actions
                VStack(spacing: 12) {
                    Button(action: {
                        onLog()
                        dismiss()
                    }) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Log This Meal")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundStyle(.white)
                        .cornerRadius(14)
                    }

                    Button(action: {
                        onSwap()
                        dismiss()
                    }) {
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("I Want Something Else")
                        }
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(uiColor: .tertiarySystemGroupedBackground))
                        .foregroundStyle(.primary)
                        .cornerRadius(14)
                    }
                }
            }
            .padding()
            .navigationTitle(meal.type.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var mealIcon: String {
        meal.type.icon
    }

    private var mealColor: Color {
        meal.type.color
    }
}

// MARK: - Add Custom Meal Sheet
struct AddCustomMealSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var mealName = ""
    @State private var mealType: MealType = .snack
    @State private var calories = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Meal Info") {
                    TextField("Meal name", text: $mealName)

                    Picker("Type", selection: $mealType) {
                        ForEach(MealType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                }

                Section("Nutrition") {
                    HStack {
                        Text("Calories")
                        Spacer()
                        TextField("0", text: $calories)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("kcal")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Protein")
                        Spacer()
                        TextField("0", text: $protein)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("g")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Carbs")
                        Spacer()
                        TextField("0", text: $carbs)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("g")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Fat")
                        Spacer()
                        TextField("0", text: $fat)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("g")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Add Custom Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addMealLog()
                        dismiss()
                    }
                    .disabled(mealName.isEmpty || calories.isEmpty)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
        }
    }

    private func addMealLog() {
        let log = MealLog(
            name: mealName,
            type: mealType,
            calories: Int(calories) ?? 0,
            protein: Int(protein) ?? 0,
            carbs: Int(carbs) ?? 0,
            fat: Int(fat) ?? 0
        )
        modelContext.insert(log)
        try? modelContext.save()
    }
}
