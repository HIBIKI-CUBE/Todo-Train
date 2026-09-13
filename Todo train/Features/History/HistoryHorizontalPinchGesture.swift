//
//  HistoryHorizontalPinchGesture.swift
//  Todo train
//
//  Two-finger pinch that recognizes only when the span is (or becomes) horizontal.
//  Must not require UIScrollView's pan to wait — a 1-finger pinch stays `.possible`
//  until lift, so `shouldBeRequiredToFailBy` would delay every scroll/swipe by a beat.
//

import SwiftUI
import UIKit

final class HistoryHorizontalPinchRecognizer: UIGestureRecognizer {
    private(set) var magnification: CGFloat = 1

    private var startLocations: [CGPoint] = []
    private var startSpanX: CGFloat = 0
    private var locked = false

    override func reset() {
        super.reset()
        magnification = 1
        startLocations = []
        startSpanX = 0
        locked = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        if numberOfTouches > 2 {
            state = .failed
            return
        }
        if numberOfTouches == 2 {
            captureStart()
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        guard numberOfTouches == 2, let view else { return }
        let points = touchPoints(in: view)
        guard points.count == 2 else { return }

        if !locked {
            if startLocations.count != 2 {
                captureStart()
                return
            }
            let spanX = points[1].x - points[0].x
            let spanY = points[1].y - points[0].y
            if let pose = HistoryCanvasZoom.pinchAxisFromSpan(spanX: spanX, spanY: spanY) {
                applyLock(pose, spanX: spanX)
                return
            }
            let deltaSpanX = spanX - (startLocations[1].x - startLocations[0].x)
            let deltaSpanY = spanY - (startLocations[1].y - startLocations[0].y)
            if let motion = HistoryCanvasZoom.pinchAxis(deltaSpanX: deltaSpanX, deltaSpanY: deltaSpanY) {
                applyLock(motion, spanX: spanX)
            }
            return
        }

        let spanX = points[1].x - points[0].x
        magnification = HistoryCanvasZoom.horizontalMagnification(
            startSpanX: startSpanX,
            currentSpanX: spanX
        )
        if state == .began || state == .changed {
            state = .changed
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        if state == .began || state == .changed {
            state = .ended
        } else {
            state = .failed
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        if state == .began || state == .changed {
            state = .cancelled
        } else {
            state = .failed
        }
    }

    private func applyLock(_ axis: HistoryCanvasZoom.GestureAxis, spanX: CGFloat) {
        switch axis {
        case .vertical:
            state = .failed
        case .horizontal:
            locked = true
            startSpanX = spanX
            magnification = 1
            state = .began
        }
    }

    private func captureStart() {
        guard numberOfTouches == 2, let view else { return }
        startLocations = touchPoints(in: view)
        if startLocations.count == 2 {
            startSpanX = startLocations[1].x - startLocations[0].x
        }
    }

    private func touchPoints(in view: UIView) -> [CGPoint] {
        (0..<numberOfTouches).map { location(ofTouch: $0, in: view) }
    }
}

struct HistoryHorizontalPinchGesture: UIGestureRecognizerRepresentable {
    var onChanged: (CGFloat) -> Void
    var onEnded: (CGFloat) -> Void
    var onCancelled: () -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> HistoryHorizontalPinchRecognizer {
        let pinch = HistoryHorizontalPinchRecognizer()
        pinch.delegate = context.coordinator
        pinch.cancelsTouchesInView = false
        pinch.delaysTouchesBegan = false
        pinch.delaysTouchesEnded = false
        return pinch
    }

    func handleUIGestureRecognizerAction(
        _ recognizer: HistoryHorizontalPinchRecognizer,
        context: Context
    ) {
        switch recognizer.state {
        case .began, .changed:
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                onChanged(recognizer.magnification)
            }
        case .ended:
            onEnded(recognizer.magnification)
        case .cancelled, .failed:
            onCancelled()
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            false
        }
    }
}
