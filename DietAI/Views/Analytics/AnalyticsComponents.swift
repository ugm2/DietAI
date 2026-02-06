import SwiftUI

// MARK: - Analytics Card Container
struct AnalyticsCard<Content: View>: View {
    let title: String
    var icon: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if let icon = icon {
                    Image(systemName: icon)
                        .foregroundStyle(.secondary)
                }
                Text(title)
                    .font(.headline)
                Spacer()
            }

            content
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(16)
    }
}

// MARK: - Stat Highlight Card
struct StatHighlightCard: View {
    let title: String
    let value: String
    var subtitle: String? = nil
    let icon: String
    let color: Color
    var trend: TrendDirection? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.title3)

                Spacer()

                if let trend = trend {
                    HStack(spacing: 2) {
                        Image(systemName: trend.icon)
                        Text(trend.percentageText)
                    }
                    .font(.caption)
                    .foregroundStyle(trend.weightColor)
                }
            }

            Text(value)
                .font(.title)
                .fontWeight(.bold)

            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(title)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
}

// MARK: - Time Range Selector
struct AnalyticsTimeRangeSelector: View {
    @Binding var selectedRange: AnalyticsTimeRange

    var body: some View {
        HStack(spacing: 8) {
            ForEach(AnalyticsTimeRange.allCases, id: \.self) { range in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedRange = range
                    }
                } label: {
                    Text(range.rawValue)
                        .font(.subheadline)
                        .fontWeight(selectedRange == range ? .semibold : .regular)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            selectedRange == range
                                ? Color.blue
                                : Color(uiColor: .secondarySystemGroupedBackground)
                        )
                        .foregroundStyle(selectedRange == range ? .white : .primary)
                        .cornerRadius(20)
                }
            }
        }
    }
}

// MARK: - Section Selector
struct SectionSelector: View {
    @Binding var selectedSection: AnalyticsSection

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AnalyticsSection.allCases, id: \.self) { section in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedSection = section
                    }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: section.icon)
                            .font(.title3)

                        Text(section.rawValue)
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        selectedSection == section
                            ? section.color.opacity(0.15)
                            : Color.clear
                    )
                    .foregroundStyle(
                        selectedSection == section
                            ? section.color
                            : .secondary
                    )
                }
            }
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
}

// MARK: - Trend Indicator
struct TrendIndicator: View {
    let trend: TrendDirection
    var useWeightColor: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: trend.icon)
            Text(trend.percentageText)
        }
        .font(.caption)
        .foregroundStyle(useWeightColor ? trend.weightColor : trend.color)
    }
}

// MARK: - Frequent Meals Card
struct FrequentMealsCard: View {
    let meals: [FrequentMeal]

    var body: some View {
        VStack(spacing: 12) {
            ForEach(meals) { meal in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(meal.name)
                            .font(.subheadline)
                            .lineLimit(1)

                        Text("\(meal.count) times")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text("\(meal.avgCalories) kcal")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Sleep Quality Indicator
struct SleepQualityIndicator: View {
    let quality: SleepQuality

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: quality.icon)
            Text(quality.rawValue)
        }
        .font(.caption)
        .fontWeight(.medium)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(quality.color.opacity(0.15))
        .foregroundStyle(quality.color)
        .cornerRadius(8)
    }
}

// MARK: - BMI Category Badge
struct BMICategoryBadge: View {
    let bmi: Double

    private var category: BMICategory {
        BMICategory.from(bmi: bmi)
    }

    var body: some View {
        Text(category.rawValue)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(category.color.opacity(0.15))
            .foregroundStyle(category.color)
            .cornerRadius(8)
    }
}

// MARK: - Permission Needed View
struct PermissionNeededView: View {
    let icon: String
    let message: String
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.secondary)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let action = action {
                Button("Enable", action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

// MARK: - Health Permission Request Card
struct HealthPermissionRequestCard: View {
    let missingPermissions: [HealthPermission]
    let onRequestPermissions: () -> Void

    var body: some View {
        AnalyticsCard(title: "Enable More Health Data", icon: "heart.fill") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Get more insights by enabling additional health tracking:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ForEach(missingPermissions, id: \.rawValue) { permission in
                    HStack(spacing: 10) {
                        Image(systemName: permission.icon)
                            .foregroundStyle(.red)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(permission.rawValue)
                                .font(.subheadline)
                                .fontWeight(.medium)

                            Text(permission.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Button(action: onRequestPermissions) {
                    Text("Open Health Settings")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .padding(.top, 8)
            }
        }
    }
}

// MARK: - Best Workout Days Card
struct BestWorkoutDaysCard: View {
    let mostActiveDay: String
    let avgDuration: Int

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Most Active Day")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(mostActiveDay)
                        .font(.title2)
                        .fontWeight(.semibold)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("Avg Duration")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("\(avgDuration) min")
                        .font(.title2)
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Loading Skeleton
struct ChartLoadingView: View {
    var body: some View {
        VStack {
            ProgressView()
                .scaleEffect(1.2)

            Text("Loading data...")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}
