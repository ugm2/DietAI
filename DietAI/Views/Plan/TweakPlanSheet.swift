import SwiftUI
import SwiftData

// MARK: - Tweak Plan Sheet
struct TweakPlanSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query var userProfiles: [UserProfile]

    let plan: DietPlan

    @State private var tweakService = TweakPlanService()
    @State private var userPrompt: String = ""
    @FocusState private var isTextFieldFocused: Bool

    private var userProfile: UserProfile? {
        userProfiles.first
    }

    private var restrictions: [String] {
        userProfile?.dietaryRestrictions ?? []
    }

    var body: some View {
        NavigationStack {
            Group {
                switch tweakService.phase {
                case .idle, .parsing:
                    inputView
                case .generating:
                    generatingView
                case .preview:
                    previewView
                case .applying:
                    applyingView
                case .completed:
                    completedView
                case .error(let message):
                    errorView(message: message)
                }
            }
            .navigationTitle("Tweak Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        tweakService.reset()
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Input View
    private var inputView: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "wand.and.sparkles")
                        .font(.system(size: 40))
                        .foregroundStyle(.purple)

                    Text("Tweak Your Plan")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Describe what you'd like to change")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 20)

                // Input field
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.purple)
                        TextField("e.g., Make breakfasts higher protein...", text: $userPrompt)
                            .textFieldStyle(.plain)
                            .focused($isTextFieldFocused)
                            .submitLabel(.search)
                            .onSubmit {
                                if !userPrompt.isEmpty {
                                    prepareTweak()
                                }
                            }
                    }
                    .padding()
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .cornerRadius(12)

                    // Quick suggestion chips
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(TweakIntentParser.quickSuggestions, id: \.label) { suggestion in
                                QuickSuggestionChip(
                                    title: suggestion.label,
                                    icon: iconForSuggestion(suggestion.label),
                                    isSelected: userPrompt == suggestion.prompt
                                ) {
                                    userPrompt = suggestion.prompt
                                    prepareTweak()
                                }
                            }
                        }
                    }
                }

                // Preview of what will change
                if let intent = tweakService.currentIntent {
                    intentPreviewCard(intent)
                }

                // Action button
                if !userPrompt.isEmpty && tweakService.phase == .idle {
                    if tweakService.currentIntent == nil || tweakService.affectedMeals.isEmpty {
                        Button {
                            prepareTweak()
                        } label: {
                            HStack {
                                Image(systemName: "magnifyingglass")
                                Text("Preview Changes")
                            }
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.purple)
                            .foregroundStyle(.white)
                            .cornerRadius(10)
                        }
                    } else {
                        Button {
                            generateReplacements()
                        } label: {
                            HStack {
                                Image(systemName: "wand.and.stars")
                                Text("Generate \(tweakService.affectedMeals.count) Replacements")
                            }
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.purple)
                            .foregroundStyle(.white)
                            .cornerRadius(10)
                        }
                    }
                }

                // Examples section
                if tweakService.currentIntent == nil {
                    examplesSection
                }
            }
            .padding()
        }
        .keyboardDismissToolbar()
        .onTapGesture {
            isTextFieldFocused = false
        }
    }

    // MARK: - Intent Preview Card
    private func intentPreviewCard(_ intent: TweakIntent) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Understood!")
                    .fontWeight(.medium)
            }

            Text(intent.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if !tweakService.affectedMeals.isEmpty {
                Divider()

                HStack {
                    Image(systemName: "fork.knife")
                        .foregroundStyle(.orange)
                    Text("\(tweakService.affectedMeals.count) meals will be changed")
                        .font(.caption)
                }

                // Show affected meal types/days
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(tweakService.affectedMeals.prefix(5), id: \.id) { meal in
                            Text(meal.name)
                                .font(.caption2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.orange.opacity(0.15))
                                .foregroundStyle(.orange)
                                .cornerRadius(8)
                        }
                        if tweakService.affectedMeals.count > 5 {
                            Text("+\(tweakService.affectedMeals.count - 5) more")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    // MARK: - Examples Section
    private var examplesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Example prompts")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 8) {
                exampleRow("Make all breakfasts higher protein")
                exampleRow("Replace lunches with lighter options")
                exampleRow("Remove all salmon dishes")
                exampleRow("Make Wednesday vegetarian")
                exampleRow("I don't like the dinners")
            }
        }
        .padding(.top, 8)
    }

    private func exampleRow(_ text: String) -> some View {
        Button {
            userPrompt = text
        } label: {
            HStack {
                Image(systemName: "text.bubble")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.vertical, 6)
        }
    }

    // MARK: - Generating View
    private var generatingView: some View {
        VStack(spacing: 24) {
            Spacer()

            // Animated icon
            Image(systemName: "wand.and.stars")
                .font(.system(size: 60))
                .foregroundStyle(.purple)
                .symbolEffect(.bounce, value: tweakService.progress)

            Text("Generating replacements...")
                .font(.title3)
                .fontWeight(.semibold)

            // Progress bar
            VStack(spacing: 8) {
                ProgressView(value: tweakService.progress)
                    .tint(.purple)

                Text("\(Int(tweakService.progress * 100))% complete")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 40)

            Text("Creating \(tweakService.affectedMeals.count) new meals")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()
        }
    }

    // MARK: - Preview View
    private var previewView: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 4) {
                Text("Preview Changes")
                    .font(.headline)
                Text("\(tweakService.acceptedCount) of \(tweakService.proposedChanges.count) changes selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()

            Divider()

            // Changes list
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach($tweakService.proposedChanges) { $change in
                        MealChangeCard(change: $change)
                    }
                }
                .padding()
            }

            Divider()

            // Apply button
            Button {
                applyChanges()
            } label: {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Apply \(tweakService.acceptedCount) Changes")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(tweakService.acceptedCount > 0 ? Color.green : Color.gray)
                .foregroundStyle(.white)
            }
            .disabled(tweakService.acceptedCount == 0)
            .padding()
        }
    }

    // MARK: - Applying View
    private var applyingView: some View {
        VStack(spacing: 24) {
            Spacer()

            ProgressView()
                .scaleEffect(1.5)

            Text("Applying changes...")
                .font(.title3)
                .fontWeight(.medium)

            Spacer()
        }
    }

    // MARK: - Completed View
    private var completedView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.green)

            Text("Plan Updated!")
                .font(.title2)
                .fontWeight(.bold)

            Text("\(tweakService.acceptedCount) meals have been replaced")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                tweakService.reset()
                dismiss()
            } label: {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.green)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 40)

            Spacer()
        }
    }

    // MARK: - Error View
    private func errorView(message: String) -> some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.orange)

            Text("Something went wrong")
                .font(.title3)
                .fontWeight(.semibold)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                tweakService.reset()
            } label: {
                Text("Try Again")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 40)

            Spacer()
        }
    }

    // MARK: - Helper Methods
    private func iconForSuggestion(_ label: String) -> String {
        switch label {
        case "More Protein": return "bolt.fill"
        case "Lighter Meals": return "leaf.fill"
        case "Quick Prep": return "clock.fill"
        case "Vegetarian": return "carrot.fill"
        default: return "sparkles"
        }
    }

    private func prepareTweak() {
        Task {
            do {
                try await tweakService.prepareTweak(prompt: userPrompt, plan: plan)
            } catch {
                tweakService.phase = .error(error.localizedDescription)
            }
        }
    }

    private func generateReplacements() {
        Task {
            do {
                try await tweakService.generateReplacements(plan: plan, restrictions: restrictions)
            } catch {
                tweakService.phase = .error(error.localizedDescription)
            }
        }
    }

    private func applyChanges() {
        tweakService.applyChanges(modelContext: modelContext)
    }
}

// MARK: - Meal Change Card
struct MealChangeCard: View {
    @Binding var change: MealChange

    private var hasActualChange: Bool {
        change.originalMeal.name != change.newMealName
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with day, meal type, and toggle
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(change.dayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(change.originalMeal.type.rawValue)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.orange)
                }

                Spacer()

                if !hasActualChange {
                    Text("No change")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.gray.opacity(0.15))
                        .cornerRadius(6)
                }

                Toggle("", isOn: $change.isAccepted)
                    .labelsHidden()
                    .tint(.green)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(uiColor: .tertiarySystemGroupedBackground))

            // Before → After (stacked vertically for full visibility)
            VStack(alignment: .leading, spacing: 12) {
                // Before
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Before")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Spacer()
                        Text("\(change.originalMeal.calories) kcal")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(change.originalMeal.name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .strikethrough(hasActualChange && change.isAccepted)
                }

                if hasActualChange {
                    // Arrow
                    HStack {
                        Image(systemName: "arrow.down")
                            .font(.caption)
                            .foregroundStyle(.purple)
                        Spacer()
                    }

                    // After
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("After")
                                .font(.caption2)
                                .foregroundStyle(.purple)
                                .textCase(.uppercase)
                            Spacer()
                            HStack(spacing: 4) {
                                Text("\(change.newCalories) kcal")
                                    .font(.caption)
                                if change.calorieDelta != 0 {
                                    Text("(\(change.calorieDelta > 0 ? "+" : "")\(change.calorieDelta))")
                                        .font(.caption2)
                                        .foregroundStyle(change.calorieDelta > 0 ? .orange : .green)
                                }
                            }
                            .foregroundStyle(.secondary)
                        }
                        Text(change.newMealName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(change.isAccepted ? .primary : .secondary)
                    }
                }
            }
            .padding(16)
            .opacity(change.isAccepted ? 1.0 : 0.5)
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
}
