import SwiftUI

// MARK: - Agentic Generation View
struct AgenticGenerationView: View {
    @Bindable var generator: AgenticPlanGenerator
    let config: PlanConfiguration
    let userProfile: UserProfile?
    let onComplete: ([PlannedDay]) -> Void
    let onCancel: () -> Void

    @State private var hasStarted = false

    var body: some View {
        VStack(spacing: 24) {
            // Header with progress ring
            generationHeader

            // Progress bar
            progressSection

            // Current phase indicator
            phaseIndicator

            // Generated meals preview
            if !generator.generatedDays.isEmpty {
                generatedMealsPreview
            }

            Spacer()

            // Stats footer
            if generator.stats.totalMealsPlanned > 0 {
                statsFooter
            }

            // Cancel button
            cancelButton
        }
        .padding()
        .task {
            guard !hasStarted else { return }
            hasStarted = true
            await startGeneration()
        }
    }

    // MARK: - Header
    private var generationHeader: some View {
        VStack(spacing: 16) {
            ZStack {
                // Background ring
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 8)
                    .frame(width: 100, height: 100)

                // Progress ring
                Circle()
                    .trim(from: 0, to: generator.progress)
                    .stroke(
                        LinearGradient(
                            colors: [.purple, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.3), value: generator.progress)

                // Center content
                VStack(spacing: 2) {
                    if generator.phase == .completed {
                        Image(systemName: "checkmark")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundStyle(.green)
                    } else {
                        Text("\(Int(generator.progress * 100))")
                            .font(.title)
                            .fontWeight(.bold)
                        Text("%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            VStack(spacing: 4) {
                Text(generator.phase == .completed ? "Plan Complete!" : "Creating Your Plan")
                    .font(.title2)
                    .fontWeight(.bold)

                if generator.phase != .completed {
                    Text("\(generator.mealsGenerated) of \(generator.totalMealsToGenerate) meals generated")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.top, 20)
    }

    // MARK: - Progress Section
    private var progressSection: some View {
        VStack(spacing: 8) {
            ProgressView(value: generator.progress)
                .tint(.blue)

            HStack {
                if generator.isGenerating && generator.estimatedTimeRemaining > 0 {
                    Text("~\(Int(generator.estimatedTimeRemaining))s remaining")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("Day \(generator.currentDayIndex + 1) of \(config.daysCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    // MARK: - Phase Indicator
    private var phaseIndicator: some View {
        HStack(spacing: 12) {
            Image(systemName: generator.phase.icon)
                .font(.title3)
                .foregroundStyle(phaseIconColor)
                .frame(width: 30)

            Text(generator.phase.displayText)
                .font(.subheadline)
                .fontWeight(.medium)

            Spacer()

            if generator.isGenerating && generator.phase != .completed {
                ProgressView()
                    .scaleEffect(0.8)
            } else if generator.phase == .completed {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .padding()
        .background(phaseBackgroundColor)
        .cornerRadius(12)
    }

    private var phaseBackgroundColor: Color {
        switch generator.phase {
        case .completed: return Color.green.opacity(0.1)
        case .failed: return Color.red.opacity(0.1)
        case .usingFallback: return Color.orange.opacity(0.1)
        case .retrying: return Color.yellow.opacity(0.1)
        default: return Color.blue.opacity(0.1)
        }
    }

    private var phaseIconColor: Color {
        switch generator.phase {
        case .completed: return .green
        case .failed: return .red
        case .usingFallback: return .orange
        case .retrying: return .yellow
        default: return .blue
        }
    }

    // MARK: - Generated Meals Preview
    private var generatedMealsPreview: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(Array(generator.generatedDays.enumerated()), id: \.element.id) { index, day in
                    DayProgressCard(
                        dayIndex: index,
                        day: day,
                        isCurrentDay: index == generator.currentDayIndex && generator.isGenerating,
                        targetCalories: config.dailyCalories
                    )
                }
            }
        }
        .frame(maxHeight: 280)
    }

    // MARK: - Stats Footer
    private var statsFooter: some View {
        HStack(spacing: 20) {
            GenerationStatPill(
                icon: "sparkles",
                value: "\(generator.stats.aiGeneratedMeals)",
                label: "AI Generated",
                color: .blue
            )

            GenerationStatPill(
                icon: "bookmark.fill",
                value: "\(generator.stats.fallbackMeals)",
                label: "Curated",
                color: .orange
            )

            if generator.stats.retriesUsed > 0 {
                GenerationStatPill(
                    icon: "arrow.triangle.2.circlepath",
                    value: "\(generator.stats.retriesUsed)",
                    label: "Retries",
                    color: .yellow
                )
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    // MARK: - Cancel Button
    private var cancelButton: some View {
        Group {
            if generator.phase == .completed {
                Button(action: {
                    onComplete(generator.generatedDays)
                }) {
                    HStack {
                        Text("Review Plan")
                        Image(systemName: "chevron.right")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .cornerRadius(14)
                }
            } else {
                Button(action: {
                    generator.cancel()
                    onCancel()
                }) {
                    Text("Cancel")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding()
                }
            }
        }
    }

    // MARK: - Actions
    private func startGeneration() async {
        do {
            _ = try await generator.generatePlan(
                config: config,
                userProfile: userProfile
            )
            // Generation complete - user will tap "Review Plan" to proceed
        } catch {
            #if DEBUG
            print("Generation failed: \(error)")
            #endif
            // Error state is handled by the generator
        }
    }
}

// MARK: - Day Progress Card
struct DayProgressCard: View {
    let dayIndex: Int
    let day: PlannedDay
    let isCurrentDay: Bool
    let targetCalories: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(day.dayName)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                Text("\(day.meals.count)/4 meals")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if day.isComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
            }

            if !day.meals.isEmpty {
                HStack(spacing: 6) {
                    ForEach(day.meals) { meal in
                        MealProgressChip(meal: meal)
                    }

                    // Placeholder chips for remaining meals
                    ForEach(0..<(4 - day.meals.count), id: \.self) { _ in
                        Circle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 24, height: 24)
                    }
                }
            }

            if day.isComplete {
                HStack {
                    Text("\(day.totalCalories) kcal")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    let deviation = day.totalCalories - targetCalories
                    if abs(deviation) > 100 {
                        Text("\(deviation > 0 ? "+" : "")\(deviation)")
                            .font(.caption)
                            .foregroundStyle(abs(deviation) < 200 ? .orange : .red)
                    } else {
                        Text("On target")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }
        }
        .padding()
        .background(isCurrentDay ? Color.blue.opacity(0.1) : Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isCurrentDay ? Color.blue : Color.clear, lineWidth: 2)
        )
    }
}

// MARK: - Meal Progress Chip
struct MealProgressChip: View {
    let meal: PlannedMeal

    var body: some View {
        Text(String(meal.type.rawValue.prefix(1)))
            .font(.caption2)
            .fontWeight(.bold)
            .frame(width: 24, height: 24)
            .background(chipColor.opacity(0.2))
            .foregroundStyle(chipColor)
            .cornerRadius(6)
    }

    private var chipColor: Color {
        meal.type.color
    }
}

// MARK: - Generation Stat Pill
struct GenerationStatPill: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.bold)
            }
            .foregroundStyle(color)

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
