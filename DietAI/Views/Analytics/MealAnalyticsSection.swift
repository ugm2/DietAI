import SwiftUI

struct MealAnalyticsSection: View {
    let viewModel: MealAnalyticsViewModel
    let timeRange: AnalyticsTimeRange

    var body: some View {
        VStack(spacing: 16) {
            // Quick Stats Row
            HStack(spacing: 12) {
                StatHighlightCard(
                    title: "Avg Calories",
                    value: "\(viewModel.averageCalories)",
                    subtitle: "per day",
                    icon: "flame.fill",
                    color: .orange
                )

                StatHighlightCard(
                    title: "Streak",
                    value: "\(viewModel.loggingStreak)",
                    subtitle: "days",
                    icon: "calendar.badge.checkmark",
                    color: .green
                )
            }

            // Calorie Trend Chart
            AnalyticsCard(title: "Calorie Trend", icon: "chart.line.uptrend.xyaxis") {
                if viewModel.dailyCalories.isEmpty || viewModel.dailyCalories.allSatisfy({ $0.calories == 0 }) {
                    ContentUnavailableView(
                        "No Data",
                        systemImage: "chart.line.uptrend.xyaxis",
                        description: Text("Log meals to see your calorie trend")
                    )
                    .frame(height: 180)
                } else {
                    CalorieTrendChart(
                        data: viewModel.dailyCalories,
                        target: viewModel.calorieTarget
                    )
                    .frame(height: 200)
                }
            }

            // Macro Distribution
            AnalyticsCard(title: "Macro Distribution", icon: "chart.pie") {
                MacroDistributionChart(
                    protein: viewModel.totalProtein,
                    carbs: viewModel.totalCarbs,
                    fat: viewModel.totalFat
                )
                .frame(height: 140)
            }

            // Meal Type Breakdown
            AnalyticsCard(title: "Calories by Meal Type", icon: "fork.knife") {
                MealTypeBreakdownChart(data: viewModel.caloriesByMealType)
                    .frame(height: max(CGFloat(viewModel.caloriesByMealType.count * 40), 120))
            }

            // Most Frequent Meals
            if !viewModel.frequentMeals.isEmpty {
                AnalyticsCard(title: "Most Logged Meals", icon: "star.fill") {
                    FrequentMealsCard(meals: viewModel.frequentMeals)
                }
            }

            // Summary Stats
            AnalyticsCard(title: "Period Summary", icon: "sum") {
                VStack(spacing: 12) {
                    AnalyticsSummaryRow(label: "Total Calories", value: "\(viewModel.totalCalories) kcal")
                    AnalyticsSummaryRow(label: "Total Protein", value: "\(viewModel.totalProtein)g")
                    AnalyticsSummaryRow(label: "Total Carbs", value: "\(viewModel.totalCarbs)g")
                    AnalyticsSummaryRow(label: "Total Fat", value: "\(viewModel.totalFat)g")
                }
            }
        }
    }
}

struct AnalyticsSummaryRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
        .font(.subheadline)
    }
}
