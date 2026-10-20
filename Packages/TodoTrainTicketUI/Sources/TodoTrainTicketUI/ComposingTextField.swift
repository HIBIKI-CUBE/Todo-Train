//
//  ComposingTextField.swift
//
//  Sheet + SwiftUI.TextField drops the first Japanese IME glyph from 変換.
//  Wrap the platform field and never assign text while marked text exists.
//

import SwiftUI

#if os(iOS)
import UIKit

public struct ComposingTextField: UIViewRepresentable {
    @Binding var text: String
    public var placeholder: String
    /// Increment to request keyboard without going through @FocusState.
    public var focusNonce: Int
    public var onSubmit: () -> Void

    public init(
        text: Binding<String>,
        placeholder: String,
        focusNonce: Int,
        onSubmit: @escaping () -> Void
    ) {
        _text = text
        self.placeholder = placeholder
        self.focusNonce = focusNonce
        self.onSubmit = onSubmit
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public func makeUIView(context: Context) -> UITextField {
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

    public func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.onSubmit = onSubmit

        if uiView.markedTextRange == nil, uiView.text != text {
            uiView.text = text
        }

        guard context.coordinator.lastFocusNonce != focusNonce else { return }
        if uiView.window == nil {
            Task { @MainActor in
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
    public final class Coordinator: NSObject, UITextFieldDelegate {
        var text: Binding<String>?
        var onSubmit: (() -> Void)?
        var lastFocusNonce: Int = 0

        @objc func editingChanged(_ field: UITextField) {
            let next = field.text ?? ""
            if text?.wrappedValue != next {
                text?.wrappedValue = next
            }
        }

        public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            guard textField.markedTextRange == nil else { return false }
            onSubmit?()
            return false
        }
    }
}

private final class OneLineTextField: UITextField {
    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: super.intrinsicContentSize.height)
    }
}

#elseif os(macOS)
import AppKit

public struct ComposingTextField: NSViewRepresentable {
    @Binding var text: String
    public var placeholder: String
    public var focusNonce: Int
    public var onSubmit: () -> Void

    public init(
        text: Binding<String>,
        placeholder: String,
        focusNonce: Int,
        onSubmit: @escaping () -> Void
    ) {
        _text = text
        self.placeholder = placeholder
        self.focusNonce = focusNonce
        self.onSubmit = onSubmit
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: "")
        field.placeholderString = placeholder
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 22, weight: .semibold)
        field.delegate = context.coordinator
        field.cell?.sendsActionOnEndEditing = false
        field.target = context.coordinator
        field.action = #selector(Coordinator.submit(_:))
        return field
    }

    public func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.onSubmit = onSubmit
        let marked = Self.hasMarkedText(nsView.currentEditor())
        if !marked, nsView.stringValue != text {
            nsView.stringValue = text
        }
        guard context.coordinator.lastFocusNonce != focusNonce else { return }
        context.coordinator.lastFocusNonce = focusNonce
        nsView.window?.makeFirstResponder(nsView)
    }

    private static func hasMarkedText(_ editor: NSText?) -> Bool {
        (editor as? NSTextView)?.hasMarkedText() == true
    }

    @MainActor
    public final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>?
        var onSubmit: (() -> Void)?
        var lastFocusNonce: Int = 0

        @objc func submit(_ sender: NSTextField) {
            guard !ComposingTextField.hasMarkedText(sender.currentEditor()) else { return }
            onSubmit?()
        }

        public func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            if ComposingTextField.hasMarkedText(field.currentEditor()) { return }
            let next = field.stringValue
            if text?.wrappedValue != next {
                text?.wrappedValue = next
            }
        }
    }
}
#endif
