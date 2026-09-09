import AVFoundation
import AppKit
import SwiftUI
import Vision

struct CompanionCameraPreview: NSViewRepresentable {
    var onCode: (String) -> Void

    func makeNSView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.onCode = onCode
        view.start()
        return view
    }

    func updateNSView(_ nsView: CameraPreviewView, context: Context) {
        nsView.onCode = onCode
    }

    static func dismantleNSView(_ nsView: CameraPreviewView, coordinator: ()) {
        nsView.stop()
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

    func start() {
        queue.async { [weak self] in
            self?.configureAndStart()
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.session.stopRunning()
        }
    }

    private func configureAndStart() {
        session.beginConfiguration()
        session.sessionPreset = .high
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(output) {
            session.addOutput(output)
        }
        session.commitConfiguration()
        session.startRunning()
    }

    override func layout() {
        super.layout()
        preview.frame = bounds
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
