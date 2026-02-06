import SwiftUI
import SwiftData

// MARK: - Brand Colors
private enum BrandColors {
    static let primaryOrange = Color(red: 0.98, green: 0.65, blue: 0.35)
    static let deepOrange = Color(red: 0.92, green: 0.45, blue: 0.25)
    static let warmOrange = Color(red: 0.96, green: 0.55, blue: 0.30)

    static var gradient: LinearGradient {
        LinearGradient(
            colors: [primaryOrange, deepOrange],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - DietAI Icon (reusable brand icon)
struct DietAIIcon: View {
    var size: CGFloat = 160
    var showBackground: Bool = true

    var body: some View {
        ZStack {
            if showBackground {
                // Glow background
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [BrandColors.primaryOrange.opacity(0.3), BrandColors.primaryOrange.opacity(0)],
                            center: .center,
                            startRadius: size * 0.2,
                            endRadius: size * 0.6
                        )
                    )
                    .frame(width: size * 1.2, height: size * 1.2)

                // Main circle
                Circle()
                    .fill(BrandColors.gradient)
                    .frame(width: size, height: size)
                    .shadow(color: BrandColors.deepOrange.opacity(0.3), radius: 20, y: 10)
            }

            // Icon content
            ZStack {
                // Leaf shape
                Image(systemName: "leaf.fill")
                    .font(.system(size: size * 0.35, weight: .medium))
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(-15))
                    .offset(x: -size * 0.03, y: size * 0.03)
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 4)

                // AI sparkles
                Image(systemName: "sparkles")
                    .font(.system(size: size * 0.18, weight: .bold))
                    .foregroundStyle(.white)
                    .offset(x: size * 0.18, y: -size * 0.14)
                    .shadow(color: .white.opacity(0.5), radius: 6)
            }
        }
    }
}

// MARK: - New Onboarding Flow (4 screens)
struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @State private var currentStep = 0
    @State private var userProfile = OnboardingData()
    @State private var healthProfileData: HealthProfileData?

    var onComplete: () -> Void

    private let totalSteps = 4

    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator
            ProgressBar(progress: Double(currentStep + 1) / Double(totalSteps))
                .padding(.horizontal)
                .padding(.top)

            // Content
            TabView(selection: $currentStep) {
                WelcomeStep(onNext: nextStep)
                    .tag(0)

                BenefitsStep(onNext: nextStep, onBack: previousStep)
                    .tag(1)

                // HealthKit now comes before Profile Setup to pre-fill data
                HealthKitStep(
                    onComplete: { profileData in
                        healthProfileData = profileData
                        nextStep()
                    },
                    onBack: previousStep,
                    onSkip: nextStep
                )
                .tag(2)

                ProfileSetupStep(
                    data: $userProfile,
                    healthProfileData: healthProfileData,
                    onNext: completeOnboarding,
                    onBack: previousStep
                )
                .tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: currentStep)
        }
        .interactiveDismissDisabled()
    }

    private func nextStep() {
        withAnimation {
            currentStep = min(currentStep + 1, totalSteps - 1)
        }
    }

    private func previousStep() {
        withAnimation {
            currentStep = max(currentStep - 1, 0)
        }
    }

    private func completeOnboarding() {
        // Create and save user profile
        let profile = UserProfile()
        profile.activityLevel = userProfile.activityLevel
        profile.height = userProfile.height
        profile.weight = userProfile.weight
        profile.age = userProfile.age
        profile.dailyCalorieTarget = userProfile.calculatedCalories
        profile.hasCompletedOnboarding = true

        context.insert(profile)
        try? context.save()

        onComplete()
    }
}

// MARK: - Onboarding Data
struct OnboardingData {
    var activityLevel: ActivityLevel = .moderatelyActive
    var height: Double?
    var weight: Double?
    var age: Int?

    var calculatedCalories: Int? {
        guard let h = height, let w = weight, let a = age else { return nil }
        // Mifflin-St Jeor equation (male formula as default, could be personalized)
        let bmr = 10 * w + 6.25 * h - 5 * Double(a) + 5
        let tdee = bmr * activityLevel.multiplier
        return Int(tdee)
    }
}

// MARK: - Progress Bar
struct ProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(BrandColors.primaryOrange.opacity(0.2))

                Capsule()
                    .fill(BrandColors.gradient)
                    .frame(width: geo.size.width * progress)
                    .animation(.spring(response: 0.4), value: progress)
            }
        }
        .frame(height: 6)
    }
}

// MARK: - Step 1: Welcome
struct WelcomeStep: View {
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // App icon - DietAI brand icon
            DietAIIcon(size: 160, showBackground: true)

            VStack(spacing: 12) {
                Text("Welcome to DietAI")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Your personal AI nutrition coach that creates meal plans just for you.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()
            Spacer()

            Button(action: onNext) {
                Text("Get Started")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(BrandColors.gradient)
                    .foregroundStyle(.white)
                    .cornerRadius(14)
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
    }
}

// MARK: - Step 2: Benefits
struct BenefitsStep: View {
    let onNext: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Benefits list
            VStack(alignment: .leading, spacing: 24) {
                BenefitRow(
                    icon: "wand.and.stars",
                    color: .purple,
                    title: "Personalized Plans",
                    description: "AI creates meals based on your goals, preferences, and schedule"
                )

                BenefitRow(
                    icon: "applewatch",
                    color: .red,
                    title: "Activity-Aware",
                    description: "Syncs with Apple Health to adjust calories based on your workouts"
                )

                BenefitRow(
                    icon: "cart.fill",
                    color: .green,
                    title: "Smart Shopping",
                    description: "Auto-generated shopping lists from your meal plan"
                )

                BenefitRow(
                    icon: "clock.fill",
                    color: .orange,
                    title: "Easy Prep",
                    description: "Simple recipes with prep time and cooking instructions"
                )
            }
            .padding(.horizontal, 24)

            Spacer()

            // Navigation
            HStack(spacing: 16) {
                Button(action: onBack) {
                    HStack {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .foregroundStyle(.primary)
                    .cornerRadius(14)
                }

                Button(action: onNext) {
                    HStack {
                        Text("Continue")
                        Image(systemName: "chevron.right")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(BrandColors.gradient)
                    .foregroundStyle(.white)
                    .cornerRadius(14)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
    }
}

struct BenefitRow: View {
    let icon: String
    let color: Color
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 50, height: 50)
                .background(color)
                .cornerRadius(12)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Step 4: Profile Setup (now after HealthKit)
struct ProfileSetupStep: View {
    @Binding var data: OnboardingData
    var healthProfileData: HealthProfileData?
    let onNext: () -> Void
    let onBack: () -> Void

    @State private var heightText = ""
    @State private var weightText = ""
    @State private var ageText = ""
    @State private var hasPrefilledFromHealth = false

    var isValid: Bool {
        data.height != nil && data.weight != nil && data.age != nil
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Text("Tell us about yourself")
                        .font(.title)
                        .fontWeight(.bold)

                    Text("For accurate calorie targets")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 40)

                // Form
                VStack(spacing: 20) {
                    OnboardingTextField(
                        title: "Height",
                        placeholder: "170",
                        suffix: "cm",
                        text: $heightText,
                        keyboardType: .numberPad
                    )
                    .onChange(of: heightText) { _, newValue in
                        data.height = Double(newValue)
                    }

                    OnboardingTextField(
                        title: "Weight",
                        placeholder: "70",
                        suffix: "kg",
                        text: $weightText,
                        keyboardType: .decimalPad
                    )
                    .onChange(of: weightText) { _, newValue in
                        data.weight = Double(newValue)
                    }

                    OnboardingTextField(
                        title: "Age",
                        placeholder: "30",
                        suffix: "years",
                        text: $ageText,
                        keyboardType: .numberPad
                    )
                    .onChange(of: ageText) { _, newValue in
                        data.age = Int(newValue)
                    }

                    // Activity level picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Activity Level")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        VStack(spacing: 8) {
                            ForEach(ActivityLevel.allCases, id: \.self) { level in
                                ActivityLevelButton(
                                    level: level,
                                    isSelected: data.activityLevel == level,
                                    onSelect: { data.activityLevel = level }
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal)

                Spacer(minLength: 100)
            }
        }
        .keyboardDismissible()
        .safeAreaInset(edge: .bottom) {
            // Navigation
            HStack(spacing: 16) {
                Button(action: onBack) {
                    HStack {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .foregroundStyle(.primary)
                    .cornerRadius(14)
                }

                Button(action: onNext) {
                    HStack {
                        Text("Continue")
                        Image(systemName: "chevron.right")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isValid ? BrandColors.gradient : LinearGradient(colors: [.gray], startPoint: .leading, endPoint: .trailing))
                    .foregroundStyle(.white)
                    .cornerRadius(14)
                }
                .disabled(!isValid)
            }
            .padding(.horizontal)
            .padding(.vertical, 16)
            .background(.ultraThinMaterial)
        }
        .onAppear {
            prefillFromHealthData()
        }
    }

    private func prefillFromHealthData() {
        guard !hasPrefilledFromHealth, let healthData = healthProfileData else { return }
        hasPrefilledFromHealth = true

        // Pre-fill height from HealthKit
        if let height = healthData.height {
            let heightInt = Int(height)
            heightText = "\(heightInt)"
            data.height = height
        }

        // Pre-fill weight from HealthKit
        if let weight = healthData.weight {
            weightText = String(format: "%.1f", weight)
            data.weight = weight
        }

        // Pre-fill age from HealthKit
        if let age = healthData.age {
            ageText = "\(age)"
            data.age = age
        }
    }
}

struct ActivityLevelButton: View {
    let level: ActivityLevel
    let isSelected: Bool
    let onSelect: () -> Void

    private var description: String {
        switch level {
        case .sedentary: return "Little or no exercise"
        case .lightlyActive: return "Light exercise 1-3 days/week"
        case .moderatelyActive: return "Moderate exercise 3-5 days/week"
        case .veryActive: return "Hard exercise 6-7 days/week"
        case .extraActive: return "Very hard exercise + physical job"
        }
    }

    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(level.rawValue)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? BrandColors.primaryOrange : .secondary)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? BrandColors.primaryOrange : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

struct OnboardingTextField: View {
    let title: String
    let placeholder: String
    let suffix: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                TextField(placeholder, text: $text)
                    .keyboardType(keyboardType)
                    .font(.title3)

                Text(suffix)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .cornerRadius(12)
        }
    }
}

// MARK: - Step 3: HealthKit Permission (now before Profile Setup)
struct HealthKitStep: View {
    let onComplete: (HealthProfileData?) -> Void
    let onBack: () -> Void
    let onSkip: () -> Void

    @State private var isRequesting = false
    @State private var isConnected = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Heart icon with brand accent
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [BrandColors.primaryOrange.opacity(0.2), BrandColors.primaryOrange.opacity(0)],
                            center: .center,
                            startRadius: 30,
                            endRadius: 80
                        )
                    )
                    .frame(width: 160, height: 160)

                Circle()
                    .fill(Color.red.opacity(0.15))
                    .frame(width: 140, height: 140)

                Image(systemName: "heart.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.red)
            }

            VStack(spacing: 12) {
                Text("Sync with Apple Health?")
                    .font(.title)
                    .fontWeight(.bold)

                Text("We'll import your height, weight, and age to save you time, plus track your workouts for smarter meal plans.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            // Benefits of connecting
            VStack(alignment: .leading, spacing: 12) {
                HealthBenefitRow(icon: "person.fill", text: "Auto-fill your profile data")
                HealthBenefitRow(icon: "flame.fill", text: "Track calories burned from workouts")
                HealthBenefitRow(icon: "figure.walk", text: "Activity-aware meal recommendations")
            }
            .padding(.horizontal, 32)

            Spacer()

            // Buttons
            VStack(spacing: 12) {
                Button(action: requestHealthKit) {
                    HStack {
                        if isRequesting {
                            ProgressView()
                                .tint(.white)
                        } else if isConnected {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Connected!")
                        } else {
                            Image(systemName: "heart.fill")
                            Text("Allow Health Access")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isConnected ? Color.green : Color.red)
                    .foregroundStyle(.white)
                    .cornerRadius(14)
                }
                .disabled(isRequesting || isConnected)

                Button(action: onSkip) {
                    Text("Skip for now")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)
            }
            .padding(.horizontal)

            // Navigation
            HStack(spacing: 16) {
                Button(action: onBack) {
                    HStack {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .foregroundStyle(.primary)
                    .cornerRadius(14)
                }

                if isConnected {
                    Button(action: { continueWithHealthData() }) {
                        HStack {
                            Text("Continue")
                            Image(systemName: "chevron.right")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(BrandColors.gradient)
                        .foregroundStyle(.white)
                        .cornerRadius(14)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
    }

    private func requestHealthKit() {
        isRequesting = true

        Task {
            do {
                try await HealthKitService.shared.requestAuthorization()
                let authorized = HealthKitService.shared.isAuthorized

                await MainActor.run {
                    isConnected = authorized
                    isRequesting = false
                }

                // Auto-advance if connected - fetch profile data first
                if authorized {
                    let profileData = await HealthKitService.shared.fetchProfileData()
                    await MainActor.run {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                            onComplete(profileData)
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    isRequesting = false
                }
            }
        }
    }

    private func continueWithHealthData() {
        Task {
            let profileData = await HealthKitService.shared.fetchProfileData()
            await MainActor.run {
                onComplete(profileData)
            }
        }
    }
}

struct HealthBenefitRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(BrandColors.primaryOrange)
                .frame(width: 24)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Profile Edit View (for editing from settings)
struct ProfileEditView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var userProfile: UserProfile
    var onComplete: () -> Void

    @State private var heightText = ""
    @State private var weightText = ""
    @State private var ageText = ""
    @State private var selectedActivityLevel: ActivityLevel = .moderatelyActive

    var body: some View {
        NavigationStack {
            Form {
                Section("Body Measurements") {
                    HStack {
                        Text("Height")
                        Spacer()
                        TextField("170", text: $heightText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("cm")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Weight")
                        Spacer()
                        TextField("70", text: $weightText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("kg")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Age")
                        Spacer()
                        TextField("30", text: $ageText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("years")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Activity Level") {
                    Picker("Activity", selection: $selectedActivityLevel) {
                        ForEach(ActivityLevel.allCases, id: \.self) { level in
                            Text(level.rawValue).tag(level)
                        }
                    }
                }

                if let calories = calculatedCalories {
                    Section("Calculated Target") {
                        HStack {
                            Text("Daily Calories")
                            Spacer()
                            Text("\(calories) kcal")
                                .fontWeight(.semibold)
                                .foregroundStyle(BrandColors.primaryOrange)
                        }
                    }
                }
            }
            .formKeyboardDismissible()
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveProfile()
                        dismiss()
                        onComplete()
                    }
                }
            }
            .onAppear {
                loadProfile()
            }
        }
    }

    private var calculatedCalories: Int? {
        guard let h = Double(heightText), let w = Double(weightText), let a = Int(ageText) else { return nil }
        let bmr = 10 * w + 6.25 * h - 5 * Double(a) + 5
        let tdee = bmr * selectedActivityLevel.multiplier
        return Int(tdee)
    }

    private func loadProfile() {
        if let height = userProfile.height {
            heightText = String(Int(height))
        }
        if let weight = userProfile.weight {
            weightText = String(format: "%.1f", weight)
        }
        if let age = userProfile.age {
            ageText = String(age)
        }
        if let level = userProfile.activityLevel {
            selectedActivityLevel = level
        }
    }

    private func saveProfile() {
        userProfile.height = Double(heightText)
        userProfile.weight = Double(weightText)
        userProfile.age = Int(ageText)
        userProfile.activityLevel = selectedActivityLevel
        userProfile.dailyCalorieTarget = calculatedCalories
        try? context.save()
    }
}
