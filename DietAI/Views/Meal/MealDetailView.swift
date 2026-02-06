import SwiftUI
import SwiftData

struct MealDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let meal: Meal
    let dailyPlan: DailyPlan?

    @State private var showSwapSheet = false
    @State private var showAdjustSheet = false
    @State private var showUseIngredientsSheet = false
    @State private var showQuickPrepSheet = false
    @State private var showHowToPrepSheet = false
    @State private var showEditSheet = false
    @State private var isSwapping = false
    @State private var alternatives: [PlannedMeal] = []
    @State private var isLogged = false
    @State private var showLoggingSuccess = false
    @State private var isDownloadingModel = false

    private let modelManager = ModelManager.shared

    // Daily targets for macro rings (reasonable defaults)
    private var dailyProteinTarget: Int { 150 }
    private var dailyCarbsTarget: Int { 200 }
    private var dailyFatTarget: Int { 65 }

    // Generate simple recipe steps based on ingredients
    private var recipeSteps: [String] {
        if !meal.cookingInstructions.isEmpty {
            return meal.cookingInstructions
        }
        return generateRecipeSteps(for: meal)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Hero Header
                heroHeader

                VStack(spacing: 24) {
                    // Macro Circles Section
                    macroCirclesSection

                    // Ingredients Section
                    ingredientsSection

                    // How to Prep Button
                    howToPrepButton

                    // AI Quick Actions Section
                    aiQuickActionsSection

                    // Edit Meal Button
                    editMealButton

                    Spacer(minLength: 40)
                }
                .padding(.horizontal)
                .padding(.top, 20)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                logButton
            }
        }
        .sheet(isPresented: $showSwapSheet) {
            MealSwapSheet(
                originalMeal: meal,
                alternatives: alternatives,
                isLoading: isSwapping,
                onSelect: { newMeal in
                    swapMeal(with: newMeal)
                },
                onRegenerate: { preference in
                    Task { await generateAlternatives(preference: preference) }
                }
            )
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showAdjustSheet) {
            AdjustCaloriesSheet(meal: meal, onApply: { adjustedMeal in
                applyMealChanges(adjustedMeal)
            })
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showUseIngredientsSheet) {
            UseIngredientsSheet(meal: meal, onGenerate: { newMeal in
                applyMealChanges(newMeal)
            })
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showQuickPrepSheet) {
            QuickPrepSheet(meal: meal, onSelect: { newMeal in
                applyMealChanges(newMeal)
            })
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showHowToPrepSheet) {
            HowToPrepSheet(meal: meal, steps: recipeSteps)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showEditSheet) {
            EditMealSheet(meal: meal, onSave: { updatedMeal in
                applyMealChanges(updatedMeal)
            })
            .presentationDetents([.large])
        }
        .onAppear {
            isLogged = meal.isLogged
        }
        .fullScreenCover(isPresented: $isDownloadingModel) {
            ModelDownloadView(
                modelManager: modelManager,
                onComplete: {
                    isDownloadingModel = false
                    // Continue generating alternatives after model is ready
                    Task { await continueGeneratingAlternatives() }
                },
                onCancel: {
                    isDownloadingModel = false
                }
            )
            .interactiveDismissDisabled()
        }
        .overlay(alignment: .top) {
            if showLoggingSuccess {
                Text("Meal Logged!")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.green)
                    .cornerRadius(20)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 8)
            }
        }
    }

    // MARK: - Log Button
    private var logButton: some View {
        Button {
            logMeal()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isLogged ? "checkmark.circle.fill" : "plus.circle.fill")
                Text(isLogged ? "Logged" : "Log")
            }
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundStyle(isLogged ? .green : .blue)
        }
        .disabled(isLogged)
    }

    // MARK: - Hero Header
    private var heroHeader: some View {
        ZStack(alignment: .bottom) {
            // Gradient Background
            LinearGradient(
                colors: [mealColor, mealColor.opacity(0.7)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(height: 260)

            // Decorative circles
            Circle()
                .fill(Color.white.opacity(0.1))
                .frame(width: 200, height: 200)
                .offset(x: 100, y: -50)

            Circle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 150, height: 150)
                .offset(x: -120, y: 30)

            // Content
            VStack(spacing: 16) {
                // Meal Type Badge
                HStack(spacing: 8) {
                    Image(systemName: mealIcon)
                        .font(.title3)
                    Text(meal.type.rawValue)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.2))
                .cornerRadius(20)

                // Meal Name
                Text(meal.name)
                    .font(.title)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // Quick Stats - using actual prep time and difficulty
                HStack(spacing: 16) {
                    QuickStatPill(icon: "flame.fill", value: "\(meal.calories)", label: "kcal")
                    QuickStatPill(icon: "clock.fill", value: "\(meal.prepTimeMinutes)", label: "min")
                    QuickStatPill(icon: "chef.hat.fill", value: meal.difficulty.rawValue, label: "")
                }
            }
            .foregroundStyle(.white)
            .padding(.bottom, 30)
        }
    }

    // MARK: - Macro Circles Section
    private var macroCirclesSection: some View {
        VStack(spacing: 16) {
            // Calories display
            Text("\(meal.calories) kcal")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            // Macro rings
            HStack(spacing: 24) {
                MacroRingView(
                    value: meal.protein,
                    target: dailyProteinTarget,
                    label: "Protein",
                    unit: "g",
                    color: .red
                )

                MacroRingView(
                    value: meal.carbs,
                    target: dailyCarbsTarget,
                    label: "Carbs",
                    unit: "g",
                    color: .blue
                )

                MacroRingView(
                    value: meal.fat,
                    target: dailyFatTarget,
                    label: "Fat",
                    unit: "g",
                    color: .yellow
                )
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(16)
    }

    // MARK: - Ingredients Section
    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Ingredients", icon: "basket.fill")

            VStack(spacing: 0) {
                ForEach(Array(meal.ingredients.enumerated()), id: \.offset) { index, ingredient in
                    IngredientRow(
                        ingredient: ingredient,
                        isLast: index == meal.ingredients.count - 1
                    )
                }
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .cornerRadius(16)
        }
    }

    // MARK: - How to Prep Button
    private var howToPrepButton: some View {
        Button {
            showHowToPrepSheet = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "book.fill")
                    .font(.title3)
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text("How to Prep")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("\(recipeSteps.count) steps • \(meal.prepTimeMinutes) min")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }

    // MARK: - AI Quick Actions Section
    private var aiQuickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "AI Actions", icon: "sparkles")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                // Swap Meal
                AIActionButton(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Swap",
                    subtitle: "Get alternatives",
                    color: .purple
                ) {
                    showSwapSheet = true
                    Task { await generateAlternatives(preference: "") }
                }

                // Adjust Calories
                AIActionButton(
                    icon: "scale.3d",
                    title: "Adjust",
                    subtitle: "Change calories",
                    color: .orange
                ) {
                    showAdjustSheet = true
                }

                // Use Ingredients
                AIActionButton(
                    icon: "carrot.fill",
                    title: "Use Ingredients",
                    subtitle: "Specify what you have",
                    color: .green
                ) {
                    showUseIngredientsSheet = true
                }

                // Quick Prep
                AIActionButton(
                    icon: "bolt.fill",
                    title: "Quick Prep",
                    subtitle: "<15 min meal",
                    color: .blue
                ) {
                    showQuickPrepSheet = true
                }
            }
        }
    }

    // MARK: - Edit Meal Button
    private var editMealButton: some View {
        Button {
            showEditSheet = true
        } label: {
            HStack {
                Image(systemName: "pencil")
                Text("Edit Meal")
            }
            .font(.subheadline)
            .fontWeight(.medium)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .foregroundStyle(.blue)
            .cornerRadius(12)
        }
    }

    // MARK: - Helper Properties
    private var mealIcon: String {
        meal.type.icon
    }

    private var mealColor: Color {
        meal.type.color
    }

    @State private var currentPreference: String = ""

    // MARK: - Meal Logging
    private func logMeal() {
        let log = MealLog(meal: meal)
        modelContext.insert(log)
        meal.markAsLogged()

        // Log to HealthKit
        Task {
            let healthService = HealthKitService.shared
            if healthService.isAuthorized {
                try? await healthService.logMealNutrition(meal: meal)
            }
        }

        try? modelContext.save()

        withAnimation {
            isLogged = true
            showLoggingSuccess = true
        }

        // Hide success indicator after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showLoggingSuccess = false
            }
        }
    }

    // MARK: - Apply Changes
    private func applyMealChanges(_ newMeal: PlannedMeal) {
        meal.name = newMeal.name
        meal.calories = newMeal.calories
        meal.protein = newMeal.protein
        meal.carbs = newMeal.carbs
        meal.fat = newMeal.fat
        meal.ingredients = newMeal.ingredients
        try? modelContext.save()
    }

    // MARK: - Actions
    private func generateAlternatives(preference: String = "") async {
        currentPreference = preference

        // First, ensure model is loaded with visual feedback
        if !modelManager.isModelLoaded {
            await MainActor.run {
                isDownloadingModel = true
            }
            // Download view will call continueGeneratingAlternatives when done
            return
        }

        // Model already loaded, proceed directly
        await continueGeneratingAlternatives()
    }

    private func continueGeneratingAlternatives() async {
        isSwapping = true

        do {
            let service = MealSuggestionService.shared
            var newAlternatives: [PlannedMeal] = []

            // Generate 3 alternatives with user preference
            for _ in 0..<3 {
                let alternative = try await service.generateMealSuggestionWithPreference(
                    type: meal.type,
                    targetCalories: meal.calories,
                    goal: .maintenance,
                    restrictions: [],
                    existingMeals: [],
                    userPreference: currentPreference
                )
                // Avoid duplicates
                if !newAlternatives.contains(where: { $0.name == alternative.name }) && alternative.name != meal.name {
                    newAlternatives.append(alternative)
                }
            }

            alternatives = newAlternatives
        } catch {
            // Use fallback alternatives
            alternatives = generateFallbackAlternatives(preference: currentPreference)
        }

        isSwapping = false
    }

    private func generateFallbackAlternatives(preference: String = "") -> [PlannedMeal] {
        // Preference-based fallback options
        let highProteinMeals: [MealType: [(String, [String], Int, Int, Int, Int)]] = [
            .breakfast: [
                ("Egg White Omelette with Turkey", ["egg whites", "turkey bacon", "spinach", "feta"], 320, 35, 8, 12),
                ("Protein Pancakes", ["protein powder", "oats", "egg whites", "greek yogurt"], 380, 32, 42, 6),
                ("Greek Yogurt Power Bowl", ["greek yogurt", "protein granola", "almonds", "berries"], 350, 28, 35, 10)
            ],
            .lunch: [
                ("Grilled Chicken Caesar", ["chicken breast", "romaine", "parmesan", "light dressing"], 420, 42, 15, 18),
                ("Tuna Protein Bowl", ["tuna steak", "quinoa", "edamame", "avocado"], 450, 45, 32, 14),
                ("Turkey & Egg White Wrap", ["turkey breast", "egg whites", "spinach", "whole wheat wrap"], 380, 40, 28, 8)
            ],
            .dinner: [
                ("Grilled Salmon with Asparagus", ["salmon fillet", "asparagus", "lemon", "olive oil"], 480, 42, 12, 28),
                ("Chicken Breast with Quinoa", ["chicken breast", "quinoa", "broccoli", "garlic"], 420, 45, 35, 8),
                ("Lean Steak with Vegetables", ["sirloin steak", "mixed vegetables", "sweet potato"], 450, 40, 30, 15)
            ],
            .snack: [
                ("Protein Shake", ["protein powder", "almond milk", "banana", "peanut butter"], 280, 30, 25, 8),
                ("Cottage Cheese & Nuts", ["cottage cheese", "almonds", "honey"], 220, 22, 12, 10),
                ("Hard Boiled Eggs", ["eggs", "salt", "pepper"], 140, 12, 1, 10)
            ]
        ]

        let lowCarbMeals: [MealType: [(String, [String], Int, Int, Int, Int)]] = [
            .breakfast: [
                ("Keto Eggs Benedict", ["eggs", "canadian bacon", "hollandaise", "spinach"], 380, 25, 4, 30),
                ("Avocado Egg Cups", ["avocado", "eggs", "bacon bits", "cheese"], 350, 18, 6, 28),
                ("Smoked Salmon Plate", ["smoked salmon", "cream cheese", "capers", "cucumber"], 320, 22, 5, 24)
            ],
            .lunch: [
                ("Cobb Salad", ["chicken", "bacon", "eggs", "avocado", "blue cheese"], 450, 35, 8, 32),
                ("Lettuce Wrap Tacos", ["ground beef", "lettuce", "cheese", "sour cream", "salsa"], 380, 28, 10, 26),
                ("Zucchini Noodle Carbonara", ["zucchini noodles", "bacon", "egg", "parmesan"], 340, 22, 12, 24)
            ],
            .dinner: [
                ("Grilled Ribeye with Broccoli", ["ribeye steak", "broccoli", "butter", "garlic"], 520, 38, 8, 38),
                ("Baked Chicken Thighs", ["chicken thighs", "green beans", "olive oil", "herbs"], 420, 35, 10, 28),
                ("Shrimp Scampi (No Pasta)", ["shrimp", "garlic", "butter", "zucchini", "parsley"], 380, 32, 8, 24)
            ],
            .snack: [
                ("Cheese & Pepperoni", ["mozzarella", "pepperoni", "olives"], 220, 14, 2, 18),
                ("Celery with Cream Cheese", ["celery", "cream cheese", "everything seasoning"], 150, 4, 4, 14),
                ("Beef Jerky", ["beef jerky"], 120, 20, 3, 2)
            ]
        ]

        let quickMeals: [MealType: [(String, [String], Int, Int, Int, Int)]] = [
            .breakfast: [
                ("Instant Oatmeal with Banana", ["instant oats", "banana", "honey", "cinnamon"], 320, 8, 58, 6),
                ("Toast with Peanut Butter", ["whole wheat bread", "peanut butter", "banana"], 350, 12, 42, 16),
                ("Yogurt Parfait", ["greek yogurt", "granola", "berries"], 280, 15, 38, 8)
            ],
            .lunch: [
                ("Deli Turkey Sandwich", ["turkey", "whole wheat bread", "lettuce", "tomato", "mustard"], 320, 25, 35, 8),
                ("Quick Caprese Salad", ["mozzarella", "tomatoes", "basil", "balsamic"], 280, 18, 12, 18),
                ("Hummus Veggie Wrap", ["hummus", "whole wheat wrap", "cucumber", "tomato", "spinach"], 300, 12, 42, 10)
            ],
            .dinner: [
                ("Rotisserie Chicken Salad", ["rotisserie chicken", "mixed greens", "cherry tomatoes", "dressing"], 380, 35, 15, 20),
                ("Microwave Salmon & Rice", ["frozen salmon", "microwave rice", "steamed broccoli"], 420, 32, 40, 14),
                ("Bean & Cheese Quesadilla", ["tortilla", "black beans", "cheese", "salsa"], 380, 18, 45, 14)
            ],
            .snack: [
                ("String Cheese & Crackers", ["string cheese", "whole wheat crackers"], 180, 10, 18, 8),
                ("Trail Mix", ["mixed nuts", "dried fruit", "dark chocolate chips"], 200, 5, 22, 12),
                ("Apple Slices with Cheese", ["apple", "cheddar cheese"], 180, 8, 20, 8)
            ]
        ]

        let vegetarianMeals: [MealType: [(String, [String], Int, Int, Int, Int)]] = [
            .breakfast: [
                ("Veggie Scramble", ["eggs", "bell peppers", "onions", "mushrooms", "cheese"], 320, 20, 12, 22),
                ("Açaí Bowl", ["açaí puree", "banana", "granola", "berries", "coconut"], 380, 8, 65, 12),
                ("Avocado Toast Deluxe", ["whole grain bread", "avocado", "tomatoes", "feta", "eggs"], 400, 16, 35, 24)
            ],
            .lunch: [
                ("Falafel Bowl", ["falafel", "hummus", "tabbouleh", "cucumber", "tahini"], 450, 16, 52, 22),
                ("Caprese Panini", ["mozzarella", "tomato", "basil", "ciabatta", "pesto"], 420, 20, 40, 20),
                ("Black Bean Buddha Bowl", ["black beans", "quinoa", "roasted vegetables", "avocado"], 480, 18, 62, 18)
            ],
            .dinner: [
                ("Vegetable Stir Fry with Tofu", ["tofu", "broccoli", "bell peppers", "soy sauce", "rice"], 420, 22, 48, 16),
                ("Eggplant Parmesan", ["eggplant", "marinara", "mozzarella", "parmesan", "basil"], 380, 18, 32, 20),
                ("Mushroom Risotto", ["arborio rice", "mushrooms", "parmesan", "white wine", "vegetable broth"], 450, 14, 58, 16)
            ],
            .snack: [
                ("Edamame", ["edamame", "sea salt"], 180, 17, 14, 8),
                ("Hummus with Veggies", ["hummus", "carrots", "cucumber", "bell pepper"], 200, 8, 22, 10),
                ("Caprese Skewers", ["mozzarella balls", "cherry tomatoes", "basil", "balsamic glaze"], 180, 12, 8, 12)
            ]
        ]

        let asianMeals: [MealType: [(String, [String], Int, Int, Int, Int)]] = [
            .breakfast: [
                ("Japanese Breakfast Bowl", ["rice", "salmon", "miso soup", "pickled vegetables"], 380, 25, 45, 10),
                ("Congee with Egg", ["rice porridge", "soft boiled egg", "green onions", "ginger"], 280, 12, 42, 6),
                ("Tamagoyaki with Rice", ["eggs", "dashi", "rice", "nori", "pickles"], 350, 18, 40, 12)
            ],
            .lunch: [
                ("Teriyaki Chicken Bowl", ["chicken", "teriyaki sauce", "rice", "broccoli", "sesame"], 450, 35, 48, 12),
                ("Poke Bowl", ["ahi tuna", "sushi rice", "edamame", "cucumber", "avocado"], 420, 32, 45, 14),
                ("Pad Thai", ["rice noodles", "shrimp", "peanuts", "bean sprouts", "lime"], 480, 25, 55, 18)
            ],
            .dinner: [
                ("Korean BBQ Beef", ["bulgogi beef", "rice", "kimchi", "lettuce wraps"], 480, 35, 42, 18),
                ("Thai Basil Chicken", ["chicken", "thai basil", "chili", "garlic", "jasmine rice"], 420, 32, 45, 12),
                ("Salmon Teriyaki", ["salmon", "teriyaki glaze", "bok choy", "rice"], 450, 38, 40, 16)
            ],
            .snack: [
                ("Miso Soup", ["tofu", "wakame", "miso paste", "green onions"], 80, 6, 8, 2),
                ("Seaweed Snack", ["roasted seaweed", "sesame oil"], 60, 2, 4, 4),
                ("Gyoza (Dumplings)", ["pork", "cabbage", "wrapper", "soy sauce"], 220, 12, 24, 8)
            ]
        ]

        // Select fallbacks based on preference
        let loweredPref = preference.lowercased()
        var selectedFallbacks: [MealType: [(String, [String], Int, Int, Int, Int)]]

        if loweredPref.contains("protein") || loweredPref.contains("muscle") {
            selectedFallbacks = highProteinMeals
        } else if loweredPref.contains("low carb") || loweredPref.contains("keto") || loweredPref.contains("carb") {
            selectedFallbacks = lowCarbMeals
        } else if loweredPref.contains("quick") || loweredPref.contains("easy") || loweredPref.contains("fast") {
            selectedFallbacks = quickMeals
        } else if loweredPref.contains("vegetarian") || loweredPref.contains("veggie") || loweredPref.contains("meatless") {
            selectedFallbacks = vegetarianMeals
        } else if loweredPref.contains("asian") || loweredPref.contains("japanese") || loweredPref.contains("chinese") || loweredPref.contains("korean") || loweredPref.contains("thai") {
            selectedFallbacks = asianMeals
        } else {
            // Default mixed fallbacks
            let defaultFallbacks: [MealType: [(String, [String], Int, Int, Int, Int)]] = [
                .breakfast: [
                    ("Avocado Toast with Eggs", ["avocado", "eggs", "whole grain bread", "cherry tomatoes"], meal.calories, meal.protein, meal.carbs, meal.fat),
                    ("Protein Smoothie Bowl", ["protein powder", "banana", "berries", "granola"], meal.calories, meal.protein, meal.carbs, meal.fat),
                    ("Veggie Omelette", ["eggs", "spinach", "mushrooms", "feta cheese"], meal.calories, meal.protein, meal.carbs, meal.fat)
                ],
                .lunch: [
                    ("Mediterranean Quinoa Bowl", ["quinoa", "chickpeas", "cucumber", "feta", "olives"], meal.calories, meal.protein, meal.carbs, meal.fat),
                    ("Asian Chicken Salad", ["chicken breast", "mixed greens", "mandarin", "sesame dressing"], meal.calories, meal.protein, meal.carbs, meal.fat),
                    ("Turkey Avocado Wrap", ["turkey", "avocado", "whole wheat wrap", "lettuce"], meal.calories, meal.protein, meal.carbs, meal.fat)
                ],
                .dinner: [
                    ("Grilled Salmon with Vegetables", ["salmon", "asparagus", "lemon", "olive oil"], meal.calories, meal.protein, meal.carbs, meal.fat),
                    ("Chicken Stir Fry", ["chicken", "broccoli", "bell peppers", "brown rice"], meal.calories, meal.protein, meal.carbs, meal.fat),
                    ("Lean Beef Tacos", ["lean beef", "corn tortillas", "lettuce", "salsa"], meal.calories, meal.protein, meal.carbs, meal.fat)
                ],
                .snack: [
                    ("Greek Yogurt with Berries", ["greek yogurt", "mixed berries", "honey"], meal.calories, meal.protein, meal.carbs, meal.fat),
                    ("Apple with Almond Butter", ["apple", "almond butter"], meal.calories, meal.protein, meal.carbs, meal.fat),
                    ("Cottage Cheese & Fruit", ["cottage cheese", "pineapple", "walnuts"], meal.calories, meal.protein, meal.carbs, meal.fat)
                ]
            ]
            selectedFallbacks = defaultFallbacks
        }

        let options = selectedFallbacks[meal.type] ?? selectedFallbacks[.snack] ?? []
        return options.filter { $0.0 != meal.name }.map { option in
            PlannedMeal(
                type: meal.type,
                name: option.0,
                calories: option.2,
                protein: option.3,
                carbs: option.4,
                fat: option.5,
                ingredients: option.1
            )
        }
    }

    private func swapMeal(with newMeal: PlannedMeal) {
        // Update the meal in the database
        meal.name = newMeal.name
        meal.calories = newMeal.calories
        meal.protein = newMeal.protein
        meal.carbs = newMeal.carbs
        meal.fat = newMeal.fat
        meal.ingredients = newMeal.ingredients

        try? modelContext.save()
        showSwapSheet = false
    }

    // MARK: - Recipe Generation
    private func generateRecipeSteps(for meal: Meal) -> [String] {
        var steps: [String] = []
        let ingredients = meal.ingredients

        // Determine cooking method based on meal type and ingredients
        let hasProtein = ingredients.contains { ingredient in
            let lower = ingredient.name.lowercased()
            return lower.contains("chicken") || lower.contains("beef") || lower.contains("fish") ||
                   lower.contains("salmon") || lower.contains("turkey") || lower.contains("shrimp") ||
                   lower.contains("egg") || lower.contains("tofu")
        }

        let hasVegetables = ingredients.contains { ingredient in
            let lower = ingredient.name.lowercased()
            return lower.contains("spinach") || lower.contains("broccoli") || lower.contains("pepper") ||
                   lower.contains("tomato") || lower.contains("lettuce") || lower.contains("cucumber") ||
                   lower.contains("carrot") || lower.contains("asparagus") || lower.contains("zucchini")
        }

        let hasGrains = ingredients.contains { ingredient in
            let lower = ingredient.name.lowercased()
            return lower.contains("rice") || lower.contains("quinoa") || lower.contains("pasta") ||
                   lower.contains("bread") || lower.contains("oats") || lower.contains("tortilla")
        }

        // Step 1: Preparation
        let ingredientNames = ingredients.prefix(4).map { $0.displayString }
        steps.append("Gather all ingredients: \(ingredientNames.joined(separator: ", "))\(ingredients.count > 4 ? ", and more" : ""). Wash and prepare vegetables as needed.")

        // Step 2: Grains/Base (if applicable)
        if hasGrains {
            if ingredients.contains(where: { $0.name.lowercased().contains("rice") }) {
                steps.append("Cook rice according to package instructions. Set aside and keep warm.")
            } else if ingredients.contains(where: { $0.name.lowercased().contains("quinoa") }) {
                steps.append("Rinse quinoa and cook with 2 parts water for 15 minutes until fluffy.")
            } else if ingredients.contains(where: { $0.name.lowercased().contains("pasta") }) {
                steps.append("Bring a large pot of salted water to boil. Cook pasta until al dente, then drain.")
            } else if ingredients.contains(where: { $0.name.lowercased().contains("oats") }) {
                steps.append("Combine oats with milk or water and cook on medium heat, stirring occasionally.")
            }
        }

        // Step 3: Protein (if applicable)
        if hasProtein {
            if ingredients.contains(where: { $0.name.lowercased().contains("chicken") }) {
                steps.append("Season chicken with salt and pepper. Cook in a heated pan with a little oil for 6-7 minutes per side until golden and cooked through.")
            } else if ingredients.contains(where: { $0.name.lowercased().contains("salmon") || $0.name.lowercased().contains("fish") }) {
                steps.append("Pat fish dry and season. Cook skin-side down in a hot pan for 4 minutes, flip and cook 2-3 more minutes.")
            } else if ingredients.contains(where: { $0.name.lowercased().contains("egg") }) {
                steps.append("Crack eggs into a bowl. Cook in a non-stick pan over medium heat, stirring gently for scrambled or leaving undisturbed for fried.")
            } else if ingredients.contains(where: { $0.name.lowercased().contains("beef") || $0.name.lowercased().contains("turkey") }) {
                steps.append("Brown the meat in a heated pan, breaking it up as it cooks. Season with your preferred spices.")
            }
        }

        // Step 4: Vegetables
        if hasVegetables {
            steps.append("Saut\u{00E9} or roast vegetables until tender-crisp. Season with salt, pepper, and a drizzle of olive oil.")
        }

        // Step 5: Assembly
        switch meal.type {
        case .breakfast:
            steps.append("Plate your breakfast while warm. Add any fresh toppings and serve immediately.")
        case .brunch:
            steps.append("Arrange your brunch spread elegantly. Combine sweet and savory elements for a balanced meal.")
        case .lunch:
            steps.append("Arrange all components in a bowl or on a plate. Drizzle with dressing or sauce if desired.")
        case .dinner:
            steps.append("Plate the protein alongside your grains and vegetables. Garnish with fresh herbs if available.")
        case .snack:
            steps.append("Combine ingredients in a bowl or container. Best enjoyed fresh or chilled.")
        }

        // Final step: Enjoy
        steps.append("Serve and enjoy your nutritious \(meal.type.rawValue.lowercased())!")

        return steps
    }
}

// MARK: - Supporting Views

struct QuickStatPill: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
            Text(value)
                .fontWeight(.semibold)
            Text(label)
                .font(.caption)
                .opacity(0.8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.15))
        .cornerRadius(20)
    }
}

struct SectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.blue)

            Text(title)
                .font(.headline)
        }
    }
}

struct NutritionCard: View {
    let value: Int
    let unit: String
    let label: String
    let color: Color
    let icon: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)

            HStack(spacing: 2) {
                Text("\(value)")
                    .font(.headline)
                    .fontWeight(.bold)
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
}

struct IngredientRow: View {
    let ingredient: MealIngredient
    let isLast: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(ingredient.name.capitalized)
                        .font(.subheadline)

                    if !ingredient.quantity.isEmpty {
                        Text(ingredient.quantity)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "checkmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(.green)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            if !isLast {
                Divider()
                    .padding(.leading, 36)
            }
        }
    }
}

struct RecipeStepRow: View {
    let stepNumber: Int
    let instruction: String
    let isLast: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Text("\(stepNumber)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Color.blue)
                    .clipShape(Circle())

                Text(instruction)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            if !isLast {
                Divider()
                    .padding(.leading, 52)
            }
        }
    }
}

// MARK: - Meal Swap Sheet
struct MealSwapSheet: View {
    @Environment(\.dismiss) private var dismiss

    let originalMeal: Meal
    let alternatives: [PlannedMeal]
    let isLoading: Bool
    let onSelect: (PlannedMeal) -> Void
    let onRegenerate: (String) -> Void
    var accentColor: Color = .purple

    @State private var userPreference: String = ""
    @State private var selectedPrepTime: PrepTimeFilter = .any
    @State private var selectedDifficulty: DifficultyFilter = .any
    @FocusState private var isTextFieldFocused: Bool

    // Observe model manager status for loading feedback
    private var modelStatus: String {
        ModelManager.shared.status
    }

    private var isModelLoading: Bool {
        modelStatus.contains("Downloading") || modelStatus.contains("Loading")
    }

    // Quick suggestion chips
    private let quickSuggestions = [
        ("High Protein", "bolt.fill"),
        ("Low Carb", "leaf.fill"),
        ("Vegetarian", "carrot.fill")
    ]

    enum PrepTimeFilter: String, CaseIterable {
        case any = "Any Time"
        case quick = "<15 min"
        case medium = "15-30 min"

        var icon: String {
            switch self {
            case .any: return "clock"
            case .quick: return "bolt.fill"
            case .medium: return "clock.fill"
            }
        }
    }

    enum DifficultyFilter: String, CaseIterable {
        case any = "Any Level"
        case easy = "Easy"
        case medium = "Medium"

        var icon: String {
            switch self {
            case .any: return "chart.bar"
            case .easy: return "leaf.fill"
            case .medium: return "flame.fill"
            }
        }
    }

    // Build the full preference string including filters
    private var fullPreference: String {
        var parts: [String] = []
        if !userPreference.isEmpty {
            parts.append(userPreference)
        }
        if selectedPrepTime != .any {
            parts.append(selectedPrepTime == .quick ? "quick prep under 15 minutes" : "prep time 15-30 minutes")
        }
        if selectedDifficulty != .any {
            parts.append("\(selectedDifficulty.rawValue.lowercased()) difficulty")
        }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 40))
                            .foregroundStyle(accentColor)

                        Text("Swap Meal")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("What are you in the mood for?")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 20)

                    // User preference input
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "sparkles")
                                .foregroundStyle(accentColor)
                            TextField("e.g., something Asian with more protein...", text: $userPreference)
                                .textFieldStyle(.plain)
                                .focused($isTextFieldFocused)
                                .submitLabel(.search)
                                .onSubmit {
                                    if !userPreference.isEmpty {
                                        onRegenerate(userPreference)
                                    }
                                }
                        }
                        .padding()
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .cornerRadius(12)

                        // Quick suggestion chips
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(quickSuggestions, id: \.0) { suggestion in
                                    QuickSuggestionChip(
                                        title: suggestion.0,
                                        icon: suggestion.1,
                                        isSelected: userPreference == suggestion.0,
                                        accentColor: accentColor
                                    ) {
                                        userPreference = suggestion.0
                                    }
                                }
                            }
                        }

                        // Prep time filter
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Prep Time")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            HStack(spacing: 8) {
                                ForEach(PrepTimeFilter.allCases, id: \.self) { filter in
                                    FilterChip(
                                        title: filter.rawValue,
                                        icon: filter.icon,
                                        isSelected: selectedPrepTime == filter,
                                        accentColor: accentColor
                                    ) {
                                        selectedPrepTime = filter
                                    }
                                }
                            }
                        }

                        // Difficulty filter
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Difficulty")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            HStack(spacing: 8) {
                                ForEach(DifficultyFilter.allCases, id: \.self) { filter in
                                    FilterChip(
                                        title: filter.rawValue,
                                        icon: filter.icon,
                                        isSelected: selectedDifficulty == filter,
                                        accentColor: accentColor
                                    ) {
                                        selectedDifficulty = filter
                                    }
                                }
                            }
                        }

                        // Search button
                        Button {
                            onRegenerate(fullPreference)
                        } label: {
                            HStack {
                                Image(systemName: "sparkles")
                                Text("Find Alternatives")
                            }
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(accentColor)
                            .foregroundStyle(.white)
                            .cornerRadius(10)
                        }
                        .disabled(isLoading)
                    }

                    Divider()
                        .padding(.vertical, 4)

                    // Current meal being replaced
                    HStack {
                        Text("Replacing:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(originalMeal.name)
                            .font(.caption)
                            .fontWeight(.medium)
                        Spacer()
                        Text("\(originalMeal.calories) kcal")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(uiColor: .tertiarySystemGroupedBackground))
                    .cornerRadius(8)

                    // Loading / Empty / Results
                    if isLoading {
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.2)

                            if isModelLoading {
                                // Show model loading status
                                VStack(spacing: 8) {
                                    Text(modelStatus)
                                        .font(.subheadline)
                                        .fontWeight(.medium)

                                    Text("First-time setup - this only happens once")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                Text(userPreference.isEmpty ? "Generating alternatives..." : "Finding \"\(userPreference)\" options...")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else if alternatives.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "fork.knife.circle")
                                .font(.system(size: 50))
                                .foregroundStyle(.secondary)

                            Text("No alternatives found")
                                .font(.headline)

                            Text("Try a different preference or tap a chip above")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                    } else {
                        VStack(spacing: 12) {
                            Text("Alternatives")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            ForEach(alternatives) { alternative in
                                AlternativeMealCard(
                                    meal: alternative,
                                    originalCalories: originalMeal.calories
                                ) {
                                    onSelect(alternative)
                                }
                            }

                            Button {
                                onRegenerate(fullPreference)
                            } label: {
                                HStack {
                                    Image(systemName: "arrow.clockwise")
                                    Text("Generate More Options")
                                }
                                .font(.subheadline)
                                .foregroundStyle(.blue)
                            }
                            .padding(.top, 8)
                        }
                    }
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
            .keyboardDismissToolbar()
            .onTapGesture {
                isTextFieldFocused = false
            }
        }
    }
}

// MARK: - Filter Chip
struct FilterChip: View {
    let title: String
    let icon: String
    let isSelected: Bool
    var accentColor: Color = .purple
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? accentColor : Color(uiColor: .secondarySystemGroupedBackground))
            .foregroundStyle(isSelected ? .white : .primary)
            .cornerRadius(16)
        }
    }
}

// MARK: - Quick Suggestion Chip
struct QuickSuggestionChip: View {
    let title: String
    let icon: String
    let isSelected: Bool
    var accentColor: Color = .purple
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? accentColor : Color(uiColor: .secondarySystemGroupedBackground))
            .foregroundStyle(isSelected ? .white : .primary)
            .cornerRadius(20)
        }
    }
}

struct AlternativeMealCard: View {
    let meal: PlannedMeal
    let originalCalories: Int
    let onSelect: () -> Void

    private var calorieDiff: Int {
        meal.calories - originalCalories
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(meal.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)

                        HStack(spacing: 8) {
                            Text("\(meal.calories) kcal")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            if calorieDiff != 0 {
                                Text(calorieDiff > 0 ? "+\(calorieDiff)" : "\(calorieDiff)")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(calorieDiff > 0 ? .orange : .green)
                            }
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)
                }

                // Macro pills
                HStack(spacing: 8) {
                    MacroPill(value: meal.protein, label: "P", color: .red)
                    MacroPill(value: meal.carbs, label: "C", color: .blue)
                    MacroPill(value: meal.fat, label: "F", color: .yellow)
                }

                // Ingredients preview
                Text(meal.ingredients.prefix(4).map { $0.displayString }.joined(separator: " \u{2022} "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding()
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Macro Ring View
struct MacroRingView: View {
    let value: Int
    let target: Int
    let label: String
    let unit: String
    let color: Color

    private var progress: Double {
        guard target > 0 else { return 0 }
        return min(Double(value) / Double(target), 1.0)
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                // Background ring
                Circle()
                    .stroke(color.opacity(0.2), lineWidth: 8)

                // Progress ring
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.6), value: progress)

                // Value text
                Text("\(value)")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
            }
            .frame(width: 70, height: 70)

            VStack(spacing: 2) {
                Text(label)
                    .font(.caption)
                    .fontWeight(.medium)

                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - AI Action Button
struct AIActionButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)

                VStack(spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - How to Prep Sheet
struct HowToPrepSheet: View {
    @Environment(\.dismiss) private var dismiss
    let meal: Meal
    let steps: [String]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text(meal.name)
                            .font(.title2)
                            .fontWeight(.bold)

                        HStack(spacing: 16) {
                            Label("\(meal.prepTimeMinutes) min", systemImage: "clock.fill")
                            Label(meal.difficulty.rawValue, systemImage: "chef.hat.fill")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)

                    Divider()
                        .padding(.horizontal)

                    // Steps
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                            HStack(alignment: .top, spacing: 16) {
                                Text("\(index + 1)")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                    .frame(width: 32, height: 32)
                                    .background(Color.blue)
                                    .clipShape(Circle())

                                Text(step)
                                    .font(.body)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 12)

                            if index < steps.count - 1 {
                                Rectangle()
                                    .fill(Color.blue.opacity(0.3))
                                    .frame(width: 2, height: 20)
                                    .padding(.leading, 31)
                            }
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("How to Prep")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Adjust Calories Sheet
struct AdjustCaloriesSheet: View {
    @Environment(\.dismiss) private var dismiss
    let meal: Meal
    let onApply: (PlannedMeal) -> Void

    @State private var adjustment: CalorieAdjustment = .same
    @State private var isGenerating = false

    enum CalorieAdjustment: String, CaseIterable {
        case lighter = "Lighter (-200 kcal)"
        case same = "Same calories"
        case heavier = "Heavier (+200 kcal)"

        var calorieChange: Int {
            switch self {
            case .lighter: return -200
            case .same: return 0
            case .heavier: return 200
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Current meal info
                VStack(spacing: 8) {
                    Text(meal.name)
                        .font(.headline)

                    Text("\(meal.calories) kcal")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(.orange)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .cornerRadius(12)

                // Adjustment options
                VStack(spacing: 12) {
                    ForEach(CalorieAdjustment.allCases, id: \.self) { option in
                        Button {
                            adjustment = option
                        } label: {
                            HStack {
                                Text(option.rawValue)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if adjustment == option {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.blue)
                                }
                            }
                            .padding()
                            .background(adjustment == option ? Color.blue.opacity(0.1) : Color(uiColor: .secondarySystemGroupedBackground))
                            .cornerRadius(12)
                        }
                    }
                }

                Spacer()

                // Apply button
                Button {
                    applyAdjustment()
                } label: {
                    if isGenerating {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Apply Changes")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isGenerating || adjustment == .same)
            }
            .padding()
            .navigationTitle("Adjust Calories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func applyAdjustment() {
        let newCalories = max(100, meal.calories + adjustment.calorieChange)
        let ratio = Double(newCalories) / Double(meal.calories)

        let adjustedMeal = PlannedMeal(
            type: meal.type,
            name: meal.name + (adjustment == .lighter ? " (Light)" : " (Hearty)"),
            calories: newCalories,
            protein: Int(Double(meal.protein) * ratio),
            carbs: Int(Double(meal.carbs) * ratio),
            fat: Int(Double(meal.fat) * ratio),
            structuredIngredients: meal.ingredients
        )

        onApply(adjustedMeal)
        dismiss()
    }
}

// MARK: - Use Ingredients Sheet
struct UseIngredientsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let meal: Meal
    let onGenerate: (PlannedMeal) -> Void
    var accentColor: Color = .green

    @State private var ingredientText = ""
    @State private var isGenerating = false
    @State private var selectedPrepTime: PrepTimeOption = .any
    @State private var selectedDifficulty: DifficultyOption = .any
    @FocusState private var isTextFieldFocused: Bool

    enum PrepTimeOption: String, CaseIterable {
        case any = "Any Time"
        case quick = "<15 min"
        case medium = "15-30 min"

        var icon: String {
            switch self {
            case .any: return "clock"
            case .quick: return "bolt.fill"
            case .medium: return "clock.fill"
            }
        }

        var maxMinutes: Int? {
            switch self {
            case .any: return nil
            case .quick: return 15
            case .medium: return 30
            }
        }
    }

    enum DifficultyOption: String, CaseIterable {
        case any = "Any Level"
        case easy = "Easy"
        case medium = "Medium"

        var icon: String {
            switch self {
            case .any: return "chart.bar"
            case .easy: return "leaf.fill"
            case .medium: return "flame.fill"
            }
        }

        var difficulty: MealDifficulty? {
            switch self {
            case .any: return nil
            case .easy: return .easy
            case .medium: return .medium
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Instructions
                    VStack(alignment: .leading, spacing: 8) {
                        Text("What ingredients do you have?")
                            .font(.headline)

                        Text("Enter ingredients you'd like to use and we'll generate a meal suggestion.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Text input
                    TextField("e.g., chicken, broccoli, rice...", text: $ingredientText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .padding()
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .cornerRadius(12)
                        .lineLimit(3...6)
                        .focused($isTextFieldFocused)

                    // Quick ingredient chips
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Quick add:")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(["Chicken", "Rice", "Eggs", "Vegetables", "Pasta", "Fish"], id: \.self) { ingredient in
                                    Button {
                                        if ingredientText.isEmpty {
                                            ingredientText = ingredient
                                        } else {
                                            ingredientText += ", " + ingredient
                                        }
                                    } label: {
                                        Text(ingredient)
                                            .font(.caption)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(Color(uiColor: .tertiarySystemGroupedBackground))
                                            .cornerRadius(16)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    // Prep time filter
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Prep Time")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            ForEach(PrepTimeOption.allCases, id: \.self) { option in
                                FilterChip(
                                    title: option.rawValue,
                                    icon: option.icon,
                                    isSelected: selectedPrepTime == option,
                                    accentColor: accentColor
                                ) {
                                    selectedPrepTime = option
                                }
                            }
                        }
                    }

                    // Difficulty filter
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Difficulty")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            ForEach(DifficultyOption.allCases, id: \.self) { option in
                                FilterChip(
                                    title: option.rawValue,
                                    icon: option.icon,
                                    isSelected: selectedDifficulty == option,
                                    accentColor: accentColor
                                ) {
                                    selectedDifficulty = option
                                }
                            }
                        }
                    }

                    Spacer(minLength: 20)

                    // Generate button
                    Button {
                        generateMeal()
                    } label: {
                        if isGenerating {
                            ProgressView()
                                .tint(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        } else {
                            HStack {
                                Image(systemName: "sparkles")
                                Text("Generate Meal")
                            }
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                        }
                    }
                    .background(ingredientText.isEmpty || isGenerating ? accentColor.opacity(0.5) : accentColor)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
                    .disabled(ingredientText.isEmpty || isGenerating)
                }
                .padding()
            }
            .navigationTitle("Use Ingredients")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .keyboardDismissToolbar()
            .onTapGesture {
                isTextFieldFocused = false
            }
        }
    }

    private func generateMeal() {
        isGenerating = true

        // Parse ingredients
        let ingredients = ingredientText
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }

        // Determine prep time based on selection
        let prepTime: Int
        switch selectedPrepTime {
        case .quick:
            prepTime = Int.random(in: 8...15)
        case .medium:
            prepTime = Int.random(in: 16...30)
        case .any:
            prepTime = meal.prepTimeMinutes
        }

        // Determine difficulty
        let difficulty = selectedDifficulty.difficulty ?? meal.difficulty

        // Generate meal name with preference hints
        let mealName = generateMealName(from: ingredients, type: meal.type, prepTime: prepTime, difficulty: difficulty)

        let newMeal = PlannedMeal(
            type: meal.type,
            name: mealName,
            calories: meal.calories,
            protein: meal.protein,
            carbs: meal.carbs,
            fat: meal.fat,
            ingredients: ingredients,
            prepTimeMinutes: prepTime,
            difficulty: difficulty
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            onGenerate(newMeal)
            dismiss()
        }
    }

    private func generateMealName(from ingredients: [String], type: MealType, prepTime: Int, difficulty: MealDifficulty) -> String {
        let mainIngredient = ingredients.first?.capitalized ?? "Mixed"

        // Add prep hint to name if quick
        let quickPrefix = prepTime <= 15 ? "Quick " : ""
        let easyPrefix = difficulty == .easy ? "Easy " : ""
        let prefix = quickPrefix.isEmpty ? easyPrefix : quickPrefix

        switch type {
        case .breakfast:
            return "\(prefix)\(mainIngredient) Breakfast Bowl"
        case .brunch:
            return "\(prefix)\(mainIngredient) Brunch Delight"
        case .lunch:
            return "\(prefix)\(mainIngredient) Power Bowl"
        case .dinner:
            return "\(prefix)Homestyle \(mainIngredient) Dinner"
        case .snack:
            return "\(prefix)\(mainIngredient) Snack Plate"
        }
    }
}

// MARK: - Quick Prep Sheet
struct QuickPrepSheet: View {
    @Environment(\.dismiss) private var dismiss
    let meal: Meal
    let onSelect: (PlannedMeal) -> Void

    private var quickMeals: [PlannedMeal] {
        generateQuickMeals(for: meal.type, targetCalories: meal.calories)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.blue)

                        Text("Quick Prep Options")
                            .font(.title3)
                            .fontWeight(.bold)

                        Text("Meals under 15 minutes")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top)

                    // Quick meal options
                    ForEach(quickMeals) { quickMeal in
                        Button {
                            onSelect(quickMeal)
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(quickMeal.name)
                                        .font(.headline)
                                        .foregroundStyle(.primary)

                                    HStack(spacing: 12) {
                                        Label("\(quickMeal.calories) kcal", systemImage: "flame.fill")
                                        Label("<15 min", systemImage: "clock.fill")
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                            .background(Color(uiColor: .secondarySystemGroupedBackground))
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle("Quick Prep")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func generateQuickMeals(for type: MealType, targetCalories: Int) -> [PlannedMeal] {
        let quickOptions: [MealType: [(String, [String], Int, Int, Int, Int)]] = [
            .breakfast: [
                ("Overnight Oats", ["oats", "milk", "honey", "berries"], 320, 12, 52, 8),
                ("Yogurt Parfait", ["greek yogurt", "granola", "fruit"], 280, 18, 35, 8),
                ("Toast with Avocado", ["bread", "avocado", "egg", "salt"], 350, 14, 28, 22)
            ],
            .lunch: [
                ("Turkey Wrap", ["turkey", "tortilla", "lettuce", "cheese"], 380, 28, 32, 14),
                ("Caprese Salad", ["mozzarella", "tomatoes", "basil", "olive oil"], 320, 18, 12, 22),
                ("Tuna Salad", ["canned tuna", "mayo", "celery", "crackers"], 340, 30, 20, 16)
            ],
            .dinner: [
                ("Stir Fry (Frozen)", ["frozen stir fry mix", "soy sauce", "rice"], 420, 15, 55, 14),
                ("Sheet Pan Salmon", ["salmon fillet", "asparagus", "lemon"], 450, 38, 8, 28),
                ("Quesadilla", ["tortilla", "cheese", "chicken", "salsa"], 480, 32, 35, 22)
            ],
            .snack: [
                ("Cheese & Crackers", ["cheese", "crackers"], 200, 10, 18, 12),
                ("Apple & Peanut Butter", ["apple", "peanut butter"], 250, 6, 32, 14),
                ("Trail Mix", ["nuts", "dried fruit"], 220, 6, 24, 14)
            ]
        ]

        let options = quickOptions[type] ?? quickOptions[.snack] ?? []
        return options.map { option in
            PlannedMeal(
                type: type,
                name: option.0,
                calories: option.2,
                protein: option.3,
                carbs: option.4,
                fat: option.5,
                ingredients: option.1
            )
        }
    }
}

// MARK: - Edit Meal Sheet
struct EditMealSheet: View {
    @Environment(\.dismiss) private var dismiss
    let meal: Meal
    let onSave: (PlannedMeal) -> Void

    @State private var name: String = ""
    @State private var calories: String = ""
    @State private var protein: String = ""
    @State private var carbs: String = ""
    @State private var fat: String = ""
    @State private var ingredientsText: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Meal Info") {
                    TextField("Name", text: $name)

                    HStack {
                        Text("Calories")
                        Spacer()
                        TextField("0", text: $calories)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("kcal")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Macros") {
                    HStack {
                        Text("Protein")
                        Spacer()
                        TextField("0", text: $protein)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        Text("g")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Carbs")
                        Spacer()
                        TextField("0", text: $carbs)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        Text("g")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Fat")
                        Spacer()
                        TextField("0", text: $fat)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        Text("g")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Ingredients") {
                    TextField("Comma-separated list", text: $ingredientsText, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Edit Meal")
            .navigationBarTitleDisplayMode(.inline)
            .formKeyboardDismissible()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveMeal()
                    }
                    .disabled(name.isEmpty)
                }
            }
            .onAppear {
                name = meal.name
                calories = "\(meal.calories)"
                protein = "\(meal.protein)"
                carbs = "\(meal.carbs)"
                fat = "\(meal.fat)"
                ingredientsText = meal.ingredientStrings.joined(separator: ", ")
            }
        }
    }

    private func saveMeal() {
        let ingredients = ingredientsText
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let updatedMeal = PlannedMeal(
            type: meal.type,
            name: name,
            calories: Int(calories) ?? meal.calories,
            protein: Int(protein) ?? meal.protein,
            carbs: Int(carbs) ?? meal.carbs,
            fat: Int(fat) ?? meal.fat,
            ingredients: ingredients
        )

        onSave(updatedMeal)
        dismiss()
    }
}

