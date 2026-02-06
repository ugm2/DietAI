import SwiftUI
import Charts

// MARK: - Calorie Trend Chart
struct CalorieTrendChart: View {
    let data: [DailyCalorieData]
    let target: Int

    var body: some View {
        Chart {
            // Target line
            RuleMark(y: .value("Target", target))
                .foregroundStyle(.orange.opacity(0.6))
                .lineStyle(StrokeStyle(dash: [5, 5]))
                .annotation(position: .top, alignment: .trailing) {
                    Text("Target")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }

            // Calorie area and line
            ForEach(data) { point in
                AreaMark(
                    x: .value("Date", point.date, unit: .day),
                    y: .value("Calories", point.calories)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue.opacity(0.4), .blue.opacity(0.1)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("Date", point.date, unit: .day),
                    y: .value("Calories", point.calories)
                )
                .foregroundStyle(.blue)
                .lineStyle(StrokeStyle(lineWidth: 2))

                PointMark(
                    x: .value("Date", point.date, unit: .day),
                    y: .value("Calories", point.calories)
                )
                .foregroundStyle(.blue)
                .symbolSize(30)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisValueLabel(format: .dateTime.weekday(.abbreviated))
            }
        }
    }
}

// MARK: - Macro Distribution Chart
struct MacroDistributionChart: View {
    let protein: Int
    let carbs: Int
    let fat: Int

    private var total: Double {
        Double(protein + carbs + fat)
    }

    private var macroData: [(name: String, value: Double, color: Color)] {
        guard total > 0 else { return [] }
        return [
            ("Protein", Double(protein), .red),
            ("Carbs", Double(carbs), .blue),
            ("Fat", Double(fat), .yellow)
        ]
    }

    var body: some View {
        if total > 0 {
            HStack(spacing: 24) {
                Chart(macroData, id: \.name) { macro in
                    SectorMark(
                        angle: .value("Grams", macro.value),
                        innerRadius: .ratio(0.6),
                        angularInset: 2
                    )
                    .foregroundStyle(macro.color)
                    .cornerRadius(4)
                }
                .frame(width: 120, height: 120)

                VStack(alignment: .leading, spacing: 10) {
                    MacroLegendRow(name: "Protein", value: protein, total: total, color: .red)
                    MacroLegendRow(name: "Carbs", value: carbs, total: total, color: .blue)
                    MacroLegendRow(name: "Fat", value: fat, total: total, color: .yellow)
                }
            }
        } else {
            ContentUnavailableView(
                "No Data",
                systemImage: "chart.pie",
                description: Text("Log meals to see macro distribution")
            )
        }
    }
}

struct MacroLegendRow: View {
    let name: String
    let value: Int
    let total: Double
    let color: Color

    private var percentage: Int {
        guard total > 0 else { return 0 }
        return Int((Double(value) / total) * 100)
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)

            Text(name)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Text("\(value)g")
                .font(.subheadline)
                .fontWeight(.medium)

            Text("(\(percentage)%)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Meal Type Breakdown Chart
struct MealTypeBreakdownChart: View {
    let data: [MealTypeCalorieData]

    var body: some View {
        if !data.isEmpty {
            Chart(data) { item in
                BarMark(
                    x: .value("Calories", item.totalCalories),
                    y: .value("Type", item.displayName)
                )
                .foregroundStyle(colorFor(item.mealType))
                .cornerRadius(4)
                .annotation(position: .trailing) {
                    Text("\(item.totalCalories)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .chartXAxis {
                AxisMarks(position: .bottom)
            }
        } else {
            ContentUnavailableView(
                "No Data",
                systemImage: "chart.bar",
                description: Text("Log meals to see breakdown")
            )
        }
    }

    private func colorFor(_ type: MealType) -> Color {
        type.color
    }
}

// MARK: - Workout Frequency Chart
struct WorkoutFrequencyChart: View {
    let data: [DayWorkoutData]

    var body: some View {
        Chart(data) { day in
            BarMark(
                x: .value("Day", day.dayName),
                y: .value("Count", day.workoutCount)
            )
            .foregroundStyle(day.isToday ? .blue : .blue.opacity(0.6))
            .cornerRadius(4)
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 4))
        }
    }
}

// MARK: - Workout Type Distribution Chart
struct WorkoutTypeDistributionChart: View {
    let data: [WorkoutTypeData]

    var body: some View {
        if !data.isEmpty {
            HStack(spacing: 20) {
                Chart(data) { item in
                    SectorMark(
                        angle: .value("Count", item.count),
                        innerRadius: .ratio(0.5),
                        angularInset: 2
                    )
                    .foregroundStyle(item.color)
                    .cornerRadius(4)
                }
                .frame(width: 120, height: 120)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(data.prefix(4)) { item in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(item.color)
                                .frame(width: 10, height: 10)

                            Text(item.displayName)
                                .font(.caption)
                                .lineLimit(1)

                            Spacer()

                            Text("\(item.count)")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                    }
                }
            }
        } else {
            ContentUnavailableView(
                "No Workouts",
                systemImage: "figure.run",
                description: Text("Complete workouts to see distribution")
            )
        }
    }
}

// MARK: - Calories Burned Trend Chart
struct CaloriesBurnedTrendChart: View {
    let data: [DailyActiveCaloriesData]

    var body: some View {
        Chart(data) { point in
            AreaMark(
                x: .value("Date", point.date, unit: .day),
                y: .value("Calories", point.calories)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [.orange.opacity(0.4), .orange.opacity(0.1)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            LineMark(
                x: .value("Date", point.date, unit: .day),
                y: .value("Calories", point.calories)
            )
            .foregroundStyle(.orange)
            .lineStyle(StrokeStyle(lineWidth: 2))

            PointMark(
                x: .value("Date", point.date, unit: .day),
                y: .value("Calories", point.calories)
            )
            .foregroundStyle(.orange)
            .symbolSize(30)
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisValueLabel(format: .dateTime.weekday(.abbreviated))
            }
        }
    }
}

// MARK: - Steps Trend Chart
struct StepsTrendChart: View {
    let data: [DailyStepData]
    var goalSteps: Int = 10000

    var body: some View {
        Chart {
            // Goal line
            RuleMark(y: .value("Goal", goalSteps))
                .foregroundStyle(.green.opacity(0.5))
                .lineStyle(StrokeStyle(dash: [5, 5]))
                .annotation(position: .top, alignment: .trailing) {
                    Text("Goal")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }

            ForEach(data) { point in
                AreaMark(
                    x: .value("Date", point.date, unit: .day),
                    y: .value("Steps", point.steps)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [.green.opacity(0.4), .green.opacity(0.1)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("Date", point.date, unit: .day),
                    y: .value("Steps", point.steps)
                )
                .foregroundStyle(.green)
                .lineStyle(StrokeStyle(lineWidth: 2))

                PointMark(
                    x: .value("Date", point.date, unit: .day),
                    y: .value("Steps", point.steps)
                )
                .foregroundStyle(.green)
                .symbolSize(30)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisValueLabel(format: .dateTime.weekday(.abbreviated))
            }
        }
    }
}

// MARK: - Weight Trend Chart
struct WeightTrendChart: View {
    let data: [WeightDataPoint]
    let goalWeight: Double?

    var body: some View {
        if !data.isEmpty {
            Chart {
                // Goal weight line
                if let goal = goalWeight {
                    RuleMark(y: .value("Goal", goal))
                        .foregroundStyle(.green.opacity(0.5))
                        .lineStyle(StrokeStyle(dash: [5, 5]))
                        .annotation(position: .top, alignment: .trailing) {
                            Text("Goal")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        }
                }

                ForEach(data) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Weight", point.weight)
                    )
                    .foregroundStyle(.blue)
                    .lineStyle(StrokeStyle(lineWidth: 2))

                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("Weight", point.weight)
                    )
                    .foregroundStyle(.blue)
                    .symbolSize(40)
                }
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    if let weight = value.as(Double.self) {
                        AxisValueLabel {
                            Text(String(format: "%.0f", weight))
                        }
                    }
                    AxisGridLine()
                }
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
        } else {
            ContentUnavailableView(
                "No Weight Data",
                systemImage: "scalemass",
                description: Text("Log weight in Health app to see trends")
            )
        }
    }
}

// MARK: - Sleep Mini Chart
struct SleepMiniChart: View {
    let data: [DailySleepHours]

    var body: some View {
        Chart(data) { day in
            BarMark(
                x: .value("Date", day.date, unit: .day),
                y: .value("Hours", day.hours)
            )
            .foregroundStyle(.indigo.opacity(0.7))
            .cornerRadius(2)
        }
        .chartYAxis(.hidden)
        .chartXAxis(.hidden)
    }
}
