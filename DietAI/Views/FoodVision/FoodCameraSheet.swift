import SwiftUI
import SwiftData
import AVFoundation
import PhotosUI
import Combine

// MARK: - Food Camera Sheet (Main Entry Point)

struct FoodCameraSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    var accentColor: Color = .pink

    @State private var phase: CameraPhase = .capturing
    @State private var capturedImage: CIImage?
    @State private var capturedUIImage: UIImage?
    @State private var userHint: String = ""
    @State private var estimate: FoodEstimate?
    @State private var errorMessage: String?

    // Photo picker state
    @State private var selectedPhoto: PhotosPickerItem?

    // VLM download state
    private let visionManager = VisionModelManager.shared

    enum CameraPhase {
        case capturing
        case reviewing
        case downloading  // VLM model download in progress
        case analyzing
        case result
        case error
    }

    var body: some View {
        NavigationStack {
            ZStack {
                switch phase {
                case .capturing:
                    capturingView

                case .reviewing:
                    if let uiImage = capturedUIImage {
                        FoodPhotoReviewView(
                            image: uiImage,
                            hint: $userHint,
                            onConfirm: analyzeFood,
                            onRetake: retakePhoto,
                            accentColor: accentColor
                        )
                    }

                case .downloading:
                    VLMDownloadView(
                        visionManager: visionManager,
                        onComplete: {
                            // Model downloaded, now analyze
                            performAnalysis()
                        },
                        onCancel: {
                            phase = .reviewing
                        },
                        accentColor: accentColor
                    )

                case .analyzing:
                    FoodAnalyzingView(accentColor: accentColor)

                case .result:
                    if let estimate = estimate {
                        FoodEstimateResultView(
                            estimate: estimate,
                            onSave: saveEstimate,
                            onRetry: retakePhoto,
                            accentColor: accentColor
                        )
                    }

                case .error:
                    FoodErrorView(
                        message: errorMessage ?? "Unknown error",
                        onRetry: retakePhoto,
                        accentColor: accentColor
                    )
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: - Capturing View

    private var capturingView: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height

            ZStack {
                // Camera preview fills entire view
                FoodCameraPreviewView(onCapture: handleCapture)
                    .ignoresSafeArea()

                // Library button - positioned differently for portrait/landscape
                if isLandscape {
                    // Landscape: button on the right side
                    HStack {
                        Spacer()
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            VStack(spacing: 8) {
                                Image(systemName: "photo.on.rectangle")
                                    .font(.title2)
                                Text("Library")
                                    .font(.caption)
                            }
                            .foregroundStyle(.white)
                            .padding()
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(12)
                        }
                        .padding(.trailing, 20)
                    }
                } else {
                    // Portrait: button at the bottom
                    VStack {
                        Spacer()
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            Label("Choose from Library", systemImage: "photo.on.rectangle")
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color(uiColor: .secondarySystemGroupedBackground))
                                .cornerRadius(12)
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 20)
                    }
                }
            }
        }
        .background(Color.black)
        .onChange(of: selectedPhoto) { _, newValue in
            handlePhotoSelection(newValue)
        }
    }

    // MARK: - Navigation Title

    private var navigationTitle: String {
        switch phase {
        case .capturing: return "Take Photo"
        case .reviewing: return "Review"
        case .downloading: return "Preparing AI"
        case .analyzing: return "Analyzing..."
        case .result: return "Results"
        case .error: return "Error"
        }
    }

    // MARK: - Actions

    private func handleCapture(_ uiImage: UIImage) {
        capturedUIImage = uiImage
        capturedImage = CIImage(image: uiImage)
        phase = .reviewing
    }

    private func handlePhotoSelection(_ item: PhotosPickerItem?) {
        guard let item = item else { return }

        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let uiImage = UIImage(data: data) {
                capturedUIImage = uiImage
                capturedImage = CIImage(image: uiImage)
                phase = .reviewing
            }
        }
    }

    private func retakePhoto() {
        capturedImage = nil
        capturedUIImage = nil
        selectedPhoto = nil
        userHint = ""
        estimate = nil
        errorMessage = nil
        phase = .capturing
    }

    private func analyzeFood() {
        guard capturedImage != nil else { return }

        // Check if VLM model is loaded - if not, show download view first
        if !visionManager.isModelLoaded {
            phase = .downloading
            return
        }

        // Model is ready, proceed with analysis
        performAnalysis()
    }

    private func performAnalysis() {
        guard let image = capturedImage else { return }

        phase = .analyzing

        Task {
            do {
                let result = try await FoodVisionService.shared.analyzeFood(
                    image: image,
                    userHint: userHint.isEmpty ? nil : userHint
                )
                estimate = result
                phase = .result
            } catch {
                errorMessage = error.localizedDescription
                phase = .error
            }
        }
    }

    private func saveEstimate(_ estimate: FoodEstimate, mealType: MealType, date: Date) {
        let log = MealLog(
            name: estimate.foodName,
            type: mealType,
            calories: estimate.calories,
            protein: estimate.protein,
            carbs: estimate.carbs,
            fat: estimate.fat,
            loggedAt: date
        )
        modelContext.insert(log)
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Food Camera Preview View

struct FoodCameraPreviewView: View {
    let onCapture: (UIImage) -> Void

    @State private var permissionStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var captureSession: AVCaptureSession?
    @State private var photoOutput: AVCapturePhotoOutput?
    @State private var previewLayer: AVCaptureVideoPreviewLayer?
    @State private var isSetup = false
    @State private var setupError: String?
    @State private var photoDelegate: PhotoCaptureDelegate?
    @State private var isCapturing = false
    @State private var showFlash = false

    var body: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height

            ZStack {
                if permissionStatus == .authorized && isSetup {
                    // Camera preview fills entire view
                    CameraPreview(previewLayer: previewLayer)
                        .ignoresSafeArea()

                    // Shutter flash effect
                    if showFlash {
                        Color.white
                            .ignoresSafeArea()
                            .transition(.opacity)
                    }

                    // Show processing overlay while capturing
                    if isCapturing {
                        Color.black.opacity(0.7)
                            .ignoresSafeArea()

                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.5)
                                .tint(.white)
                            Text("Processing...")
                                .font(.headline)
                                .foregroundStyle(.white)
                        }
                    } else {
                        // Controls adapt to orientation
                        if isLandscape {
                            // Landscape: instructions centered at top, capture button lower right
                            VStack {
                                // Instructions centered at top
                                instructionsLabel
                                    .padding(.top, 20)

                                Spacer()
                            }

                            // Capture button on right side, toward bottom
                            HStack {
                                Spacer()
                                VStack {
                                    Spacer()
                                    captureButton
                                        .padding(.bottom, 40)
                                }
                                .padding(.trailing, 100) // Room for library button
                            }
                        } else {
                            // Portrait: instructions at top, capture button at bottom
                            VStack {
                                // Instructions with safe area padding
                                instructionsLabel
                                    .padding(.top, 60) // Clear nav bar

                                Spacer()

                                // Capture button above library button
                                captureButton
                                    .padding(.bottom, 140)
                            }
                        }
                    }

                } else if permissionStatus == .denied || permissionStatus == .restricted {
                    permissionDeniedView
                } else if let error = setupError {
                    errorView(message: error)
                } else {
                    ProgressView("Setting up camera...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .task {
            await setupCamera()
        }
        .onDisappear {
            stopCamera()
        }
    }

    private var instructionsLabel: some View {
        Text("Point camera at your food")
            .font(.subheadline)
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Capsule().fill(Color.black.opacity(0.6)))
    }

    private var captureButton: some View {
        Button(action: capturePhoto) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 70, height: 70)
                    Circle()
                        .stroke(Color.white, lineWidth: 4)
                        .frame(width: 80, height: 80)
                }

                Text("Take photo")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
            }
        }
    }

    private var permissionDeniedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.fill")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("Camera Access Required")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Please enable camera access in Settings to take food photos.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.orange)

            Text("Camera Setup Failed")
                .font(.title2)
                .fontWeight(.semibold)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private func setupCamera() async {
        // Request permission if needed
        if permissionStatus == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            permissionStatus = granted ? .authorized : .denied
        }

        guard permissionStatus == .authorized else { return }

        // Setup capture session
        let session = AVCaptureSession()
        session.sessionPreset = .photo

        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            setupError = "Camera not available"
            return
        }

        do {
            let videoInput = try AVCaptureDeviceInput(device: videoDevice)
            if session.canAddInput(videoInput) {
                session.addInput(videoInput)
            }

            let output = AVCapturePhotoOutput()
            if session.canAddOutput(output) {
                session.addOutput(output)
                photoOutput = output
            }

            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            previewLayer = layer

            captureSession = session

            DispatchQueue.global(qos: .userInitiated).async {
                session.startRunning()
            }

            isSetup = true
        } catch {
            setupError = error.localizedDescription
        }
    }

    private func stopCamera() {
        captureSession?.stopRunning()
    }

    private func capturePhoto() {
        guard let photoOutput = photoOutput, !isCapturing else { return }

        // Immediate haptic feedback
        let impactGenerator = UIImpactFeedbackGenerator(style: .medium)
        impactGenerator.impactOccurred()

        // Show shutter flash animation
        withAnimation(.easeIn(duration: 0.1)) {
            showFlash = true
        }

        // Hide flash and show processing after brief moment
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeOut(duration: 0.1)) {
                showFlash = false
            }
            isCapturing = true
        }

        let settings = AVCapturePhotoSettings()

        let delegate = PhotoCaptureDelegate { [self] image in
            isCapturing = false
            onCapture(image)
        }
        photoDelegate = delegate
        photoOutput.capturePhoto(with: settings, delegate: delegate)
    }
}

// MARK: - Photo Capture Delegate

private class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    let completion: (UIImage) -> Void

    init(completion: @escaping (UIImage) -> Void) {
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            return
        }

        DispatchQueue.main.async {
            // Haptic feedback
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            self.completion(image)
        }
    }
}

// MARK: - Camera Preview UIViewRepresentable

private struct CameraPreview: UIViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer?

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.backgroundColor = .black

        if let layer = previewLayer {
            view.previewLayer = layer
            layer.frame = view.bounds
            layer.videoGravity = .resizeAspectFill
            view.layer.addSublayer(layer)
        }

        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        uiView.updateOrientation()
    }
}

// Custom UIView that handles orientation changes
private class CameraPreviewUIView: UIView {
    var previewLayer: AVCaptureVideoPreviewLayer?

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
        updateOrientation()
    }

    func updateOrientation() {
        guard let connection = previewLayer?.connection,
              connection.isVideoRotationAngleSupported(0) else { return }

        let orientation = UIDevice.current.orientation
        let rotationAngle: CGFloat

        switch orientation {
        case .portrait:
            rotationAngle = 90
        case .portraitUpsideDown:
            rotationAngle = 270
        case .landscapeLeft:
            rotationAngle = 180
        case .landscapeRight:
            rotationAngle = 0
        default:
            // Use interface orientation as fallback
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                switch windowScene.interfaceOrientation {
                case .portrait:
                    rotationAngle = 90
                case .portraitUpsideDown:
                    rotationAngle = 270
                case .landscapeLeft:
                    rotationAngle = 180
                case .landscapeRight:
                    rotationAngle = 0
                default:
                    rotationAngle = 90
                }
            } else {
                rotationAngle = 90
            }
        }

        if connection.isVideoRotationAngleSupported(rotationAngle) {
            connection.videoRotationAngle = rotationAngle
        }
    }
}

// MARK: - Food Photo Review View

struct FoodPhotoReviewView: View {
    let image: UIImage
    @Binding var hint: String
    let onConfirm: () -> Void
    let onRetake: () -> Void
    var accentColor: Color = .pink

    var body: some View {
        VStack(spacing: 0) {
            // Image preview
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 400)
                .cornerRadius(12)
                .padding()

            // Hint input
            VStack(alignment: .leading, spacing: 8) {
                Text("What is this? (optional)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("e.g., Chicken salad, pasta...", text: $hint)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal)

            Spacer()

            // Action buttons
            HStack(spacing: 16) {
                Button(action: onRetake) {
                    Label("Retake", systemImage: "arrow.counterclockwise")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .cornerRadius(12)
                }

                Button(action: onConfirm) {
                    Label("Analyze", systemImage: "sparkles")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(accentColor)
                        .cornerRadius(12)
                }
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .keyboardDismissible()
        .onTapGesture {
            KeyboardDismiss.dismiss()
        }
    }
}

// MARK: - Food Analyzing View

struct FoodAnalyzingView: View {
    var accentColor: Color = .pink
    @State private var animationPhase = 0

    let tips = [
        "AI is analyzing your food...",
        "Estimating portion size...",
        "Calculating nutritional values...",
        "Almost there..."
    ]

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Animated icon
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.1))
                    .frame(width: 120, height: 120)

                Image(systemName: "sparkles")
                    .font(.system(size: 50))
                    .foregroundStyle(accentColor)
                    .symbolEffect(.pulse, options: .repeating)
            }

            Text(tips[animationPhase % tips.count])
                .font(.headline)
                .foregroundStyle(.secondary)
                .animation(.easeInOut, value: animationPhase)

            ProgressView()
                .scaleEffect(1.2)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
        .onAppear {
            // Cycle through tips
            Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
                animationPhase += 1
            }
        }
    }
}

// MARK: - Food Error View

struct FoodErrorView: View {
    let message: String
    let onRetry: () -> Void
    var accentColor: Color = .pink

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.orange)

            Text("Analysis Failed")
                .font(.title2)
                .fontWeight(.semibold)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button(action: onRetry) {
                Label("Try Again", systemImage: "arrow.counterclockwise")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding()
                    .frame(maxWidth: 200)
                    .background(accentColor)
                    .cornerRadius(12)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }
}

// MARK: - VLM Download View

struct VLMDownloadView: View {
    @Bindable var visionManager: VisionModelManager
    var onComplete: () -> Void
    var onCancel: () -> Void
    var accentColor: Color = .pink

    @State private var pulseScale: CGFloat = 1.0
    @State private var tipIndex = 0
    @State private var hasCompleted = false

    private let tips = [
        "Vision AI runs entirely on your device",
        "Your food photos stay private",
        "No internet needed after download",
        "AI-powered nutrition estimation"
    ]

    private let timer = Timer.publish(every: 4, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    accentColor.opacity(0.15),
                    accentColor.opacity(0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // Animated icon
                ZStack {
                    // Outer pulsing rings
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .stroke(accentColor.opacity(0.2 - Double(i) * 0.05), lineWidth: 2)
                            .frame(width: 140 + CGFloat(i) * 30, height: 140 + CGFloat(i) * 30)
                            .scaleEffect(pulseScale)
                    }

                    // Progress ring background
                    Circle()
                        .stroke(accentColor.opacity(0.2), lineWidth: 8)
                        .frame(width: 120, height: 120)

                    // Progress ring
                    Circle()
                        .trim(from: 0, to: visionManager.loadingProgress)
                        .stroke(
                            LinearGradient(
                                colors: [accentColor, .orange],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .frame(width: 120, height: 120)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.3), value: visionManager.loadingProgress)

                    // Center icon
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [accentColor, .orange],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 80, height: 80)

                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 35))
                            .foregroundStyle(.white)
                    }
                }

                // Title and status
                VStack(spacing: 12) {
                    Text("Preparing Vision AI")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text(visionManager.status)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    if visionManager.loadingProgress > 0 && visionManager.loadingProgress < 1 {
                        Text("\(Int(visionManager.loadingProgress * 100))%")
                            .font(.headline)
                            .foregroundStyle(accentColor)
                    }
                }

                // Rotating tips
                Text(tips[tipIndex])
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .animation(.easeInOut, value: tipIndex)

                Spacer()

                // Memory info
                Text("Model: \(visionManager.currentTier.displayName) (~\(String(format: "%.1f", visionManager.currentTier.estimatedMemoryGB)) GB)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                // Cancel button
                Button("Cancel") {
                    onCancel()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.bottom, 20)
            }
            .padding()
        }
        .onAppear {
            startAnimations()
            startLoading()
        }
        .onReceive(timer) { _ in
            withAnimation {
                tipIndex = (tipIndex + 1) % tips.count
            }
        }
        .onChange(of: visionManager.isModelLoaded) { _, isLoaded in
            if isLoaded && !hasCompleted {
                hasCompleted = true
                // Small delay for visual feedback
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    onComplete()
                }
            }
        }
    }

    private func startAnimations() {
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            pulseScale = 1.1
        }
    }

    private func startLoading() {
        Task {
            await visionManager.loadModelIfNeeded()
        }
    }
}

// MARK: - Preview

#Preview {
    FoodCameraSheet()
}
