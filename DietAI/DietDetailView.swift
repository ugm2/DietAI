import SwiftUI
import SwiftData

struct DietDetailView: View {
    let plan: DietPlan

    // Computed nutrition totals
    private var allMeals: [Meal] {
        plan.days.flatMap { $0.meals }
    }

    private var totalCalories: Int {
        allMeals.reduce(0) { $0 + $1.calories }
    }

    private var totalProtein: Int {
        allMeals.reduce(0) { $0 + $1.protein }
    }

    private var totalCarbs: Int {
        allMeals.reduce(0) { $0 + $1.carbs }
    }

    private var totalFat: Int {
        allMeals.reduce(0) { $0 + $1.fat }
    }

    private var avgCaloriesPerDay: Int {
        guard plan.days.count > 0 else { return 0 }
        return totalCalories / plan.days.count
    }

    var body: some View {
        List {
            // Section 1: Plan Overview
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Label(plan.goal, systemImage: "flag.fill")
                        .font(.headline)

                    Label("\(plan.dailyCaloriesTarget) kcal / day", systemImage: "flame.fill")
                        .foregroundStyle(.secondary)

                    Text("Created on \(plan.createdAt.formatted(date: .long, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.gray)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Overview")
            }

            // Section 2: Nutrition Dashboard
            Section {
                // Calorie ring
                CalorieRingView(
                    consumed: avgCaloriesPerDay,
                    target: plan.dailyCaloriesTarget
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)

                // Macro summary
                HStack(spacing: 16) {
                    MacroSummaryCard(
                        title: "Protein",
                        value: totalProtein / max(plan.days.count, 1),
                        unit: "g/day",
                        color: .red,
                        icon: "figure.strengthtraining.traditional"
                    )
                    MacroSummaryCard(
                        title: "Carbs",
                        value: totalCarbs / max(plan.days.count, 1),
                        unit: "g/day",
                        color: .blue,
                        icon: "leaf.fill"
                    )
                    MacroSummaryCard(
                        title: "Fat",
                        value: totalFat / max(plan.days.count, 1),
                        unit: "g/day",
                        color: .yellow,
                        icon: "drop.fill"
                    )
                }
            } header: {
                Text("Nutrition Dashboard")
            }

            // Section 3: Days & Meals
            // We sort by date to ensure Monday comes before Tuesday (if generated in order)
            ForEach(plan.days.sorted(by: { $0.date < $1.date })) { day in
                Section(header: Text(day.dayName).font(.headline).foregroundStyle(.primary)) {
                    
                    if day.meals.isEmpty {
                        Text("No meals recorded").italic().foregroundStyle(.secondary)
                    } else {
                        ForEach(day.meals) { meal in
                            MealRowView(meal: meal)
                        }
                    }
                }
            }
        }
        .navigationTitle(plan.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// Helper View for a single meal row
struct MealRowView: View {
    @Environment(\.modelContext) private var modelContext
    let meal: Meal
    @State private var isExpanded = false
    @State private var isLogged = false
    @State private var showLoggingSuccess = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Main row
            HStack {
                Image(systemName: iconFor(meal.type))
                    .foregroundStyle(.blue)
                    .frame(width: 24)

                VStack(alignment: .leading) {
                    Text(meal.name)
                        .font(.body)
                        .bold()
                    Text(meal.typeRaw)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing) {
                    HStack(spacing: 2) {
                        Text("\(meal.calories)")
                            .font(.system(.callout, design: .monospaced))
                            .bold()
                        Text("kcal")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    // Macro summary
                    if meal.protein > 0 || meal.carbs > 0 || meal.fat > 0 {
                        HStack(spacing: 6) {
                            MacroPill(value: meal.protein, label: "P", color: .red)
                            MacroPill(value: meal.carbs, label: "C", color: .blue)
                            MacroPill(value: meal.fat, label: "F", color: .yellow)
                        }
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.3)) {
                    isExpanded.toggle()
                }
            }

            // Expanded details
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    // Macro bars
                    MacroBarView(protein: meal.protein, carbs: meal.carbs, fat: meal.fat)

                    // Ingredients
                    if !meal.ingredients.isEmpty {
                        Divider()
                        Text("Ingredients")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)

                        FlowLayout(spacing: 4) {
                            ForEach(meal.ingredients) { ingredient in
                                Text(ingredient.displayString)
                                    .font(.caption2)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.gray.opacity(0.15))
                                    .cornerRadius(8)
                            }
                        }
                    }

                    // Log meal button
                    Divider()
                    Button(action: logMeal) {
                        HStack {
                            Image(systemName: isLogged ? "checkmark.circle.fill" : "plus.circle.fill")
                            Text(isLogged ? "Logged" : "Log This Meal")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(isLogged ? Color.green.opacity(0.15) : Color.blue.opacity(0.15))
                        .foregroundStyle(isLogged ? .green : .blue)
                        .cornerRadius(8)
                    }
                    .disabled(isLogged)
                }
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 4)
        .overlay(alignment: .topTrailing) {
            if showLoggingSuccess {
                Text("Logged!")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green)
                    .cornerRadius(12)
                    .transition(.scale.combined(with: .opacity))
                    .padding(4)
            }
        }
    }

    private func logMeal() {
        let log = MealLog(meal: meal)
        modelContext.insert(log)

        // Mark the meal as logged
        meal.markAsLogged()

        // Log to HealthKit
        Task {
            let healthService = HealthKitService.shared
            if healthService.isAuthorized {
                try? await healthService.logMealNutrition(meal: meal)
            }
        }

        try? modelContext.save()

        withAnimation {
            isLogged = true
            showLoggingSuccess = true
        }

        // Hide success indicator after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showLoggingSuccess = false
            }
        }
    }

    func iconFor(_ type: MealType) -> String {
        type.icon
    }
}

// Small macro pill for compact display
struct MacroPill: View {
    let value: Int
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(color)
            Text("\(value)")
                .font(.system(size: 9, design: .monospaced))
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(color.opacity(0.15))
        .cornerRadius(4)
    }
}

// Macro bar visualization
struct MacroBarView: View {
    let protein: Int
    let carbs: Int
    let fat: Int

    private var total: Int { protein + carbs + fat }

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    if total > 0 {
                        Rectangle()
                            .fill(Color.red.opacity(0.8))
                            .frame(width: geo.size.width * CGFloat(protein) / CGFloat(total))
                        Rectangle()
                            .fill(Color.blue.opacity(0.8))
                            .frame(width: geo.size.width * CGFloat(carbs) / CGFloat(total))
                        Rectangle()
                            .fill(Color.yellow.opacity(0.8))
                            .frame(width: geo.size.width * CGFloat(fat) / CGFloat(total))
                    }
                }
                .cornerRadius(4)
            }
            .frame(height: 8)

            HStack {
                MacroLabel(name: "Protein", value: protein, color: .red)
                Spacer()
                MacroLabel(name: "Carbs", value: carbs, color: .blue)
                Spacer()
                MacroLabel(name: "Fat", value: fat, color: .yellow)
            }
        }
    }
}

struct MacroLabel: View {
    let name: String
    let value: Int
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text("\(name): \(value)g")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// Simple flow layout for ingredients
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: .unspecified)
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        let maxWidth = proposal.width ?? .infinity
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), frames)
    }
}

// MARK: - Calorie Ring View
struct CalorieRingView: View {
    let consumed: Int
    let target: Int

    private var progress: Double {
        guard target > 0 else { return 0 }
        return min(Double(consumed) / Double(target), 1.5)
    }

    private var progressColor: Color {
        if progress < 0.5 { return .green }
        if progress < 0.85 { return .blue }
        if progress <= 1.0 { return .orange }
        return .red
    }

    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: 16)

            // Progress ring
            Circle()
                .trim(from: 0, to: min(progress, 1.0))
                .stroke(
                    AngularGradient(
                        colors: [progressColor.opacity(0.6), progressColor],
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: 16, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.8), value: progress)

            // Center text
            VStack(spacing: 2) {
                Text("\(consumed)")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(progressColor)

                Text("of \(target) kcal")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if consumed > 0 {
                    Text("\(Int(progress * 100))%")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(width: 150, height: 150)
    }
}

// MARK: - Macro Summary Card
struct MacroSummaryCard: View {
    let title: String
    let value: Int
    let unit: String
    let color: Color
    let icon: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)

            Text("\(value)")
                .font(.system(.title3, design: .rounded))
                .fontWeight(.bold)

            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(unit)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
}
