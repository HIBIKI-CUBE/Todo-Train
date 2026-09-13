import AVFoundation
import AppKit
import SwiftUI
import Vision

struct CompanionCameraPreview: NSViewRepresentable {
    var onCode: (String) -> Void
    var isActive: Bool
    var scanGeneration: Int = 0

    func makeNSView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.onCode = onCode
        view.setGeneration(scanGeneration)
        view.setActive(isActive)
        return view
    }

    func updateNSView(_ nsView: CameraPreviewView, context: Context) {
        nsView.onCode = onCode
        nsView.setGeneration(scanGeneration)
        nsView.setActive(isActive)
    }

    static func dismantleNSView(_ nsView: CameraPreviewView, coordinator: ()) {
        nsView.setActive(false)
    }
}

final class CameraPreviewView: NSView {
    var onCode: ((String) -> Void)?

    private let session = AVCaptureSession()
    private let preview = AVCaptureVideoPreviewLayer()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "todotrain.companion.camera")
    private var lastValue: String?
    private var lastAt = Date.distantPast
    private var wantsRunning = false
    private var generation = 0
    private var occlusionObserver: NSObjectProtocol?
    private var closeObserver: NSObjectProtocol?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        preview.videoGravity = .resizeAspectFill
        preview.session = session
        layer = preview
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        if let occlusionObserver {
            NotificationCenter.default.removeObserver(occlusionObserver)
        }
        if let closeObserver {
            NotificationCenter.default.removeObserver(closeObserver)
        }
        output.setSampleBufferDelegate(nil, queue: nil)
        let session = session
        let preview = preview
        queue.async {
            CameraPreviewView.tearDown(session: session, preview: preview)
        }
    }

    func setGeneration(_ value: Int) {
        guard generation != value else { return }
        generation = value
        lastValue = nil
        lastAt = Date.distantPast
    }

    func setActive(_ active: Bool) {
        let changed = wantsRunning != active
        wantsRunning = active
        if changed {
            applyDesiredState()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        unbindWindowObservers()
        if let window {
            bindWindowObservers(window)
        }
        applyDesiredState()
    }

    override func layout() {
        super.layout()
        preview.frame = bounds
    }

    private func applyDesiredState() {
        let shouldRun = wantsRunning && isShownInWindow
        if shouldRun {
            startIfNeeded()
        } else {
            stopNow()
        }
    }

    private var isShownInWindow: Bool {
        guard let window, !window.isMiniaturized else { return false }
        return window.isVisible && window.occlusionState.contains(.visible)
    }

    private func bindWindowObservers(_ window: NSWindow) {
        occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.applyDesiredState()
        }
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.setActive(false)
        }
    }

    private func unbindWindowObservers() {
        if let occlusionObserver {
            NotificationCenter.default.removeObserver(occlusionObserver)
            self.occlusionObserver = nil
        }
        if let closeObserver {
            NotificationCenter.default.removeObserver(closeObserver)
            self.closeObserver = nil
        }
    }

    private func startIfNeeded() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            queue.async { [weak self] in
                self?.configureAndStart()
            }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard granted else { return }
                self?.queue.async { self?.configureAndStart() }
            }
        default:
            break
        }
    }

    private func stopNow() {
        output.setSampleBufferDelegate(nil, queue: nil)
        let session = session
        let preview = preview
        queue.async {
            CameraPreviewView.tearDown(session: session, preview: preview)
        }
    }

    private func configureAndStart() {
        guard wantsRunning else { return }
        if session.inputs.isEmpty {
            session.beginConfiguration()
            if session.canSetSessionPreset(.hd1280x720) {
                session.sessionPreset = .hd1280x720
            } else {
                session.sessionPreset = .high
            }
            if let device = AVCaptureDevice.default(for: .video),
               let input = try? AVCaptureDeviceInput(device: device),
               session.canAddInput(input) {
                session.addInput(input)
            }
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: queue)
            if session.canAddOutput(output) {
                session.addOutput(output)
            }
            session.commitConfiguration()
        } else {
            output.setSampleBufferDelegate(self, queue: queue)
        }
        guard !session.inputs.isEmpty, !session.isRunning else { return }
        session.startRunning()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.preview.session = self.session
        }
    }

    private static func tearDown(session: AVCaptureSession, preview: AVCaptureVideoPreviewLayer) {
        if session.isRunning {
            session.stopRunning()
        }
        session.beginConfiguration()
        for input in session.inputs {
            session.removeInput(input)
        }
        for output in session.outputs {
            session.removeOutput(output)
        }
        session.commitConfiguration()
        DispatchQueue.main.async {
            preview.session = nil
        }
    }
}

extension CameraPreviewView: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard Date().timeIntervalSince(lastAt) > 0.4 else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let request = VNDetectBarcodesRequest { [weak self] request, _ in
            guard let self else { return }
            let payload = request.results?
                .compactMap { $0 as? VNBarcodeObservation }
                .compactMap(\.payloadStringValue)
                .first { $0.hasPrefix("todotrain://") }
            guard let payload, payload != self.lastValue else { return }
            self.lastValue = payload
            self.lastAt = Date()
            DispatchQueue.main.async {
                self.onCode?(payload)
            }
        }
        request.symbologies = [.qr]
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try? handler.perform([request])
    }
}
