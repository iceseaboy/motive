//
//  CommandBarTextField.swift
//  Motive
//
//  Created by geezerrrr on 2026/1/19.
//

import AppKit
import SwiftUI

struct CommandBarTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var isDisabled: Bool
    var onSubmit: () -> Void
    var onCmdDelete: () -> Void
    var onCmdN: (() -> Void)?
    var onCmdReturn: (() -> Void)?
    var onEscape: (() -> Void)?

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.delegate = context.coordinator
        textField.isBordered = false
        textField.drawsBackground = false
        textField.font = NSFont.systemFont(ofSize: 17, weight: .regular)
        textField.textColor = NSColor(Color.Aurora.textPrimary)
        textField.focusRingType = .none
        textField.cell?.truncatesLastVisibleLine = true

        // Custom placeholder color for readability on translucent glass
        // System placeholderTextColor (~#C5C5C7) is nearly invisible on bright glass
        let placeholderColor = NSColor(name: nil) { appearance in
            appearance.isDark
                ? NSColor(white: 1.0, alpha: 0.25)
                : NSColor(hex: "757575")
        }
        textField.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [
                .font: NSFont.systemFont(ofSize: 17, weight: .regular),
                .foregroundColor: placeholderColor,
            ]
        )

        // Set up keyboard event monitor
        context.coordinator.setupKeyboardMonitor()

        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        // IMPORTANT: Do NOT update stringValue during IME composition.
        // When the field editor has marked text (uncommitted IME input like
        // pinyin), setting stringValue would cancel the composition, trigger
        // a cascade of controlTextDidChange → binding update → re-render,
        // and potentially desync the window height.
        if let fieldEditor = nsView.currentEditor() as? NSTextView,
           fieldEditor.hasMarkedText()
        {
            // Skip stringValue update — let the IME handle composition.
        } else if nsView.stringValue != text {
            nsView.stringValue = text
        }
        // Update placeholder with custom color (matches makeNSView)
        let placeholderColor = NSColor(name: nil) { appearance in
            appearance.isDark
                ? NSColor(white: 1.0, alpha: 0.25)
                : NSColor(hex: "757575")
        }
        nsView.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [
                .font: NSFont.systemFont(ofSize: 17, weight: .regular),
                .foregroundColor: placeholderColor,
            ]
        )
        nsView.isEnabled = !isDisabled

        // Update callbacks
        context.coordinator.onCmdDelete = onCmdDelete
        context.coordinator.onCmdN = onCmdN
        context.coordinator.onCmdReturn = onCmdReturn
        context.coordinator.onEscape = onEscape
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    static func dismantleNSView(_ nsView: NSTextField, coordinator: Coordinator) {
        coordinator.removeKeyboardMonitor()
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: CommandBarTextField
        var onCmdDelete: (() -> Void)?
        var onCmdN: (() -> Void)?
        var onCmdReturn: (() -> Void)?
        var onEscape: (() -> Void)?
        private var keyboardMonitor: Any?

        init(_ parent: CommandBarTextField) {
            self.parent = parent
            self.onCmdDelete = parent.onCmdDelete
            self.onCmdN = parent.onCmdN
            self.onCmdReturn = parent.onCmdReturn
            self.onEscape = parent.onEscape
        }

        func setupKeyboardMonitor() {
            keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self = self else { return event }

                // ESC key (keyCode 53) - no modifier required
                if event.keyCode == 53 {
                    self.onEscape?()
                    return nil  // Consume the event
                }

                // Check for Cmd modifier for other shortcuts
                guard event.modifierFlags.contains(.command) else { return event }

                // Cmd+Delete (backspace, keyCode 51)
                if event.keyCode == 51 {
                    self.onCmdDelete?()
                    return nil  // Consume the event
                }

                // Cmd+N (keyCode 45)
                if event.keyCode == 45 {
                    self.onCmdN?()
                    return nil  // Consume the event
                }

                // Cmd+Return (keyCode 36)
                if event.keyCode == 36 {
                    self.onCmdReturn?()
                    return nil  // Consume the event
                }

                return event
            }
        }

        func removeKeyboardMonitor() {
            if let monitor = keyboardMonitor {
                NSEvent.removeMonitor(monitor)
                keyboardMonitor = nil
            }
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let textField = obj.object as? NSTextField else { return }

            // Skip binding update during IME composition (marked text).
            // controlTextDidChange fires for BOTH committed text and intermediate
            // composition changes (e.g., pinyin keystrokes). Updating the binding
            // with intermediate composition text causes unnecessary SwiftUI
            // re-renders and can trigger handleInputChange with uncommitted text,
            // potentially desynchronizing the window height.
            if let fieldEditor = textField.currentEditor() as? NSTextView,
               fieldEditor.hasMarkedText()
            {
                return
            }

            parent.text = textField.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            return false
        }
    }
}
