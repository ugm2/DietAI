import SwiftUI
import AuthenticationServices
import SwiftData

struct SignInView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var colorScheme

    @State private var authService = AuthenticationService.shared
    @State private var showError = false
    @State private var errorMessage = ""

    var onSignedIn: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Logo and Welcome
            VStack(spacing: 16) {
                Image(systemName: "leaf.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.green)

                Text("Diet AI")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Your AI-powered nutrition assistant")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            // Features highlight
            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(icon: "wand.and.stars", title: "AI-Powered Plans", description: "Generate personalized diet plans instantly")
                FeatureRow(icon: "chart.bar.fill", title: "Track Progress", description: "Monitor calories and macros effortlessly")
                FeatureRow(icon: "icloud.fill", title: "Sync Everywhere", description: "Access your plans on all your devices")
            }
            .padding(.horizontal)

            Spacer()

            // Sign In Button
            VStack(spacing: 16) {
                SignInWithAppleButton(
                    onRequest: configureAppleSignIn,
                    onCompletion: handleAppleSignIn
                )
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 50)
                .cornerRadius(12)
                .padding(.horizontal)

                Button(action: continueAsGuest) {
                    Text("Continue as Guest")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
                .frame(height: 40)
        }
        .alert("Sign In Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private func configureAppleSignIn(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName, .email]
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            Task {
                do {
                    try await authService.signInWithApple(authorization: authorization, context: context)
                    onSignedIn()
                } catch {
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func continueAsGuest() {
        Task {
            do {
                try await authService.continueAsGuest(context: context)
                onSignedIn()
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Profile Setup View
struct ProfileSetupView: View {
    @Environment(\.modelContext) private var context
    @Bindable var userProfile: UserProfile

    @State private var height: String = ""
    @State private var weight: String = ""
    @State private var age: String = ""
    @State private var selectedGoal: GoalType = .maintenance
    @State private var selectedActivity: ActivityLevel = .moderatelyActive
    @State private var restrictions: Set<String> = []

    let commonRestrictions = ["Vegetarian", "Vegan", "Gluten-Free", "Dairy-Free", "Nut-Free", "Halal", "Kosher"]

    var onComplete: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Physical Information") {
                    TextField("Height (cm)", text: $height)
                        .keyboardType(.numberPad)

                    TextField("Weight (kg)", text: $weight)
                        .keyboardType(.decimalPad)

                    TextField("Age", text: $age)
                        .keyboardType(.numberPad)
                }

                Section("Activity Level") {
                    Picker("Activity Level", selection: $selectedActivity) {
                        ForEach(ActivityLevel.allCases, id: \.self) { level in
                            Text(level.rawValue).tag(level)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Diet Goal") {
                    Picker("Goal", selection: $selectedGoal) {
                        ForEach(GoalType.allCases, id: \.self) { goal in
                            Text(goal.rawValue).tag(goal)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Dietary Restrictions") {
                    ForEach(commonRestrictions, id: \.self) { restriction in
                        Toggle(restriction, isOn: Binding(
                            get: { restrictions.contains(restriction) },
                            set: { isOn in
                                if isOn {
                                    restrictions.insert(restriction)
                                } else {
                                    restrictions.remove(restriction)
                                }
                            }
                        ))
                    }
                }

                Section {
                    if let recommended = calculateRecommendedCalories() {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Recommended Daily Calories")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(recommended) kcal")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
            .navigationTitle("Complete Your Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        saveProfile()
                        onComplete()
                    }
                }
            }
        }
    }

    private func calculateRecommendedCalories() -> Int? {
        guard let h = Double(height), let w = Double(weight), let a = Int(age) else {
            return nil
        }
        // Mifflin-St Jeor (male approximation)
        let bmr = 10 * w + 6.25 * h - 5 * Double(a) + 5
        let tdee = bmr * selectedActivity.multiplier

        switch selectedGoal {
        case .weightLoss: return Int(tdee * 0.8)
        case .muscleGain: return Int(tdee * 1.1)
        case .maintenance: return Int(tdee)
        case .keto: return Int(tdee * 0.85)
        }
    }

    private func saveProfile() {
        userProfile.height = Double(height)
        userProfile.weight = Double(weight)
        userProfile.age = Int(age)
        userProfile.activityLevel = selectedActivity
        userProfile.preferredGoal = selectedGoal
        userProfile.dailyCalorieTarget = calculateRecommendedCalories()
        userProfile.dietaryRestrictions = Array(restrictions)

        try? context.save()
    }
}
