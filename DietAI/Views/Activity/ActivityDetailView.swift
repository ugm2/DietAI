import SwiftUI

struct ActivityDetailView: View {
    let activity: EnhancedActivitySummary
    let smartTarget: SmartCalorieTarget?

    var body: some View {
        List {
            // Today's Summary Section
            Section("Today's Activity") {
                StatsRow(label: "Active Calories", value: "\(activity.activeCalories) kcal", icon: "flame.fill", color: .orange)
                StatsRow(label: "Steps", value: "\(activity.steps)", icon: "figure.walk", color: .green)
                if let target = smartTarget, target.workoutBonus > 0 {
                    StatsRow(label: "Calorie Bonus", value: "+\(target.workoutBonus) kcal", icon: "plus.circle.fill", color: .blue)
                }
            }

            // Workouts Section
            if !activity.workouts.isEmpty {
                Section("Today's Workouts") {
                    ForEach(activity.workouts) { workout in
                        WorkoutDetailRow(workout: workout)
                    }
                }

                // Calorie Adjustment Explanation
                Section("How Activity Affects Your Targets") {
                    CalorieAdjustmentExplanation(activity: activity)
                }
            }

            // Weekly Trend Section
            Section("This Week") {
                WeeklyTrendCard(trend: activity.weeklyTrend)
            }

            // Recovery Recommendations (if strength training recently)
            if activity.hasActiveRecoveryWindow {
                Section("Recovery Nutrition") {
                    RecoveryRecommendationsCard()
                }
            }

            // Nutrition Tips based on activity
            if let dominant = activity.dominantWorkoutCategory ?? activity.weeklyTrend.dominantCategory {
                Section("Nutrition Tips for \(dominant.rawValue)") {
                    NutritionTipsCard(category: dominant)
                }
            }
        }
        .navigationTitle("Activity & Nutrition")
    }
}

// MARK: - Stats Row
struct StatsRow: View {
    let label: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        HStack {
            Label(label, systemImage: icon)
                .foregroundStyle(color)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Workout Detail Row
struct WorkoutDetailRow: View {
    let workout: WorkoutSummary

    var body: some View {
        HStack {
            Image(systemName: workout.category.icon)
                .font(.title2)
                .foregroundStyle(categoryColor)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(workout.category.rawValue)
                    .font(.headline)

                HStack(spacing: 12) {
                    Label("\(Int(workout.durationMinutes)) min", systemImage: "clock")
                    Label("\(workout.calories) kcal", systemImage: "flame")
                    Label(workout.intensity.rawValue, systemImage: "gauge.medium")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            // Recovery status indicator
            if workout.isInRecoveryWindow {
                VStack {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(.purple)
                    Text("Recovery")
                        .font(.caption2)
                        .foregroundStyle(.purple)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var categoryColor: Color {
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

// MARK: - Calorie Adjustment Explanation
struct CalorieAdjustmentExplanation: View {
    let activity: EnhancedActivitySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(activity.workouts) { workout in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: workout.category.icon)
                                .font(.caption)
                            Text(workout.category.rawValue)
                        }
                        .font(.subheadline)

                        Spacer()

                        Text("+\(workout.calorieBonus) kcal")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.blue)
                    }

                    Text("\(Int(workout.category.calorieRecoveryMultiplier * 100))% of \(workout.calories) kcal \u{00D7} \(String(format: "%.1f", workout.intensity.intensityMultiplier))x intensity")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if activity.workouts.count > 1 {
                Divider()

                HStack {
                    Text("Total Workout Bonus")
                        .font(.headline)
                    Spacer()
                    Text("+\(activity.totalCalorieBonus) kcal")
                        .font(.headline)
                        .foregroundStyle(.blue)
                }
            }
        }
    }
}

// MARK: - Weekly Trend Card
struct WeeklyTrendCard: View {
    let trend: WeeklyActivityTrend

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                TrendStat(label: "Workout Days", value: "\(trend.workoutDays)", icon: "calendar")
                Spacer()
                TrendStat(label: "Total Minutes", value: "\(trend.totalWorkoutMinutes)", icon: "timer")
                Spacer()
                TrendStat(label: "Strength Days", value: "\(trend.strengthDays)", icon: "dumbbell.fill")
            }

            Divider()

            HStack {
                Text("Activity Level:")
                    .font(.subheadline)
                Spacer()
                Text(trend.activityLevel.rawValue)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(levelColor)
            }

            if let dominant = trend.dominantCategory {
                HStack {
                    Text("Training Focus:")
                        .font(.subheadline)
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: dominant.icon)
                        Text(dominant.rawValue)
                    }
                    .font(.subheadline)
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private var levelColor: Color {
        switch trend.activityLevel {
        case .sedentary: return .gray
        case .lightlyActive: return .blue
        case .moderatelyActive: return .green
        case .veryActive: return .orange
        case .extremelyActive: return .red
        }
    }
}

// MARK: - Trend Stat
struct TrendStat: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.blue)
            Text(value)
                .font(.headline)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Recovery Recommendations Card
struct RecoveryRecommendationsCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "figure.strengthtraining.traditional")
                    .foregroundStyle(.purple)
                Text("Post-Strength Training")
                    .font(.headline)
            }

            VStack(alignment: .leading, spacing: 8) {
                RecommendationRow(
                    icon: "fork.knife",
                    title: "Protein Timing",
                    detail: "Aim for 25-30g protein within 2 hours"
                )

                RecommendationRow(
                    icon: "leaf.fill",
                    title: "Leucine-Rich Foods",
                    detail: "Eggs, chicken, fish, Greek yogurt"
                )

                RecommendationRow(
                    icon: "carrot.fill",
                    title: "Include Carbs",
                    detail: "Helps shuttle protein to muscles"
                )
            }
        }
    }
}

// MARK: - Recommendation Row
struct RecommendationRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.blue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Nutrition Tips Card
struct NutritionTipsCard: View {
    let category: WorkoutCategory

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(tipsForCategory, id: \.title) { tip in
                RecommendationRow(icon: tip.icon, title: tip.title, detail: tip.detail)
            }
        }
    }

    private var tipsForCategory: [(icon: String, title: String, detail: String)] {
        switch category {
        case .strength:
            return [
                ("fork.knife", "High Protein", "Target 1.6-2.2g protein per kg bodyweight"),
                ("carrot.fill", "Post-Workout Carbs", "40-60g carbs with protein after training"),
                ("drop.fill", "Stay Hydrated", "Aim for 3+ liters of water daily")
            ]
        case .cardio:
            return [
                ("leaf.fill", "Carb Focus", "Complex carbs before, simple carbs during long sessions"),
                ("bolt.fill", "Electrolytes", "Replace sodium and potassium during sweaty workouts"),
                ("fork.knife", "Lean Protein", "Moderate protein for recovery, not as high as strength")
            ]
        case .hiit:
            return [
                ("flame.fill", "Pre-Workout Fuel", "Light carbs 1-2 hours before for energy"),
                ("fork.knife", "Post-Workout Protein", "20-25g protein within 1 hour"),
                ("drop.fill", "Rehydrate", "HIIT causes significant fluid loss")
            ]
        case .endurance:
            return [
                ("leaf.fill", "Carb Loading", "Increase carbs 1-2 days before long events"),
                ("bolt.fill", "During Exercise", "30-60g carbs per hour for sessions over 90 min"),
                ("drop.fill", "Sodium", "Add electrolytes for sessions over 1 hour")
            ]
        case .yoga:
            return [
                ("leaf.fill", "Light Meals", "Avoid heavy foods 2-3 hours before practice"),
                ("drop.fill", "Hydration", "Stay hydrated but don't overdrink before class"),
                ("carrot.fill", "Anti-Inflammatory", "Focus on whole foods, fruits, vegetables")
            ]
        default:
            return [
                ("fork.knife", "Balanced Nutrition", "Aim for balanced macros across all meals"),
                ("drop.fill", "Hydration", "Drink water consistently throughout the day"),
                ("leaf.fill", "Whole Foods", "Prioritize whole, unprocessed foods")
            ]
        }
    }
}
