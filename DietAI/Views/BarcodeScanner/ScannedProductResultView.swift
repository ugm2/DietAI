import SwiftUI

// MARK: - Scanned Product Result View

struct ScannedProductResultView: View {
    let product: ScannedProduct
    let onLog: (MealType, Double, Date) -> Void
    let onScanAgain: () -> Void

    @State private var servingGrams: Double
    @State private var selectedMealType: MealType = .snack
    @State private var selectedDate: Date = Date()

    // Computed nutrition based on serving size
    private var nutrition: (calories: Int, protein: Int, carbs: Int, fat: Int) {
        product.nutritionFor(grams: servingGrams)
    }

    init(
        product: ScannedProduct,
        onLog: @escaping (MealType, Double, Date) -> Void,
        onScanAgain: @escaping () -> Void
    ) {
        self.product = product
        self.onLog = onLog
        self.onScanAgain = onScanAgain

        // Default to product serving size or 100g
        let defaultServing = product.servingSizeGrams ?? 100
        self._servingGrams = State(initialValue: defaultServing)

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
                // Product header
                productHeader

                // Serving size adjuster
                servingSizeCard

                // Nutrition info
                nutritionCard

                // Meal type selector
                mealTypeSelector

                // Date picker
                dateSelector

                // Log button
                logButton

                // Scan again option
                Button("Scan Another Product") {
                    onScanAgain()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 8)

                Spacer(minLength: 40)
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    // MARK: - Product Header

    private var productHeader: some View {
        VStack(spacing: 12) {
            // Product image if available
            if let imageURL = product.imageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    case .failure:
                        productPlaceholder
                    case .empty:
                        ProgressView()
                            .frame(height: 120)
                    @unknown default:
                        productPlaceholder
                    }
                }
            } else {
                productPlaceholder
            }

            // Product name
            Text(product.name)
                .font(.title2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)

            // Brand
            if let brand = product.brand {
                Text(brand)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(16)
    }

    private var productPlaceholder: some View {
        Image(systemName: "barcode")
            .font(.system(size: 50))
            .foregroundStyle(.secondary)
            .frame(height: 120)
    }

    // Max grams for slider - use product total weight or default to 500g
    private var sliderMaxGrams: Double {
        if let total = product.totalWeightGrams, total > 10 {
            return total
        }
        return 500
    }

    // MARK: - Serving Size Card

    private var servingSizeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Serving Size")
                    .font(.headline)
                Spacer()
                Text("\(Int(servingGrams))g")
                    .font(.headline)
                    .foregroundStyle(.blue)
            }

            // Slider for serving size (max based on product total weight)
            Slider(value: $servingGrams, in: 10...sliderMaxGrams, step: 5)
                .tint(.blue)

            // Quick select buttons
            HStack(spacing: 8) {
                ForEach(quickServingSizes, id: \.0) { label, grams in
                    Button {
                        servingGrams = grams
                    } label: {
                        Text(label)
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                servingGrams == grams
                                    ? Color.blue
                                    : Color(uiColor: .tertiarySystemGroupedBackground)
                            )
                            .foregroundStyle(servingGrams == grams ? .white : .primary)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Package info
            if let total = product.totalWeightGrams {
                Text("Package: \(Int(total))g")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let originalServing = product.servingSize {
                Text("Package serving: \(originalServing)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(16)
    }

    private var quickServingSizes: [(String, Double)] {
        var sizes: [(String, Double)] = [
            ("50g", 50),
            ("100g", 100),
            ("150g", 150),
            ("200g", 200)
        ]

        // Add product serving size if different
        if let productServing = product.servingSizeGrams,
           !sizes.contains(where: { $0.1 == productServing }) {
            sizes.insert(("1 serving", productServing), at: 0)
        }

        // Add whole package option if total weight is known
        if let totalWeight = product.totalWeightGrams,
           totalWeight > 200,
           !sizes.contains(where: { $0.1 == totalWeight }) {
            sizes.append(("Whole", totalWeight))
        }

        return Array(sizes.prefix(5))
    }

    // MARK: - Nutrition Card

    private var nutritionCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Nutrition")
                .font(.headline)

            // Main calories display
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(nutrition.calories)")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                    Text("calories")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                // Macro rings
                HStack(spacing: 16) {
                    MacroRing(label: "Protein", value: nutrition.protein, color: .red)
                    MacroRing(label: "Carbs", value: nutrition.carbs, color: .blue)
                    MacroRing(label: "Fat", value: nutrition.fat, color: .yellow)
                }
            }

            Divider()

            // Detailed macros
            HStack(spacing: 0) {
                NutritionDetail(label: "Protein", value: "\(nutrition.protein)g", color: .red)
                NutritionDetail(label: "Carbs", value: "\(nutrition.carbs)g", color: .blue)
                NutritionDetail(label: "Fat", value: "\(nutrition.fat)g", color: .yellow)
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(16)
    }

    // MARK: - Meal Type Selector

    private var mealTypeSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Log as")
                .font(.headline)

            HStack(spacing: 8) {
                ForEach(MealType.allCases, id: \.self) { type in
                    Button {
                        selectedMealType = type
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: iconFor(type))
                                .font(.title3)
                            Text(type.rawValue)
                                .font(.caption)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            selectedMealType == type
                                ? colorFor(type).opacity(0.2)
                                : Color(uiColor: .tertiarySystemGroupedBackground)
                        )
                        .foregroundStyle(selectedMealType == type ? colorFor(type) : .secondary)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(selectedMealType == type ? colorFor(type) : .clear, lineWidth: 2)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(16)
    }

    private func iconFor(_ type: MealType) -> String {
        type.icon
    }

    private func colorFor(_ type: MealType) -> Color {
        type.color
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
                                ? Color.blue
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
                                ? Color.blue
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
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(16)
    }

    // MARK: - Log Button

    private var logButton: some View {
        Button {
            onLog(selectedMealType, servingGrams, selectedDate)
        } label: {
            HStack {
                Image(systemName: "plus.circle.fill")
                Text("Log \(nutrition.calories) kcal")
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue)
            .foregroundStyle(.white)
            .cornerRadius(14)
        }
    }
}

// MARK: - Supporting Views

struct MacroRing: View {
    let label: String
    let value: Int
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.2), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: min(CGFloat(value) / 50, 1))
                    .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(value)")
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            .frame(width: 40, height: 40)

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

struct NutritionDetail: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
