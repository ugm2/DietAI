import SwiftUI

// MARK: - Plan Review Step
struct PlanReviewStep: View {
    let config: PlanConfiguration
    let plannedDays: [PlannedDay]
    let onSave: () -> Void
    let onBack: () -> Void

    @State private var expandedDay: UUID?

    private var totalMeals: Int {
        plannedDays.reduce(0) { $0 + $1.meals.count }
    }

    private var averageCalories: Int {
        let total = plannedDays.reduce(0) { $0 + $1.totalCalories }
        return plannedDays.isEmpty ? 0 : total / plannedDays.count
    }

    private var averageProtein: Int {
        let total = plannedDays.reduce(0) { $0 + $1.totalProtein }
        return plannedDays.isEmpty ? 0 : total / plannedDays.count
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    // Success header
                    successHeader

                    // Summary card
                    summaryCard

                    // Daily breakdown
                    dailyBreakdown
                }
                .padding()
            }

            // Save button
            saveButton
        }
    }

    // MARK: - Success Header
    private var successHeader: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 80, height: 80)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.green)
            }

            Text("Your Plan is Ready!")
                .font(.title2)
                .fontWeight(.bold)

            Text("Review your \(config.daysCount)-day meal plan below")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 20)
    }

    // MARK: - Summary Card
    private var summaryCard: some View {
        VStack(spacing: 16) {
            HStack {
                Text(config.name)
                    .font(.headline)

                Spacer()

                Label(config.goal.rawValue, systemImage: "flag.fill")
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .foregroundStyle(.blue)
                    .cornerRadius(12)
            }

            Divider()

            // Stats grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                StatBox(
                    value: "\(config.daysCount)",
                    label: "Days",
                    icon: "calendar",
                    color: .blue
                )

                StatBox(
                    value: "\(totalMeals)",
                    label: "Meals",
                    icon: "fork.knife",
                    color: .orange
                )

                StatBox(
                    value: "\(averageCalories)",
                    label: "Avg kcal",
                    icon: "flame.fill",
                    color: .red
                )
            }

            // Calorie target comparison
            HStack {
                Text("Daily Target")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(config.dailyCalories) kcal")
                    .font(.subheadline)
                    .fontWeight(.medium)

                // Indicator
                if abs(averageCalories - config.dailyCalories) < 100 {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else if averageCalories > config.dailyCalories {
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundStyle(.orange)
                } else {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(.orange)
                }
            }
            .padding()
            .background(Color(uiColor: .tertiarySystemGroupedBackground))
            .cornerRadius(10)
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(16)
    }

    // MARK: - Daily Breakdown
    private var dailyBreakdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Daily Breakdown")
                .font(.headline)

            ForEach(plannedDays) { day in
                DayReviewCard(
                    day: day,
                    targetCalories: config.dailyCalories,
                    isExpanded: expandedDay == day.id
                ) {
                    withAnimation {
                        expandedDay = expandedDay == day.id ? nil : day.id
                    }
                }
            }
        }
    }

    // MARK: - Save Button
    private var saveButton: some View {
        VStack(spacing: 12) {
            Button(action: onSave) {
                HStack {
                    Image(systemName: "square.and.arrow.down")
                    Text("Save Plan")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundStyle(.white)
                .cornerRadius(14)
            }

            Button(action: onBack) {
                Text("Go Back & Edit")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(uiColor: .systemBackground))
    }
}

// MARK: - Stat Box
struct StatBox: View {
    let value: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)

            Text(value)
                .font(.title3)
                .fontWeight(.bold)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Day Review Card
struct DayReviewCard: View {
    let day: PlannedDay
    let targetCalories: Int
    let isExpanded: Bool
    let onTap: () -> Void

    private var calorieDeviation: Int {
        day.totalCalories - targetCalories
    }

    private var deviationColor: Color {
        if abs(calorieDeviation) < 100 { return .green }
        if abs(calorieDeviation) < 200 { return .orange }
        return .red
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header (always visible)
            Button(action: onTap) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(day.dayName)
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Text("\(day.meals.count) meals")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text("\(day.totalCalories) kcal")
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        HStack(spacing: 4) {
                            if calorieDeviation > 0 {
                                Image(systemName: "arrow.up")
                                    .font(.caption2)
                                Text("+\(calorieDeviation)")
                                    .font(.caption)
                            } else if calorieDeviation < 0 {
                                Image(systemName: "arrow.down")
                                    .font(.caption2)
                                Text("\(calorieDeviation)")
                                    .font(.caption)
                            } else {
                                Image(systemName: "checkmark")
                                    .font(.caption2)
                                Text("On target")
                                    .font(.caption)
                            }
                        }
                        .foregroundStyle(deviationColor)
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 8)
                }
                .padding()
            }
            .foregroundStyle(.primary)

            // Expanded content
            if isExpanded {
                Divider()

                VStack(spacing: 8) {
                    ForEach(day.meals) { meal in
                        HStack {
                            Image(systemName: mealIcon(meal.type))
                                .font(.caption)
                                .foregroundStyle(mealColor(meal.type))
                                .frame(width: 24)

                            Text(meal.name)
                                .font(.subheadline)

                            Spacer()

                            Text("\(meal.calories) kcal")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 6)
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    private func mealIcon(_ type: MealType) -> String {
        type.icon
    }

    private func mealColor(_ type: MealType) -> Color {
        type.color
    }
}
