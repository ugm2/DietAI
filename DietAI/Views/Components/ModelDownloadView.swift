import SwiftUI
import Combine

// MARK: - Model Download View
/// Beautiful animated view shown when downloading the AI model for the first time
struct ModelDownloadView: View {
    @Bindable var modelManager: ModelManager
    var onComplete: (() -> Void)? = nil
    var onCancel: (() -> Void)? = nil

    @State private var rotation: Double = 0
    @State private var pulseScale: CGFloat = 1.0
    @State private var particlesVisible = false
    @State private var tipIndex = 0
    @State private var isLoading = false
    @State private var hasError = false
    @State private var errorMessage = ""
    @State private var hasCompleted = false  // Prevent multiple onComplete calls
    @State private var showContent = false   // Only show UI after verifying model needs loading

    private let tips = [
        "DietAI runs entirely on your device",
        "Your data stays private and secure",
        "No internet needed after download",
        "AI-powered meal planning at your fingertips"
    ]

    private let timer = Timer.publish(every: 4, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            // Background gradient (always show to avoid flash)
            LinearGradient(
                colors: [
                    Color(red: 0.98, green: 0.65, blue: 0.35).opacity(0.15),
                    Color(red: 0.96, green: 0.55, blue: 0.30).opacity(0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Only show content if model actually needs loading
            if showContent {
                // Floating particles
                if particlesVisible {
                    DownloadParticlesView()
                }

                VStack(spacing: 32) {
                Spacer()

                // Animated icon
                ZStack {
                    // Outer pulsing rings
                    ForEach(0..<3) { i in
                        Circle()
                            .stroke(
                                Color(red: 0.98, green: 0.65, blue: 0.35).opacity(0.2 - Double(i) * 0.05),
                                lineWidth: 2
                            )
                            .frame(width: 140 + CGFloat(i) * 30, height: 140 + CGFloat(i) * 30)
                            .scaleEffect(pulseScale)
                    }

                    // Progress ring
                    Circle()
                        .stroke(
                            Color(red: 0.98, green: 0.65, blue: 0.35).opacity(0.2),
                            lineWidth: 8
                        )
                        .frame(width: 120, height: 120)

                    Circle()
                        .trim(from: 0, to: modelManager.loadingProgress)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.98, green: 0.65, blue: 0.35),
                                    Color(red: 0.92, green: 0.45, blue: 0.25)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .frame(width: 120, height: 120)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.3), value: modelManager.loadingProgress)

                    // Center icon
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.98, green: 0.65, blue: 0.35),
                                        Color(red: 0.92, green: 0.45, blue: 0.25)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 90, height: 90)
                            .shadow(color: Color(red: 0.92, green: 0.45, blue: 0.25).opacity(0.3), radius: 15, y: 5)

                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 36, weight: .medium))
                            .foregroundStyle(.white)
                            .rotationEffect(.degrees(rotation))
                    }
                }

                // Status text
                VStack(spacing: 12) {
                    if hasError {
                        // Error state
                        Text("Download Failed")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(.red)

                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        // Retry and Cancel buttons
                        HStack(spacing: 16) {
                            Button {
                                onCancel?()
                            } label: {
                                Text("Cancel")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 100)
                                    .padding(.vertical, 12)
                                    .background(Color(uiColor: .secondarySystemBackground))
                                    .cornerRadius(10)
                            }

                            Button {
                                retryDownload()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.clockwise")
                                    Text("Retry")
                                }
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                                .frame(width: 100)
                                .padding(.vertical, 12)
                                .background(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.98, green: 0.65, blue: 0.35),
                                            Color(red: 0.92, green: 0.45, blue: 0.25)
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .cornerRadius(10)
                            }
                        }
                        .padding(.top, 8)
                    } else {
                        // Normal loading state
                        Text("Preparing AI")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text(modelManager.status)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        // Progress percentage
                        if modelManager.loadingProgress > 0 && modelManager.loadingProgress < 1 {
                            Text("\(Int(modelManager.loadingProgress * 100))%")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.98, green: 0.65, blue: 0.35),
                                            Color(red: 0.92, green: 0.45, blue: 0.25)
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        }
                    }
                }

                Spacer()

                // Model info
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "cpu")
                            .font(.caption)
                        Text(modelManager.currentTier.displayName)
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(.secondary)

                    Text("~\(String(format: "%.1f", modelManager.currentTier.estimatedMemoryGB)) GB")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                // Rotating tips (only when not in error state)
                if !hasError {
                    VStack(spacing: 8) {
                        Image(systemName: "lightbulb.fill")
                            .font(.caption)
                            .foregroundStyle(Color(red: 0.98, green: 0.65, blue: 0.35))

                        Text(tips[tipIndex])
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .animation(.easeInOut, value: tipIndex)
                    }
                    .padding(.horizontal, 40)
                }

                // Cancel button (visible during download, hidden in error state which has its own buttons)
                if !hasError {
                    Button {
                        onCancel?()
                    } label: {
                        Text("Cancel")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                    }
                    .padding(.bottom, 40)
                } else {
                    Spacer()
                        .frame(height: 40)
                }
            }
            } // end if showContent
        }
        .onAppear {
            // Check if model is already loaded - if so, complete immediately without showing UI
            if modelManager.isModelLoaded {
                hasCompleted = true
                onComplete?()
                return
            }

            // Model needs loading, show the UI
            showContent = true
            startAnimations()
            startModelLoading()
        }
        .onReceive(timer) { _ in
            withAnimation {
                tipIndex = (tipIndex + 1) % tips.count
            }
        }
        .onChange(of: modelManager.isModelLoaded) { _, isLoaded in
            if isLoaded && !hasCompleted {
                hasCompleted = true
                onComplete?()
            }
        }
    }

    private func startModelLoading() {
        guard !isLoading && !hasCompleted else { return }

        // Check if already loaded
        if modelManager.isModelLoaded {
            hasCompleted = true
            onComplete?()
            return
        }

        isLoading = true
        hasError = false
        errorMessage = ""

        Task {
            let success = await modelManager.loadModelIfNeeded()

            await MainActor.run {
                isLoading = false
                if success && !hasCompleted {
                    hasCompleted = true
                    onComplete?()
                } else if !success {
                    hasError = true
                    errorMessage = modelManager.memoryWarning ?? "Failed to download the AI model. Please check your internet connection and try again."
                }
            }
        }
    }

    private func retryDownload() {
        hasError = false
        errorMessage = ""
        startModelLoading()
    }

    private func startAnimations() {
        // Gentle rotation
        withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) {
            rotation = 360
        }

        // Pulse animation
        withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
            pulseScale = 1.1
        }

        // Show particles
        withAnimation(.easeOut(duration: 0.5).delay(0.3)) {
            particlesVisible = true
        }
    }
}

// MARK: - Download Particles
struct DownloadParticlesView: View {
    let particleCount = 12

    var body: some View {
        GeometryReader { geometry in
            ForEach(0..<particleCount, id: \.self) { i in
                DownloadParticle(
                    size: geometry.size,
                    index: i
                )
            }
        }
    }
}

struct DownloadParticle: View {
    let size: CGSize
    let index: Int

    @State private var position: CGPoint = .zero
    @State private var opacity: Double = 0
    @State private var scale: CGFloat = 0.5

    private var particleSize: CGFloat {
        CGFloat.random(in: 4...10)
    }

    private var duration: Double {
        Double.random(in: 4...8)
    }

    var body: some View {
        Circle()
            .fill(Color(red: 0.98, green: 0.65, blue: 0.35).opacity(0.4))
            .frame(width: particleSize, height: particleSize)
            .blur(radius: 1)
            .position(position)
            .opacity(opacity)
            .scaleEffect(scale)
            .onAppear {
                // Random starting position
                position = CGPoint(
                    x: CGFloat.random(in: 0...size.width),
                    y: CGFloat.random(in: 0...size.height)
                )

                // Fade in
                withAnimation(.easeOut(duration: 0.5).delay(Double(index) * 0.1)) {
                    opacity = Double.random(in: 0.2...0.5)
                    scale = 1.0
                }

                // Float upward
                withAnimation(
                    .easeInOut(duration: duration)
                    .repeatForever(autoreverses: true)
                    .delay(Double(index) * 0.2)
                ) {
                    position = CGPoint(
                        x: position.x + CGFloat.random(in: -40...40),
                        y: position.y - CGFloat.random(in: 30...80)
                    )
                }
            }
    }
}

// MARK: - Model Download Sheet Modifier
extension View {
    /// Shows a download sheet when the model is being downloaded
    func modelDownloadSheet(modelManager: ModelManager, isLoading: Binding<Bool>) -> some View {
        self.fullScreenCover(isPresented: isLoading) {
            ModelDownloadView(modelManager: modelManager)
                .interactiveDismissDisabled()
        }
    }
}

// MARK: - Model Loading Wrapper
/// A view that ensures the model is loaded before showing content
struct ModelLoadingWrapper<Content: View>: View {
    @Bindable var modelManager: ModelManager
    @ViewBuilder var content: () -> Content

    @State private var isLoading = false
    @State private var hasCheckedModel = false

    var body: some View {
        ZStack {
            if modelManager.isModelLoaded || hasCheckedModel {
                content()
            }

            if isLoading {
                ModelDownloadView(modelManager: modelManager)
                    .transition(.opacity)
            }
        }
        .task {
            if !modelManager.isModelLoaded && !hasCheckedModel {
                isLoading = true
                _ = await modelManager.loadModelIfNeeded()
                withAnimation {
                    isLoading = false
                    hasCheckedModel = true
                }
            } else {
                hasCheckedModel = true
            }
        }
    }
}

// MARK: - Preview
#Preview("Download View") {
    ModelDownloadView(modelManager: ModelManager.shared)
}
