//
//  DietAIApp.swift
//  DietAI
//
//  Created by Unai Garay Maestre on 8/12/25.
//

import SwiftUI
import SwiftData

@main
struct DietAIApp: App {
    let sharedModelContainer: ModelContainer?
    let databaseError: String?

    init() {
        // Pre-create Application Support directory to prevent CoreData initialization errors on fresh install
        let applicationSupportURL = URL.applicationSupportDirectory
        if !FileManager.default.fileExists(atPath: applicationSupportURL.path()) {
            try? FileManager.default.createDirectory(at: applicationSupportURL, withIntermediateDirectories: true)
        }

        let schema = Schema([
            // Core models
            Item.self,
            DietPlan.self,
            DailyPlan.self,
            Meal.self,
            // User
            UserProfile.self,
            // Shopping & Logging
            ShoppingListItem.self,
            MealLog.self
        ])

        // Try to create the container (local storage only - iCloud requires paid Developer Program)
        do {
            let modelConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false
            )
            sharedModelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
            databaseError = nil
            #if DEBUG
            print("✅ SwiftData container created (local storage)")
            #endif
        } catch {
            // Schema mismatch or CloudKit error - delete old data and retry
            // This is acceptable during development when schema changes frequently
            #if DEBUG
            print("SwiftData migration error: \(error)")
            print("Attempting to delete old data and recreate database...")
            #endif

            // Delete the old SwiftData store
            let url = URL.applicationSupportDirectory.appending(path: "default.store")
            if FileManager.default.fileExists(atPath: url.path()) {
                try? FileManager.default.removeItem(at: url)
            }

            // Also try the standard locations
            let urls = [
                URL.applicationSupportDirectory.appending(path: "default.store"),
                URL.applicationSupportDirectory.appending(path: "default.store-shm"),
                URL.applicationSupportDirectory.appending(path: "default.store-wal")
            ]
            for storeURL in urls {
                try? FileManager.default.removeItem(at: storeURL)
            }

            // Retry creating the container
            do {
                let modelConfiguration = ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: false
                )
                sharedModelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
                databaseError = nil
                #if DEBUG
                print("✅ Successfully recreated database with new schema")
                #endif
            } catch {
                // Store the error instead of crashing
                sharedModelContainer = nil
                databaseError = "Could not create database: \(error.localizedDescription)"
                #if DEBUG
                print("⚠️ Database creation failed: \(error)")
                #endif
            }
        }

        // Configure services with model context if available
        if let container = sharedModelContainer {
            let context = container.mainContext
            DependencyContainer.shared.configure(with: context)
        }
    }

    var body: some Scene {
        WindowGroup {
            if let container = sharedModelContainer {
                RootView()
                    .environmentObject(DependencyContainer.shared)
                    .modelContainer(container)
            } else {
                DatabaseErrorView(error: databaseError ?? "Unknown database error")
            }
        }
    }
}

// MARK: - Root View with Splash Screen
struct RootView: View {
    @State private var showSplash = true
    @State private var splashComplete = false

    var body: some View {
        ZStack {
            if splashComplete {
                MainTabView()
                    .transition(.opacity)
            }

            if showSplash {
                SplashScreenView()
                    .transition(.opacity)
            }
        }
        .onAppear {
            // Show splash for 2.5 seconds (matches animation timing), then transition
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                withAnimation(.easeOut(duration: 0.5)) {
                    showSplash = false
                    splashComplete = true
                }
            }

            // Export app icons in debug mode (one-time)
            #if DEBUG
            exportAppIconsIfNeeded()
            #endif
        }
    }

    #if DEBUG
    private func exportAppIconsIfNeeded() {
        let defaults = UserDefaults.standard
        let key = "hasExportedAppIcons"

        if !defaults.bool(forKey: key) {
            Task { @MainActor in
                AppIconExporter.exportIcons()
                defaults.set(true, forKey: key)
            }
        }
    }
    #endif
}

// MARK: - Database Error View
struct DatabaseErrorView: View {
    let error: String

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.orange)

            Text("Database Error")
                .font(.title)
                .fontWeight(.bold)

            Text("Diet AI couldn't start because of a database problem.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(8)

            Text("Try restarting the app. If the problem persists, you may need to reinstall.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }
}
