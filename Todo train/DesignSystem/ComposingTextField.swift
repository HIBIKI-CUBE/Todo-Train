//
//  ComposingTextField.swift
//  Todo train
//
//  Sheet + SwiftUI.TextField drops the first Japanese IME glyph from 変換.
//  Wrap UITextField and never assign `.text` while marked text exists.
//  Never resign first responder from updateUIView — that dismisses the keyboard
//  on the first keystroke when SwiftUI re-renders.
//

import SwiftUI
import UIKit

struct ComposingTextField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    /// Increment to request keyboard without going through @FocusState.
    var focusNonce: Int
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UITextField {
        let field = OneLineTextField()
        field.placeholder = placeholder
        field.font = Self.titleFont
        field.adjustsFontForContentSizeCategory = true
        field.borderStyle = .none
        field.returnKeyType = .go
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.smartQuotesType = .no
        field.smartDashesType = .no
        field.smartInsertDeleteType = .no
        field.delegate = context.coordinator
        field.setContentHuggingPriority(.required, for: .vertical)
        field.setContentCompressionResistancePriority(.required, for: .vertical)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.addTarget(
            context.coordinator,
            action: #selector(Coordinator.editingChanged(_:)),
            for: .editingChanged
        )
        return field
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.onSubmit = onSubmit

        if uiView.markedTextRange == nil, uiView.text != text {
            uiView.text = text
        }

        guard context.coordinator.lastFocusNonce != focusNonce else { return }
        if uiView.window == nil {
            DispatchQueue.main.async {
                guard uiView.window != nil else { return }
                context.coordinator.lastFocusNonce = focusNonce
                if !uiView.isFirstResponder {
                    uiView.becomeFirstResponder()
                }
            }
            return
        }
        context.coordinator.lastFocusNonce = focusNonce
        if !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        }
    }

    private static var titleFont: UIFont {
        let size = UIFont.preferredFont(forTextStyle: .title2).pointSize
        return UIFontMetrics(forTextStyle: .title2).scaledFont(
            for: UIFont.systemFont(ofSize: size, weight: .semibold)
        )
    }

    @MainActor
    final class Coordinator: NSObject, UITextFieldDelegate {
        var text: Binding<String>?
        var onSubmit: (() -> Void)?
        var lastFocusNonce: Int = 0

        @objc func editingChanged(_ field: UITextField) {
            let next = field.text ?? ""
            if text?.wrappedValue != next {
                text?.wrappedValue = next
            }
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            guard textField.markedTextRange == nil else { return false }
            onSubmit?()
            return false
        }
    }
}

/// UITextField reports flexible height to SwiftUI and will fill a VStack.
private final class OneLineTextField: UITextField {
    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: super.intrinsicContentSize.height)
    }
}
