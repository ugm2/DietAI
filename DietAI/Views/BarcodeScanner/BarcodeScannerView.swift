import SwiftUI
import SwiftData
import AVFoundation

// MARK: - Barcode Scanner Sheet

struct BarcodeScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var scannerState: ScannerState = .scanning
    @State private var scannedProduct: ScannedProduct?
    @State private var errorMessage: String?

    private let scannerService = BarcodeScannerService()
    private let foodService = FoodDatabaseService.shared

    enum ScannerState {
        case scanning
        case loading
        case productFound
        case error
    }

    var body: some View {
        NavigationStack {
            ZStack {
                switch scannerState {
                case .scanning:
                    BarcodeScannerCameraView(
                        scannerService: scannerService,
                        onBarcodeDetected: handleBarcodeDetected
                    )

                case .loading:
                    loadingView

                case .productFound:
                    if let product = scannedProduct {
                        ScannedProductResultView(
                            product: product,
                            onLog: { mealType, servingGrams, date in
                                logMeal(product: product, mealType: mealType, servingGrams: servingGrams, date: date)
                                dismiss()
                            },
                            onScanAgain: {
                                resetToScanning()
                            }
                        )
                    }

                case .error:
                    ProductNotFoundView(
                        message: errorMessage ?? "Product not found",
                        onTryAgain: resetToScanning,
                        onEnterManually: { dismiss() }
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

    private var navigationTitle: String {
        switch scannerState {
        case .scanning: return "Scan Barcode"
        case .loading: return "Looking up..."
        case .productFound: return "Product Found"
        case .error: return "Not Found"
        }
    }

    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Looking up product...")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private func handleBarcodeDetected(_ barcode: String) {
        guard scannerState == .scanning else { return }

        scannerState = .loading
        scannerService.stopScanning()

        Task {
            do {
                let product = try await foodService.fetchProduct(barcode: barcode)
                scannedProduct = product
                scannerState = .productFound
            } catch let error as FoodDatabaseError {
                errorMessage = error.localizedDescription
                scannerState = .error
            } catch {
                errorMessage = "An unexpected error occurred"
                scannerState = .error
            }
        }
    }

    private func resetToScanning() {
        scannedProduct = nil
        errorMessage = nil
        scannerService.resetScanState()
        scannerState = .scanning
        scannerService.startScanning()
    }

    private func logMeal(product: ScannedProduct, mealType: MealType, servingGrams: Double, date: Date) {
        let nutrition = product.nutritionFor(grams: servingGrams)

        let log = MealLog(
            name: product.displayName,
            type: mealType,
            calories: nutrition.calories,
            protein: nutrition.protein,
            carbs: nutrition.carbs,
            fat: nutrition.fat,
            loggedAt: date
        )

        modelContext.insert(log)
        try? modelContext.save()
    }
}

// MARK: - Camera Preview View

struct BarcodeScannerCameraView: View {
    let scannerService: BarcodeScannerService
    let onBarcodeDetected: (String) -> Void

    @State private var permissionStatus: AVAuthorizationStatus = BarcodeScannerService.authorizationStatus
    @State private var isSetup = false
    @State private var setupError: String?
    @State private var isTorchOn = false
    @State private var barcodeDelegate: BarcodeDelegate?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if permissionStatus == .authorized && isSetup {
                    // Camera preview
                    CameraPreviewView(scannerService: scannerService)
                        .ignoresSafeArea()

                    // Scanning overlay
                    scanningOverlay(geometry: geometry)

                    // Torch button
                    if scannerService.isTorchAvailable {
                        torchButton
                    }

                    // Instructions
                    instructionsView

                } else if permissionStatus == .denied || permissionStatus == .restricted {
                    permissionDeniedView
                } else if let error = setupError {
                    errorView(message: error)
                } else {
                    ProgressView("Setting up camera...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black)
                }
            }
        }
        .task {
            await setupCamera()
        }
        .onDisappear {
            scannerService.stopScanning()
            scannerService.setTorch(on: false)
        }
    }

    private func scanningOverlay(geometry: GeometryProxy) -> some View {
        let scanAreaSize = min(geometry.size.width * 0.7, 280.0)

        return ZStack {
            // Dimmed background
            Color.black.opacity(0.5)
                .ignoresSafeArea()

            // Clear scanning area
            RoundedRectangle(cornerRadius: 16)
                .frame(width: scanAreaSize, height: scanAreaSize)
                .blendMode(.destinationOut)

            // Scanning frame border
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white, lineWidth: 3)
                .frame(width: scanAreaSize, height: scanAreaSize)

            // Corner accents
            scanningCorners(size: scanAreaSize)
        }
        .compositingGroup()
    }

    private func scanningCorners(size: CGFloat) -> some View {
        let cornerLength: CGFloat = 30
        let cornerWidth: CGFloat = 4

        return ZStack {
            ForEach(0..<4, id: \.self) { index in
                ScannerCorner(length: cornerLength, width: cornerWidth)
                    .rotationEffect(.degrees(Double(index) * 90))
                    .offset(
                        x: (size / 2 - cornerLength / 2) * (index == 1 || index == 2 ? 1 : -1),
                        y: (size / 2 - cornerLength / 2) * (index >= 2 ? 1 : -1)
                    )
            }
        }
        .foregroundStyle(.green)
    }

    private var torchButton: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button {
                    scannerService.toggleTorch()
                    isTorchOn = scannerService.isTorchOn
                } label: {
                    Image(systemName: isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .padding(14)
                        .background(Circle().fill(Color.black.opacity(0.6)))
                }
                .padding()
            }
            .padding(.bottom, 100)
        }
    }

    private var instructionsView: some View {
        VStack {
            Spacer()
            Text("Position barcode within the frame")
                .font(.subheadline)
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Capsule().fill(Color.black.opacity(0.6)))
                .padding(.bottom, 40)
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

            Text("Please enable camera access in Settings to scan barcodes.")
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
            let granted = await BarcodeScannerService.requestCameraAccess()
            permissionStatus = granted ? .authorized : .denied
        }

        guard permissionStatus == .authorized else { return }

        // Configure scanner
        do {
            try scannerService.configure()
            let delegate = BarcodeDelegate(onDetected: onBarcodeDetected)
            barcodeDelegate = delegate
            scannerService.delegate = delegate
            scannerService.startScanning()
            isSetup = true
        } catch let error as BarcodeScannerError {
            setupError = error.localizedDescription
        } catch {
            setupError = "Failed to setup camera"
        }
    }
}

// MARK: - Barcode Delegate Wrapper

private class BarcodeDelegate: BarcodeScannerDelegate {
    let onDetected: (String) -> Void

    init(onDetected: @escaping (String) -> Void) {
        self.onDetected = onDetected
    }

    func barcodeScannerDidDetect(barcode: String) {
        onDetected(barcode)
    }

    func barcodeScannerDidFail(error: BarcodeScannerError) {
        // Handle error if needed
    }
}

// MARK: - Camera Preview UIViewRepresentable

struct CameraPreviewView: UIViewRepresentable {
    let scannerService: BarcodeScannerService

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .black

        if let previewLayer = scannerService.previewLayer {
            previewLayer.frame = view.bounds
            view.layer.addSublayer(previewLayer)
        }

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            scannerService.previewLayer?.frame = uiView.bounds
        }
    }
}

// MARK: - Scanner Corner Shape

struct ScannerCorner: View {
    let length: CGFloat
    let width: CGFloat

    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: length))
            path.addLine(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: length, y: 0))
        }
        .stroke(style: StrokeStyle(lineWidth: width, lineCap: .round))
    }
}
