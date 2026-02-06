import SwiftUI

struct HealthAnalyticsSection: View {
    let viewModel: HealthAnalyticsViewModel
    let timeRange: AnalyticsTimeRange
    let userProfile: UserProfile?

    var body: some View {
        VStack(spacing: 16) {
            // Weight & BMI Cards
            HStack(spacing: 12) {
                if let weight = viewModel.currentWeight {
                    StatHighlightCard(
                        title: "Weight",
                        value: String(format: "%.1f", weight),
                        subtitle: "kg",
                        icon: "scalemass.fill",
                        color: .blue,
                        trend: viewModel.weightTrend
                    )
                } else {
                    StatHighlightCard(
                        title: "Weight",
                        value: "--",
                        subtitle: "Not recorded",
                        icon: "scalemass.fill",
                        color: .blue
                    )
                }

                if let bmi = viewModel.currentBMI {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "figure.stand")
                                .foregroundStyle(.purple)
                                .font(.title3)
                            Spacer()
                            // Don't show misleading BMI category if body fat indicates athletic build
                            if let bodyFat = viewModel.bodyFatPercentage, bodyFat < 20 {
                                Text("Athletic")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color.blue.opacity(0.15))
                                    .foregroundStyle(.blue)
                                    .cornerRadius(8)
                            } else {
                                BMICategoryBadge(bmi: bmi)
                            }
                        }

                        Text(String(format: "%.1f", bmi))
                            .font(.title)
                            .fontWeight(.bold)

                        Text("BMI")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .cornerRadius(12)
                } else {
                    StatHighlightCard(
                        title: "BMI",
                        value: "--",
                        subtitle: "Need weight & height",
                        icon: "figure.stand",
                        color: .purple
                    )
                }
            }

            // Weight Trend Chart
            AnalyticsCard(title: "Weight Trend", icon: "chart.line.uptrend.xyaxis") {
                WeightTrendChart(
                    data: viewModel.weightHistory,
                    goalWeight: viewModel.goalWeight
                )
                .frame(height: 200)
            }

            // Sleep Analytics
            AnalyticsCard(title: "Sleep", icon: "bed.double.fill") {
                if let sleepData = viewModel.sleepData {
                    VStack(spacing: 16) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(alignment: .firstTextBaseline, spacing: 2) {
                                    Text(String(format: "%.1f", sleepData.averageDuration))
                                        .font(.title)
                                        .fontWeight(.bold)
                                    Text("hrs")
                                        .font(.title3)
                                        .foregroundStyle(.secondary)
                                }

                                Text("avg per night")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            SleepQualityIndicator(quality: sleepData.quality)
                        }

                        if !sleepData.dailyHours.isEmpty {
                            SleepMiniChart(data: sleepData.dailyHours)
                                .frame(height: 60)
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "No Sleep Data",
                        systemImage: "bed.double",
                        description: Text("Sleep data from Apple Watch or iPhone will appear here")
                    )
                    .frame(height: 100)
                }
            }

            // Heart Rate Card
            AnalyticsCard(title: "Heart Health", icon: "heart.fill") {
                if viewModel.restingHeartRate != nil || viewModel.heartRateVariability != nil {
                    HStack(spacing: 24) {
                        if let hr = viewModel.restingHeartRate {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text("\(hr)")
                                        .font(.title)
                                        .fontWeight(.bold)
                                    Text("bpm")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text("Resting HR")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                HeartRateIndicator(bpm: hr)
                            }
                        }

                        if let hrv = viewModel.heartRateVariability {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text(String(format: "%.0f", hrv))
                                        .font(.title)
                                        .fontWeight(.bold)
                                    Text("ms")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text("HRV")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                HRVIndicator(hrv: hrv)
                            }
                        }

                        Spacer()
                    }
                } else {
                    ContentUnavailableView(
                        "No Heart Data",
                        systemImage: "heart",
                        description: Text("Heart rate data from Apple Watch will appear here")
                    )
                    .frame(height: 80)
                }
            }

            // Body Composition
            if let bodyFat = viewModel.bodyFatPercentage {
                AnalyticsCard(title: "Body Composition", icon: "figure.arms.open") {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(String(format: "%.1f", bodyFat))
                                    .font(.title)
                                    .fontWeight(.bold)
                                Text("%")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                            }
                            Text("Body Fat")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        BodyFatIndicator(percentage: bodyFat)
                    }
                }
            }

            // Goal Progress
            if let goalWeight = viewModel.goalWeight, let currentWeight = viewModel.currentWeight {
                AnalyticsCard(title: "Goal Progress", icon: "target") {
                    GoalProgressView(
                        currentWeight: currentWeight,
                        goalWeight: goalWeight,
                        startWeight: userProfile?.weight ?? currentWeight
                    )
                }
            }
        }
    }
}

// MARK: - Heart Rate Indicator
struct HeartRateIndicator: View {
    let bpm: Int

    private var status: (text: String, color: Color) {
        switch bpm {
        case ..<60: return ("Low", .blue)
        case 60...100: return ("Normal", .green)
        default: return ("Elevated", .orange)
        }
    }

    var body: some View {
        Text(status.text)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(status.color.opacity(0.15))
            .foregroundStyle(status.color)
            .cornerRadius(4)
    }
}

// MARK: - HRV Indicator
struct HRVIndicator: View {
    let hrv: Double

    private var status: (text: String, color: Color) {
        switch hrv {
        case ..<20: return ("Low", .red)
        case 20..<50: return ("Moderate", .orange)
        case 50..<100: return ("Good", .green)
        default: return ("Excellent", .blue)
        }
    }

    var body: some View {
        Text(status.text)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(status.color.opacity(0.15))
            .foregroundStyle(status.color)
            .cornerRadius(4)
    }
}

// MARK: - Body Fat Indicator
struct BodyFatIndicator: View {
    let percentage: Double

    private var status: (text: String, color: Color) {
        // General ranges (varies by gender/age)
        switch percentage {
        case ..<15: return ("Athletic", .blue)
        case 15..<25: return ("Fit", .green)
        case 25..<32: return ("Average", .orange)
        default: return ("Above Average", .red)
        }
    }

    var body: some View {
        Text(status.text)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(status.color.opacity(0.15))
            .foregroundStyle(status.color)
            .cornerRadius(8)
    }
}

// MARK: - Goal Progress View
struct GoalProgressView: View {
    let currentWeight: Double
    let goalWeight: Double
    let startWeight: Double

    private var progress: Double {
        let totalChange = abs(startWeight - goalWeight)
        guard totalChange > 0 else { return 0 }
        let currentChange = abs(startWeight - currentWeight)
        return min(currentChange / totalChange, 1.0)
    }

    private var remaining: Double {
        abs(currentWeight - goalWeight)
    }

    private var isLosing: Bool {
        startWeight > goalWeight
    }

    var body: some View {
        VStack(spacing: 16) {
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(uiColor: .tertiarySystemGroupedBackground))
                        .frame(height: 12)

                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: [.blue, .green],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * progress, height: 12)
                }
            }
            .frame(height: 12)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Current")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.1f kg", currentWeight))
                        .font(.subheadline)
                        .fontWeight(.medium)
                }

                Spacer()

                VStack(spacing: 2) {
                    Text(String(format: "%.1f kg", remaining))
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundStyle(.blue)
                    Text(isLosing ? "to lose" : "to gain")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("Goal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.1f kg", goalWeight))
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
            }
        }
    }
}
