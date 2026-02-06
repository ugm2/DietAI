import SwiftUI
import SwiftData

// MARK: - Meal Logging View
struct MealLoggingView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MealLog.loggedAt, order: .reverse) var mealLogs: [MealLog]
    @Query(sort: \DietPlan.createdAt, order: .reverse) var plans: [DietPlan]

    @State private var selectedDate = Date()
    @State private var showLogMeal = false
    @State private var showQuickAdd = false

    private var todayLogs: [MealLog] {
        let calendar = Calendar.current
        return mealLogs.filter { calendar.isDate($0.loggedAt, inSameDayAs: selectedDate) }
    }

    private var totalCalories: Int {
        todayLogs.reduce(0) { $0 + $1.calories }
    }

    private var totalProtein: Int {
        todayLogs.reduce(0) { $0 + $1.protein }
    }

    private var totalCarbs: Int {
        todayLogs.reduce(0) { $0 + $1.carbs }
    }

    private var totalFat: Int {
        todayLogs.reduce(0) { $0 + $1.fat }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Date picker
                DatePicker("Date", selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .padding()
                    .background(Color(uiColor: .secondarySystemGroupedBackground))

                List {
                    // Daily summary
                    Section {
                        DailySummaryCard(
                            calories: totalCalories,
                            protein: totalProtein,
                            carbs: totalCarbs,
                            fat: totalFat
                        )
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }

                    // Logged meals
                    Section {
                        if todayLogs.isEmpty {
                            ContentUnavailableView(
                                "No meals logged",
                                systemImage: "fork.knife",
                                description: Text("Tap + to log your first meal")
                            )
                        } else {
                            ForEach(todayLogs) { log in
                                MealLogRow(log: log)
                            }
                            .onDelete(perform: deleteLog)
                        }
                    } header: {
                        Text("Logged Meals")
                    }

                    // Suggested meals from plan
                    if let currentPlan = plans.first {
                        Section {
                            ForEach(suggestedMeals(from: currentPlan), id: \.id) { meal in
                                SuggestedMealRow(meal: meal) {
                                    logMeal(meal)
                                }
                            }
                        } header: {
                            Text("From Your Plan")
                        } footer: {
                            Text("Tap to log meals from your current plan")
                        }
                    }
                }
            }
            .navigationTitle("Meal Log")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(action: { showLogMeal = true }) {
                            Label("Log from Plan", systemImage: "list.bullet")
                        }
                        Button(action: { showQuickAdd = true }) {
                            Label("Quick Add", systemImage: "plus.circle")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                    }
                }
            }
            .sheet(isPresented: $showLogMeal) {
                if let plan = plans.first {
                    SelectMealToLogView(plan: plan) { meal in
                        logMeal(meal)
                        showLogMeal = false
                    }
                }
            }
            .sheet(isPresented: $showQuickAdd) {
                QuickAddMealView(date: selectedDate)
            }
        }
    }

    private func suggestedMeals(from plan: DietPlan) -> [Meal] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "EEEE"
        let dayName = formatter.string(from: selectedDate)

        guard let day = plan.days.first(where: { $0.dayName.lowercased() == dayName.lowercased() }) else {
            return []
        }

        // Filter out already logged meals
        let loggedMealIds = Set(todayLogs.compactMap { $0.originalMeal?.id })
        return day.meals.filter { !loggedMealIds.contains($0.id) }
    }

    private func logMeal(_ meal: Meal) {
        let log = MealLog(meal: meal)
        modelContext.insert(log)

        // Mark the meal as logged
        meal.markAsLogged()

        // Log to HealthKit
        Task {
            let healthService = HealthKitService.shared
            if healthService.isAuthorized {
                try? await healthService.logMealNutrition(meal: meal, date: selectedDate)
            }
        }

        try? modelContext.save()
    }

    private func deleteLog(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(todayLogs[index])
        }
    }
}

// MARK: - Daily Summary Card
struct DailySummaryCard: View {
    let calories: Int
    let protein: Int
    let carbs: Int
    let fat: Int

    @Query var userProfiles: [UserProfile]
    private var target: Int { userProfiles.first?.dailyCalorieTarget ?? 2000 }

    var body: some View {
        VStack(spacing: 16) {
            // Calorie progress
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Calories")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(calories)")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                        Text("/ \(target)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Ring
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: min(Double(calories) / Double(target), 1.0))
                        .stroke(progressColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(Int(Double(calories) / Double(target) * 100))%")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .frame(width: 60, height: 60)
            }

            // Macros
            HStack(spacing: 12) {
                MacroProgressBar(label: "Protein", value: protein, goal: 150, color: .red)
                MacroProgressBar(label: "Carbs", value: carbs, goal: 200, color: .blue)
                MacroProgressBar(label: "Fat", value: fat, goal: 65, color: .yellow)
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(16)
        .padding(.horizontal)
    }

    private var progressColor: Color {
        let progress = Double(calories) / Double(target)
        if progress < 0.5 { return .green }
        if progress < 0.85 { return .blue }
        if progress <= 1.0 { return .orange }
        return .red
    }
}

struct MacroProgressBar: View {
    let label: String
    let value: Int
    let goal: Int
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text("\(value)g")
                .font(.headline)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(color.opacity(0.2))
                    Capsule()
                        .fill(color)
                        .frame(width: geo.size.width * min(CGFloat(value) / CGFloat(goal), 1.0))
                }
            }
            .frame(height: 6)

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Meal Log Row
struct MealLogRow: View {
    let log: MealLog

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconFor(log.mealType))
                .font(.title2)
                .foregroundStyle(colorFor(log.mealType))
                .frame(width: 40, height: 40)
                .background(colorFor(log.mealType).opacity(0.15))
                .cornerRadius(10)

            VStack(alignment: .leading, spacing: 2) {
                Text(log.mealName)
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack(spacing: 8) {
                    Text(log.mealType.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(log.loggedAt.formatted(date: .omitted, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(log.calories)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("kcal")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func iconFor(_ type: MealType) -> String {
        type.icon
    }

    private func colorFor(_ type: MealType) -> Color {
        type.color
    }
}

// MARK: - Suggested Meal Row
struct SuggestedMealRow: View {
    let meal: Meal
    let onLog: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(meal.name)
                    .font(.subheadline)
                Text(meal.typeRaw)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(meal.calories) kcal")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button(action: onLog) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Select Meal to Log View
struct SelectMealToLogView: View {
    @Environment(\.dismiss) private var dismiss
    let plan: DietPlan
    let onSelect: (Meal) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(plan.days.sorted(by: { $0.date < $1.date })) { day in
                    Section(day.dayName) {
                        ForEach(day.meals) { meal in
                            Button {
                                onSelect(meal)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(meal.name)
                                            .font(.subheadline)
                                        Text(meal.typeRaw)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text("\(meal.calories) kcal")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }
            }
            .navigationTitle("Log a Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Quick Add Meal View
struct QuickAddMealView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let date: Date

    @State private var mealName = ""
    @State private var mealType: MealType = .lunch
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
            .navigationTitle("Quick Add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addMeal()
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

    private func addMeal() {
        let meal = Meal(
            type: mealType,
            name: mealName,
            calories: Int(calories) ?? 0,
            protein: Int(protein) ?? 0,
            carbs: Int(carbs) ?? 0,
            fat: Int(fat) ?? 0
        )

        let log = MealLog(meal: meal)
        modelContext.insert(log)

        // Mark the meal as logged
        meal.markAsLogged()

        // Log to HealthKit
        Task {
            let healthService = HealthKitService.shared
            if healthService.isAuthorized {
                try? await healthService.logMealNutrition(meal: meal, date: date)
            }
        }

        try? modelContext.save()
    }
}
