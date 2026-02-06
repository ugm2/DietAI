import AVFoundation
import UIKit

// MARK: - Barcode Scanner Delegate

protocol BarcodeScannerDelegate: AnyObject {
    func barcodeScannerDidDetect(barcode: String)
    func barcodeScannerDidFail(error: BarcodeScannerError)
}

// MARK: - Barcode Scanner Error

enum BarcodeScannerError: LocalizedError {
    case cameraNotAvailable
    case cameraAccessDenied
    case cameraAccessRestricted
    case setupFailed(Error)

    var errorDescription: String? {
        switch self {
        case .cameraNotAvailable:
            return "Camera is not available on this device"
        case .cameraAccessDenied:
            return "Camera access was denied. Please enable it in Settings."
        case .cameraAccessRestricted:
            return "Camera access is restricted on this device"
        case .setupFailed(let error):
            return "Failed to setup camera: \(error.localizedDescription)"
        }
    }
}

// MARK: - Barcode Scanner Service

final class BarcodeScannerService: NSObject {
    weak var delegate: BarcodeScannerDelegate?

    private let captureSession = AVCaptureSession()
    private var videoPreviewLayer: AVCaptureVideoPreviewLayer?
    private let metadataQueue = DispatchQueue(label: "com.dietai.barcode.metadata")

    private var isConfigured = false
    private var lastScannedBarcode: String?
    private var lastScanTime: Date?

    // Debounce interval to prevent duplicate scans
    private let debounceInterval: TimeInterval = 2.0

    // Supported barcode types for food products
    private let supportedBarcodeTypes: [AVMetadataObject.ObjectType] = [
        .ean8,
        .ean13,
        .upce,
        .code128,
        .code39,
        .code93,
        .itf14
    ]

    var previewLayer: AVCaptureVideoPreviewLayer? {
        videoPreviewLayer
    }

    var isRunning: Bool {
        captureSession.isRunning
    }

    var isTorchAvailable: Bool {
        guard let device = AVCaptureDevice.default(for: .video) else { return false }
        return device.hasTorch
    }

    var isTorchOn: Bool {
        guard let device = AVCaptureDevice.default(for: .video) else { return false }
        return device.torchMode == .on
    }

    // MARK: - Authorization

    static var authorizationStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    static func requestCameraAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    // MARK: - Setup

    func configure() throws {
        guard !isConfigured else { return }

        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            throw BarcodeScannerError.cameraNotAvailable
        }

        switch Self.authorizationStatus {
        case .denied:
            throw BarcodeScannerError.cameraAccessDenied
        case .restricted:
            throw BarcodeScannerError.cameraAccessRestricted
        case .notDetermined, .authorized:
            break
        @unknown default:
            break
        }

        do {
            try setupCaptureSession()
            isConfigured = true
        } catch {
            throw BarcodeScannerError.setupFailed(error)
        }
    }

    private func setupCaptureSession() throws {
        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }

        // Set session preset
        if captureSession.canSetSessionPreset(.high) {
            captureSession.sessionPreset = .high
        }

        // Add video input
        guard let videoDevice = AVCaptureDevice.default(for: .video) else {
            throw BarcodeScannerError.cameraNotAvailable
        }

        let videoInput = try AVCaptureDeviceInput(device: videoDevice)
        guard captureSession.canAddInput(videoInput) else {
            throw BarcodeScannerError.cameraNotAvailable
        }
        captureSession.addInput(videoInput)

        // Add metadata output for barcode detection
        let metadataOutput = AVCaptureMetadataOutput()
        guard captureSession.canAddOutput(metadataOutput) else {
            throw BarcodeScannerError.cameraNotAvailable
        }
        captureSession.addOutput(metadataOutput)

        // Configure metadata output
        metadataOutput.setMetadataObjectsDelegate(self, queue: metadataQueue)

        // Filter to only supported barcode types that are available
        let availableTypes = metadataOutput.availableMetadataObjectTypes
        let typesToUse = supportedBarcodeTypes.filter { availableTypes.contains($0) }
        metadataOutput.metadataObjectTypes = typesToUse

        // Create preview layer
        videoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        videoPreviewLayer?.videoGravity = .resizeAspectFill
    }

    // MARK: - Control

    func startScanning() {
        guard isConfigured, !captureSession.isRunning else { return }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.startRunning()
        }
    }

    func stopScanning() {
        guard captureSession.isRunning else { return }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.stopRunning()
        }
    }

    func resetScanState() {
        lastScannedBarcode = nil
        lastScanTime = nil
    }

    // MARK: - Torch Control

    func toggleTorch() {
        guard let device = AVCaptureDevice.default(for: .video),
              device.hasTorch else { return }

        do {
            try device.lockForConfiguration()
            device.torchMode = device.torchMode == .on ? .off : .on
            device.unlockForConfiguration()
        } catch {
            // Silently fail torch toggle
        }
    }

    func setTorch(on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video),
              device.hasTorch else { return }

        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
        } catch {
            // Silently fail torch setting
        }
    }
}

// MARK: - AVCaptureMetadataOutputObjectsDelegate

extension BarcodeScannerService: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let barcode = metadataObject.stringValue else {
            return
        }

        // Debounce to prevent rapid duplicate scans
        let now = Date()
        if let lastBarcode = lastScannedBarcode,
           let lastTime = lastScanTime,
           lastBarcode == barcode,
           now.timeIntervalSince(lastTime) < debounceInterval {
            return
        }

        lastScannedBarcode = barcode
        lastScanTime = now

        // Haptic feedback
        DispatchQueue.main.async {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        }

        // Notify delegate on main thread
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.barcodeScannerDidDetect(barcode: barcode)
        }
    }
}
