import SwiftUI
import SwiftData

struct AnalyticsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MealLog.loggedAt, order: .reverse) var mealLogs: [MealLog]
    @Query var userProfiles: [UserProfile]

    @State private var viewModel = AnalyticsViewModel()
    @State private var selectedTimeRange: AnalyticsTimeRange = .week
    @State private var selectedSection: AnalyticsSection = .meals

    private var userProfile: UserProfile? { userProfiles.first }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Time Range Selector
                    AnalyticsTimeRangeSelector(selectedRange: $selectedTimeRange)
                        .padding(.horizontal)

                    // Section Selector
                    SectionSelector(selectedSection: $selectedSection)
                        .padding(.horizontal)

                    // Content based on selected section
                    Group {
                        switch selectedSection {
                        case .meals:
                            MealAnalyticsSection(
                                viewModel: viewModel.mealAnalytics,
                                timeRange: selectedTimeRange
                            )
                        case .workouts:
                            WorkoutAnalyticsSection(
                                viewModel: viewModel.workoutAnalytics,
                                timeRange: selectedTimeRange
                            )
                        case .health:
                            HealthAnalyticsSection(
                                viewModel: viewModel.healthAnalytics,
                                timeRange: selectedTimeRange,
                                userProfile: userProfile
                            )
                        }
                    }
                    .padding(.horizontal)

                    Spacer(minLength: 40)
                }
                .padding(.top)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Analytics")
            .refreshable {
                await loadData()
            }
            .task {
                await loadData()
            }
            .onChange(of: selectedTimeRange) { _, _ in
                Task {
                    await loadData()
                }
            }
            .overlay {
                if viewModel.isLoading {
                    LoadingOverlay()
                }
            }
        }
    }

    private func loadData() async {
        await viewModel.loadData(
            for: selectedTimeRange,
            mealLogs: mealLogs,
            userProfile: userProfile
        )
    }
}

// MARK: - Loading Overlay
struct LoadingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.1)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                ProgressView()
                    .scaleEffect(1.2)

                Text("Loading analytics...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .background(.ultraThinMaterial)
            .cornerRadius(16)
        }
    }
}

#Preview {
    AnalyticsView()
        .modelContainer(for: [MealLog.self, UserProfile.self], inMemory: true)
}
