import SwiftUI

struct WorkoutAnalyticsSection: View {
    let viewModel: WorkoutAnalyticsViewModel
    let timeRange: AnalyticsTimeRange

    var body: some View {
        VStack(spacing: 16) {
            // Quick Stats
            HStack(spacing: 12) {
                StatHighlightCard(
                    title: "Workouts",
                    value: "\(viewModel.totalWorkouts)",
                    subtitle: timeRange == .day ? "today" : "this \(timeRange.rawValue.lowercased())",
                    icon: "figure.run",
                    color: .pink
                )

                StatHighlightCard(
                    title: "Calories",
                    value: "\(viewModel.totalCaloriesBurned)",
                    subtitle: "burned",
                    icon: "flame.fill",
                    color: .orange
                )
            }

            // Steps Summary
            HStack(spacing: 12) {
                StatHighlightCard(
                    title: "Steps",
                    value: formatSteps(viewModel.totalSteps),
                    subtitle: timeRange == .day ? "today" : "total",
                    icon: "figure.walk",
                    color: .green
                )

                if let mostActiveDay = viewModel.mostActiveDay {
                    StatHighlightCard(
                        title: "Most Active",
                        value: mostActiveDay,
                        subtitle: "day",
                        icon: "star.fill",
                        color: .yellow
                    )
                } else {
                    StatHighlightCard(
                        title: "Avg Duration",
                        value: "\(viewModel.averageWorkoutDuration)",
                        subtitle: "minutes",
                        icon: "timer",
                        color: .cyan
                    )
                }
            }

            // Weekly Frequency Chart
            if timeRange != .day {
                AnalyticsCard(title: "Workout Frequency", icon: "calendar") {
                    if viewModel.workoutsByDay.isEmpty || viewModel.workoutsByDay.allSatisfy({ $0.workoutCount == 0 }) {
                        ContentUnavailableView(
                            "No Workouts",
                            systemImage: "figure.run",
                            description: Text("Complete workouts to see your frequency")
                        )
                        .frame(height: 140)
                    } else {
                        WorkoutFrequencyChart(data: viewModel.workoutsByDay)
                            .frame(height: 160)
                    }
                }
            }

            // Workout Type Distribution
            AnalyticsCard(title: "Workout Types", icon: "figure.mixed.cardio") {
                WorkoutTypeDistributionChart(data: viewModel.workoutsByType)
                    .frame(height: 160)
            }

            // Active Calories Trend
            AnalyticsCard(title: "Active Calories Trend", icon: "flame") {
                if viewModel.dailyActiveCalories.isEmpty || viewModel.dailyActiveCalories.allSatisfy({ $0.calories == 0 }) {
                    ContentUnavailableView(
                        "No Activity Data",
                        systemImage: "flame",
                        description: Text("Activity data will appear here")
                    )
                    .frame(height: 160)
                } else {
                    CaloriesBurnedTrendChart(data: viewModel.dailyActiveCalories)
                        .frame(height: 180)
                }
            }

            // Steps Trend
            AnalyticsCard(title: "Steps", icon: "figure.walk") {
                if viewModel.dailySteps.isEmpty || viewModel.dailySteps.allSatisfy({ $0.steps == 0 }) {
                    ContentUnavailableView(
                        "No Step Data",
                        systemImage: "figure.walk",
                        description: Text("Step data will appear here")
                    )
                    .frame(height: 140)
                } else {
                    StepsTrendChart(data: viewModel.dailySteps)
                        .frame(height: 160)
                }
            }

            // Insights
            if viewModel.averageWorkoutDuration > 0 || viewModel.mostActiveDay != nil {
                AnalyticsCard(title: "Insights", icon: "lightbulb") {
                    BestWorkoutDaysCard(
                        mostActiveDay: viewModel.mostActiveDay ?? "N/A",
                        avgDuration: viewModel.averageWorkoutDuration
                    )
                }
            }
        }
    }

    private func formatSteps(_ steps: Int) -> String {
        if steps >= 10000 {
            return String(format: "%.1fk", Double(steps) / 1000)
        }
        return "\(steps)"
    }
}
