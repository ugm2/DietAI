import SwiftUI

// MARK: - Splash Screen View
struct SplashScreenView: View {
    // Animation states
    @State private var iconScale: CGFloat = 0.3
    @State private var iconOpacity: Double = 0
    @State private var iconRotation: Double = -30
    @State private var glowScale: CGFloat = 0.8
    @State private var glowOpacity: Double = 0
    @State private var titleOffset: CGFloat = 30
    @State private var titleOpacity: Double = 0
    @State private var taglineOpacity: Double = 0
    @State private var particlesVisible = false
    @State private var loadingOpacity: Double = 0
    @State private var gradientRotation: Double = 0

    var body: some View {
        ZStack {
            // Animated background gradient
            AngularGradient(
                colors: [
                    Color(red: 0.98, green: 0.65, blue: 0.35),
                    Color(red: 0.96, green: 0.55, blue: 0.30),
                    Color(red: 0.94, green: 0.48, blue: 0.28),
                    Color(red: 0.96, green: 0.55, blue: 0.30),
                    Color(red: 0.98, green: 0.65, blue: 0.35)
                ],
                center: .center,
                angle: .degrees(gradientRotation)
            )
            .blur(radius: 60)
            .ignoresSafeArea()

            // Solid base to prevent weird edges
            Color(red: 0.96, green: 0.58, blue: 0.32)
                .ignoresSafeArea()
                .opacity(0.5)

            // Floating particles
            if particlesVisible {
                FloatingParticlesView()
            }

            VStack(spacing: 24) {
                Spacer()

                // App Icon with glow
                ZStack {
                    // Outer glow rings
                    ForEach(0..<3) { i in
                        Circle()
                            .stroke(
                                .white.opacity(0.15 - Double(i) * 0.04),
                                lineWidth: 2
                            )
                            .frame(width: 160 + CGFloat(i) * 30, height: 160 + CGFloat(i) * 30)
                            .scaleEffect(glowScale)
                            .opacity(glowOpacity)
                    }

                    // Pulsing glow background
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [.white.opacity(0.4), .white.opacity(0)],
                                center: .center,
                                startRadius: 30,
                                endRadius: 90
                            )
                        )
                        .frame(width: 180, height: 180)
                        .scaleEffect(glowScale)
                        .opacity(glowOpacity)

                    // Main icon background
                    Circle()
                        .fill(.white.opacity(0.25))
                        .frame(width: 140, height: 140)
                        .shadow(color: .black.opacity(0.1), radius: 20, y: 10)

                    // Icon content
                    ZStack {
                        // Leaf shape
                        Image(systemName: "leaf.fill")
                            .font(.system(size: 50, weight: .medium))
                            .foregroundStyle(.white)
                            .rotationEffect(.degrees(-15))
                            .offset(x: -5, y: 5)
                            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)

                        // AI sparkles with shimmer
                        Image(systemName: "sparkles")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.white)
                            .offset(x: 25, y: -20)
                            .shadow(color: .white.opacity(0.8), radius: 8)
                    }
                }
                .scaleEffect(iconScale)
                .opacity(iconOpacity)
                .rotationEffect(.degrees(iconRotation))

                // App name with animated entrance
                VStack(spacing: 12) {
                    Text("DietAI")
                        .font(.system(size: 46, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                        .offset(y: titleOffset)
                        .opacity(titleOpacity)

                    Text("Your AI-Powered Nutrition Partner")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .opacity(taglineOpacity)
                }

                Spacer()

                // Animated loading indicator
                VStack(spacing: 16) {
                    // Custom animated dots
                    HStack(spacing: 8) {
                        ForEach(0..<3) { i in
                            LoadingDot(delay: Double(i) * 0.15)
                        }
                    }

                    Text("Preparing your experience...")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .opacity(loadingOpacity)
                .padding(.bottom, 60)
            }
        }
        .onAppear {
            startAnimations()
        }
    }

    private func startAnimations() {
        // Rotating gradient (subtle)
        withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
            gradientRotation = 360
        }

        // Icon entrance - spring animation
        withAnimation(.spring(response: 0.8, dampingFraction: 0.6).delay(0.1)) {
            iconScale = 1.0
            iconOpacity = 1.0
            iconRotation = 0
        }

        // Glow pulse animation
        withAnimation(.easeOut(duration: 0.6).delay(0.3)) {
            glowOpacity = 1.0
            glowScale = 1.0
        }

        // Continuous glow pulse
        withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true).delay(0.9)) {
            glowScale = 1.15
            glowOpacity = 0.6
        }

        // Title entrance
        withAnimation(.spring(response: 0.7, dampingFraction: 0.7).delay(0.4)) {
            titleOffset = 0
            titleOpacity = 1.0
        }

        // Tagline fade in
        withAnimation(.easeOut(duration: 0.5).delay(0.7)) {
            taglineOpacity = 1.0
        }

        // Particles
        withAnimation(.easeOut(duration: 0.3).delay(0.5)) {
            particlesVisible = true
        }

        // Loading indicator
        withAnimation(.easeOut(duration: 0.4).delay(0.9)) {
            loadingOpacity = 1.0
        }
    }
}

// MARK: - Loading Dot
struct LoadingDot: View {
    let delay: Double
    @State private var isAnimating = false

    var body: some View {
        Circle()
            .fill(.white)
            .frame(width: 8, height: 8)
            .scaleEffect(isAnimating ? 1.0 : 0.5)
            .opacity(isAnimating ? 1.0 : 0.4)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 0.6)
                    .repeatForever(autoreverses: true)
                    .delay(delay)
                ) {
                    isAnimating = true
                }
            }
    }
}

// MARK: - Floating Particles
struct FloatingParticlesView: View {
    let particleCount = 15

    var body: some View {
        GeometryReader { geometry in
            ForEach(0..<particleCount, id: \.self) { i in
                FloatingParticle(
                    size: geometry.size,
                    index: i
                )
            }
        }
    }
}

struct FloatingParticle: View {
    let size: CGSize
    let index: Int

    @State private var position: CGPoint = .zero
    @State private var opacity: Double = 0
    @State private var scale: CGFloat = 0.5

    private var particleSize: CGFloat {
        CGFloat.random(in: 4...12)
    }

    private var duration: Double {
        Double.random(in: 3...6)
    }

    var body: some View {
        Circle()
            .fill(.white.opacity(0.3))
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

                // Floating animation
                withAnimation(
                    .easeInOut(duration: duration)
                    .repeatForever(autoreverses: true)
                    .delay(Double(index) * 0.2)
                ) {
                    position = CGPoint(
                        x: position.x + CGFloat.random(in: -50...50),
                        y: position.y + CGFloat.random(in: -80...(-20))
                    )
                }
            }
    }
}

// MARK: - App Icon View (for export)
struct AppIconView: View {
    let size: CGFloat

    init(size: CGFloat = 1024) {
        self.size = size
    }

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color(red: 0.98, green: 0.65, blue: 0.35), // Warm orange
                    Color(red: 0.92, green: 0.45, blue: 0.25)  // Deeper orange
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Subtle pattern overlay
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.white.opacity(0.15), .clear],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: size * 0.8
                    )
                )

            // Main icon content
            ZStack {
                // Large leaf
                Image(systemName: "leaf.fill")
                    .font(.system(size: size * 0.38, weight: .medium))
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(-20))
                    .offset(x: -size * 0.02, y: size * 0.04)

                // AI sparkles
                Image(systemName: "sparkles")
                    .font(.system(size: size * 0.18, weight: .bold))
                    .foregroundStyle(.white.opacity(0.95))
                    .offset(x: size * 0.18, y: -size * 0.15)

                // Small accent sparkle
                Image(systemName: "sparkle")
                    .font(.system(size: size * 0.08, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .offset(x: -size * 0.22, y: -size * 0.18)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }
}

// MARK: - Dark Mode App Icon
struct AppIconDarkView: View {
    let size: CGFloat

    init(size: CGFloat = 1024) {
        self.size = size
    }

    var body: some View {
        ZStack {
            // Dark background
            LinearGradient(
                colors: [
                    Color(red: 0.15, green: 0.15, blue: 0.18),
                    Color(red: 0.08, green: 0.08, blue: 0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Subtle glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.orange.opacity(0.2), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.5
                    )
                )

            // Main icon content
            ZStack {
                // Large leaf
                Image(systemName: "leaf.fill")
                    .font(.system(size: size * 0.38, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 0.98, green: 0.70, blue: 0.40),
                                Color(red: 0.95, green: 0.55, blue: 0.30)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .rotationEffect(.degrees(-20))
                    .offset(x: -size * 0.02, y: size * 0.04)

                // AI sparkles
                Image(systemName: "sparkles")
                    .font(.system(size: size * 0.18, weight: .bold))
                    .foregroundStyle(Color(red: 0.98, green: 0.75, blue: 0.45))
                    .offset(x: size * 0.18, y: -size * 0.15)

                // Small accent sparkle
                Image(systemName: "sparkle")
                    .font(.system(size: size * 0.08, weight: .bold))
                    .foregroundStyle(Color.orange.opacity(0.6))
                    .offset(x: -size * 0.22, y: -size * 0.18)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }
}

// MARK: - Preview
#Preview("Splash Screen") {
    SplashScreenView()
}

#Preview("App Icon Light") {
    AppIconView(size: 200)
        .padding()
}

#Preview("App Icon Dark") {
    AppIconDarkView(size: 200)
        .padding()
        .background(Color.black)
}

#Preview("App Icons Grid") {
    VStack(spacing: 20) {
        HStack(spacing: 20) {
            AppIconView(size: 120)
            AppIconDarkView(size: 120)
        }
        Text("Light & Dark Mode Icons")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
    .padding()
}
