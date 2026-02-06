import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var dbContext
    @Query(sort: \DietPlan.createdAt, order: .reverse) var savedPlans: [DietPlan]
    
    @State private var modelManager = ModelManager.shared
    @State private var userRequest = "Plan a 1800 calorie keto diet for Monday."
    
    var body: some View {
        NavigationStack { // WRAP EVERYTHING IN NAVIGATION STACK
            VStack(spacing: 20) {
                
                // --- Header & Input ---
                VStack(spacing: 12) {
                    Text("Diet AI Assistant")
                        .font(.largeTitle)
                        .bold()
                    
                    TextField("Request...", text: $userRequest)
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal)
                    
                    Button(action: {
                        Task {
                            await modelManager.generateDiet(userPrompt: userRequest, context: dbContext)
                        }
                    }) {
                        HStack {
                            if modelManager.isGenerating {
                                ProgressView().tint(.white)
                                Text("Generating...")
                            } else {
                                Image(systemName: "wand.and.stars")
                                Text("Generate Plan")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(modelManager.isGenerating ? Color.gray : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(modelManager.isGenerating)
                    .padding(.horizontal)
                    
                    Text(modelManager.status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .animation(.default, value: modelManager.status)
                }
                .padding(.top)

                Divider()
                
                // --- Saved Plans List ---
                List {
                    Section("Your Diet Plans") {
                        if savedPlans.isEmpty {
                            ContentUnavailableView("No Plans Yet", systemImage: "doc.text.magnifyingglass", description: Text("Ask the AI to create a diet plan for you."))
                        }
                        
                        ForEach(savedPlans) { plan in
                            // NAVIGATION LINK ADDED HERE
                            NavigationLink(destination: DietDetailView(plan: plan)) {
                                VStack(alignment: .leading) {
                                    Text(plan.name).bold()
                                    HStack {
                                        Text(plan.goal)
                                            .font(.caption)
                                            .padding(4)
                                            .background(Color.blue.opacity(0.1))
                                            .cornerRadius(4)
                                        
                                        Spacer()
                                        
                                        Text("\(plan.days.count) Days")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                dbContext.delete(savedPlans[index])
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .task { await modelManager.loadModel() }
        }
    }
}
