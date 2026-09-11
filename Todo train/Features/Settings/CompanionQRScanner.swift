import SwiftUI
import VisionKit

struct CompanionQRScanner: UIViewControllerRepresentable {
    var onCode: (String) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        if DataScannerViewController.isSupported, DataScannerViewController.isAvailable {
            let scanner = DataScannerViewController(
                recognizedDataTypes: [.barcode(symbologies: [.qr])],
                qualityLevel: .fast,
                recognizesMultipleItems: false,
                isHighFrameRateTrackingEnabled: true,
                isHighlightingEnabled: true
            )
            scanner.delegate = context.coordinator
            context.coordinator.scanner = scanner
            return scanner
        }
        return UIViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        if let scanner = uiViewController as? DataScannerViewController, !scanner.isScanning {
            try? scanner.startScanning()
        }
    }

    static func dismantleUIViewController(_ uiViewController: UIViewController, coordinator: Coordinator) {
        (uiViewController as? DataScannerViewController)?.stopScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onCode: onCode)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onCode: (String) -> Void
        weak var scanner: DataScannerViewController?
        private var didEmit = false

        init(onCode: @escaping (String) -> Void) {
            self.onCode = onCode
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            guard !didEmit else { return }
            for item in addedItems {
                if case .barcode(let barcode) = item, let payload = barcode.payloadStringValue {
                    didEmit = true
                    dataScanner.stopScanning()
                    onCode(payload)
                    return
                }
            }
        }
    }
}

enum CompanionScannerSupport {
    static var isCameraUsable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }
}
