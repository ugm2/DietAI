import SwiftUI

// MARK: - Food Estimate Result View

struct FoodEstimateResultView: View {
    let estimate: FoodEstimate
    let onSave: (FoodEstimate, MealType, Date) -> Void
    let onRetry: () -> Void
    var accentColor: Color = .pink

    // Editable values
    @State private var editedFoodName: String
    @State private var editedPortionDescription: String
    @State private var editedCalories: String
    @State private var editedProtein: String
    @State private var editedCarbs: String
    @State private var editedFat: String
    @State private var selectedMealType: MealType
    @State private var selectedDate: Date = Date()

    init(
        estimate: FoodEstimate,
        onSave: @escaping (FoodEstimate, MealType, Date) -> Void,
        onRetry: @escaping () -> Void,
        accentColor: Color = .pink
    ) {
        self.estimate = estimate
        self.onSave = onSave
        self.onRetry = onRetry
        self.accentColor = accentColor

        // Initialize editable values
        self._editedFoodName = State(initialValue: estimate.foodName)
        self._editedPortionDescription = State(initialValue: estimate.portionDescription)
        self._editedCalories = State(initialValue: String(estimate.calories))
        self._editedProtein = State(initialValue: String(estimate.protein))
        self._editedCarbs = State(initialValue: String(estimate.carbs))
        self._editedFat = State(initialValue: String(estimate.fat))

        // Guess meal type based on time of day
        let hour = Calendar.current.component(.hour, from: Date())
        let guessedType: MealType
        switch hour {
        case 5..<11: guessedType = .breakfast
        case 11..<15: guessedType = .lunch
        case 15..<18: guessedType = .snack
        default: guessedType = .dinner
        }
        self._selectedMealType = State(initialValue: guessedType)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Food name header
                foodHeader

                // Confidence indicator
                confidenceIndicator

                // Portion description
                portionCard

                // Editable nutrition
                nutritionCard

                // Components/ingredients
                if !estimate.components.isEmpty {
                    componentsCard
                }

                // Meal type selector
                mealTypeSelector

                // Date selector
                dateSelector

                // Save button
                saveButton

                // Retry option
                Button("Take Another Photo") {
                    onRetry()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 8)

                Spacer(minLength: 40)
            }
            .padding()
        }
        .keyboardDismissible()
        .background(Color(uiColor: .systemGroupedBackground))
    }

    // MARK: - Food Header

    private var foodHeader: some View {
        VStack(spacing: 12) {
            // Food icon
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.1))
                    .frame(width: 80, height: 80)

                Image(systemName: "fork.knife")
                    .font(.system(size: 35))
                    .foregroundStyle(accentColor)
            }

            // Food name (editable)
            TextField("Food name", text: $editedFoodName)
                .font(.title2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)

            Text("Tap to edit name")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(16)
    }

    // MARK: - Confidence Indicator

    private var confidenceIndicator: some View {
        HStack {
            Image(systemName: confidenceIcon)
                .foregroundStyle(confidenceColor)

            Text(estimate.confidenceLevel.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Text("\(Int(estimate.confidence * 100))%")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(confidenceColor)
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    private var confidenceIcon: String {
        switch estimate.confidenceLevel {
        case .high: return "checkmark.circle.fill"
        case .moderate: return "exclamationmark.circle.fill"
        case .low: return "questionmark.circle.fill"
        }
    }

    private var confidenceColor: Color {
        switch estimate.confidenceLevel {
        case .high: return .green
        case .moderate: return .orange
        case .low: return .red
        }
    }

    // MARK: - Portion Card

    private var portionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Portion")
                    .font(.headline)
                Spacer()
                Text("Tap to edit")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextField("e.g., 1 cup, 200g, medium plate", text: $editedPortionDescription)
                .font(.body)
                .foregroundStyle(.primary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    // MARK: - Nutrition Card (Editable)

    private var nutritionCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Nutrition")
                    .font(.headline)
                Spacer()
                Text("Tap to edit")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Calories (main)
            HStack {
                Label("Calories", systemImage: "flame.fill")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                Spacer()
                TextField("0", text: $editedCalories)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .frame(width: 80)
                Text("kcal")
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Macros grid
            HStack(spacing: 16) {
                macroField(
                    label: "Protein",
                    icon: "p.circle.fill",
                    color: .red,
                    value: $editedProtein
                )

                macroField(
                    label: "Carbs",
                    icon: "c.circle.fill",
                    color: .blue,
                    value: $editedCarbs
                )

                macroField(
                    label: "Fat",
                    icon: "f.circle.fill",
                    color: .yellow,
                    value: $editedFat
                )
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    private func macroField(label: String, icon: String, color: Color, value: Binding<String>) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.title3)

            TextField("0", text: value)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.headline)
                .frame(width: 50)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Components Card

    private var componentsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Detected Ingredients")
                .font(.headline)

            FlowLayout(spacing: 8) {
                ForEach(estimate.components, id: \.self) { component in
                    Text(component)
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(accentColor.opacity(0.1))
                        .foregroundStyle(accentColor)
                        .cornerRadius(20)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    // MARK: - Meal Type Selector

    private var mealTypeSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Log as")
                .font(.headline)

            HStack(spacing: 12) {
                ForEach([MealType.breakfast, .lunch, .snack, .dinner], id: \.self) { type in
                    mealTypeButton(type)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    private func mealTypeButton(_ type: MealType) -> some View {
        Button {
            selectedMealType = type
        } label: {
            VStack(spacing: 4) {
                Image(systemName: mealTypeIcon(type))
                    .font(.title3)
                Text(type.rawValue)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(selectedMealType == type ? accentColor : Color.clear)
            .foregroundStyle(selectedMealType == type ? .white : .primary)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(selectedMealType == type ? Color.clear : Color.gray.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func mealTypeIcon(_ type: MealType) -> String {
        switch type {
        case .breakfast: return "sunrise.fill"
        case .brunch: return "sun.haze.fill"
        case .lunch: return "sun.max.fill"
        case .snack: return "leaf.fill"
        case .dinner: return "moon.stars.fill"
        }
    }

    // MARK: - Date Selector

    private var dateSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Date")
                .font(.headline)

            HStack {
                // Quick date buttons
                Button {
                    selectedDate = Date()
                } label: {
                    Text("Today")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Calendar.current.isDateInToday(selectedDate)
                                ? accentColor
                                : Color(uiColor: .tertiarySystemGroupedBackground)
                        )
                        .foregroundStyle(Calendar.current.isDateInToday(selectedDate) ? .white : .primary)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)

                Button {
                    selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
                } label: {
                    Text("Yesterday")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Calendar.current.isDateInYesterday(selectedDate)
                                ? accentColor
                                : Color(uiColor: .tertiarySystemGroupedBackground)
                        )
                        .foregroundStyle(Calendar.current.isDateInYesterday(selectedDate) ? .white : .primary)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)

                Spacer()

                // Date picker for custom date
                DatePicker("", selection: $selectedDate, displayedComponents: .date)
                    .labelsHidden()
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    // MARK: - Save Button

    private var saveButton: some View {
        Button(action: handleSave) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                Text("Log Meal")
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(accentColor)
            .cornerRadius(12)
        }
    }

    private func handleSave() {
        // Create adjusted estimate with all edited values
        let adjustedEstimate = estimate.withAdjustments(
            foodName: editedFoodName,
            portionDescription: editedPortionDescription,
            calories: Int(editedCalories) ?? estimate.calories,
            protein: Int(editedProtein) ?? estimate.protein,
            carbs: Int(editedCarbs) ?? estimate.carbs,
            fat: Int(editedFat) ?? estimate.fat
        )

        onSave(adjustedEstimate, selectedMealType, selectedDate)
    }
}

// MARK: - Preview
// Note: FlowLayout is defined in DietDetailView.swift and shared across the app

#Preview {
    FoodEstimateResultView(
        estimate: FoodEstimate.preview,
        onSave: { _, _, _ in },
        onRetry: { }
    )
}
