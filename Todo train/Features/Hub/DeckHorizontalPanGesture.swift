//
//  DeckHorizontalPanGesture.swift
//  Todo train
//
//  Horizontal-only pan that fails to begin when the first move is vertical,
//  so ScrollView keeps the scroll. Simultaneous SwiftUI DragGesture was
//  fighting the scroll pan and jittering the ticket on X.
//

import SwiftUI
import UIKit

struct DeckHorizontalPanGesture: UIGestureRecognizerRepresentable {
    var isEnabled: Bool = true
    var cancelsTouchesInView: Bool = false
    var onChanged: (CGFloat) -> Void
    var onEnded: (_ translationX: CGFloat, _ predictedX: CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        pan.maximumNumberOfTouches = 1
        pan.cancelsTouchesInView = cancelsTouchesInView
        pan.delaysTouchesBegan = false
        pan.isEnabled = isEnabled
        return pan
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        recognizer.isEnabled = isEnabled
        recognizer.cancelsTouchesInView = cancelsTouchesInView
    }

    func handleUIGestureRecognizerAction(
        _ recognizer: UIPanGestureRecognizer,
        context: Context
    ) {
        let x = recognizer.translation(in: recognizer.view).x
        let vx = recognizer.velocity(in: recognizer.view).x
        switch recognizer.state {
        case .began, .changed:
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                onChanged(x)
            }
        case .ended, .cancelled:
            onEnded(x, x + vx * 0.25)
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            let translation = pan.translation(in: pan.view)
            let dx: CGFloat
            let dy: CGFloat
            if hypot(velocity.x, velocity.y) > 8 {
                dx = abs(velocity.x)
                dy = abs(velocity.y)
            } else {
                dx = abs(translation.x)
                dy = abs(translation.y)
            }
            return dx > dy
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            false
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            otherGestureRecognizer.view is UIScrollView
        }
    }
}
