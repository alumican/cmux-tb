import AppKit
import SwiftUI

// MARK: - Constants

private enum TextBoxLayout {
    static let fontSizeOffset: CGFloat = 1
    static let singleLineHeight: CGFloat = 20
    static let maxHeight: CGFloat = 100
    static let lineSpacing: CGFloat = 4
    static let textInset = NSSize(width: 2, height: 6)
    static let borderWidth: CGFloat = 1
    static let borderOpacity: CGFloat = 0.3
    static let cornerRadius: CGFloat = 6
    static let sendButtonSize: CGFloat = 18
    static let horizontalPadding: CGFloat = 8
    static let topPadding: CGFloat = 8
    static let bottomPadding: CGFloat = 8
}

// MARK: - Settings

/// Settings for TextBox Input Mode
enum TextBoxInputSettings {
    static let enabledKey = "textBoxInputEnabled"
    static let enterToSendKey = "textBoxEnterToSend"

    static let defaultEnabled = false
    static let defaultEnterToSend = true

    static func isEnabled() -> Bool {
        if UserDefaults.standard.object(forKey: enabledKey) == nil {
            return defaultEnabled
        }
        return UserDefaults.standard.bool(forKey: enabledKey)
    }

    static func isEnterToSend() -> Bool {
        if UserDefaults.standard.object(forKey: enterToSendKey) == nil {
            return defaultEnterToSend
        }
        return UserDefaults.standard.bool(forKey: enterToSendKey)
    }
}

// MARK: - Container View

/// Inline text input that sits flush at the bottom of the terminal.
///
/// Styled as a thin single-line field with the terminal's own colors so it looks
/// like the prompt's caret area was replaced by a native text field.
struct TextBoxInputContainer: View {
    @Binding var text: String
    let enterToSend: Bool
    let terminalBackgroundColor: NSColor
    let terminalForegroundColor: NSColor
    let terminalFont: NSFont
    let onSend: (String) -> Void
    let onEscape: () -> Void
    let onArrowUp: () -> Void
    let onArrowDown: () -> Void
    let onArrowLeft: () -> Void
    let onArrowRight: () -> Void
    let onTab: () -> Void
    let onBackspace: () -> Void
    let onControlKey: (NSEvent) -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            TextBoxInputView(
                text: $text,
                enterToSend: enterToSend,
                onSubmit: submit,
                onEscape: onEscape,
                onArrowUp: onArrowUp,
                onArrowDown: onArrowDown,
                onArrowLeft: onArrowLeft,
                onArrowRight: onArrowRight,
                onTab: onTab,
                onBackspace: onBackspace,
                onControlKey: onControlKey,
                terminalBackgroundColor: terminalBackgroundColor,
                terminalForegroundColor: terminalForegroundColor,
                terminalFont: terminalFont
            )
            .frame(
                minHeight: TextBoxLayout.singleLineHeight,
                maxHeight: TextBoxLayout.maxHeight
            )

            Button(action: submit) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: TextBoxLayout.sendButtonSize))
                    .foregroundColor(Color(nsColor: terminalForegroundColor))
            }
            .buttonStyle(.borderless)
            .disabled(false)
            .help(String(localized: "textbox.send.tooltip", defaultValue: "Send"))
        }
        .padding(.leading, TextBoxLayout.horizontalPadding)
        .padding(.trailing, TextBoxLayout.horizontalPadding)
        .padding(.top, TextBoxLayout.topPadding)
        .padding(.bottom, TextBoxLayout.bottomPadding)
        .background(Color(nsColor: terminalBackgroundColor))
    }

    private func submit() {
        let content = text
        onSend(content)
        text = ""
    }
}

// MARK: - NSViewRepresentable

/// NSViewRepresentable that wraps NSTextView for inline terminal input.
///
/// Styled to blend with the terminal: same background/foreground colors, monospace font,
/// with a subtle border to indicate it is a native editable field.
struct TextBoxInputView: NSViewRepresentable {
    @Binding var text: String
    let enterToSend: Bool
    let onSubmit: () -> Void
    let onEscape: () -> Void
    let onArrowUp: () -> Void
    let onArrowDown: () -> Void
    let onArrowLeft: () -> Void
    let onArrowRight: () -> Void
    let onTab: () -> Void
    let onBackspace: () -> Void
    let onControlKey: (NSEvent) -> Void
    let terminalBackgroundColor: NSColor
    let terminalForegroundColor: NSColor
    let terminalFont: NSFont

    private var adjustedFont: NSFont {
        let size = max(1, terminalFont.pointSize + TextBoxLayout.fontSizeOffset)
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    private func makeParagraphStyle() -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = TextBoxLayout.lineSpacing
        return style
    }

    private func makeTypingAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: adjustedFont,
            .foregroundColor: terminalForegroundColor,
            .paragraphStyle: makeParagraphStyle(),
        ]
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSView {
        // Border is on a container NSView, not on the NSScrollView directly.
        // Setting `wantsLayer = true` + `layer?.borderWidth` on NSScrollView
        // does not render a border (its layer management conflicts with
        // direct layer property access). A plain NSView wrapper works reliably.
        let container = NSView()
        container.wantsLayer = true
        container.layer?.borderWidth = TextBoxLayout.borderWidth
        container.layer?.borderColor = terminalForegroundColor.withAlphaComponent(TextBoxLayout.borderOpacity).cgColor
        container.layer?.cornerRadius = TextBoxLayout.cornerRadius
        container.layer?.masksToBounds = true

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let textView = InputTextView()
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.usesFindPanel = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = TextBoxLayout.textInset
        textView.delegate = context.coordinator
        textView.inputCoordinator = context.coordinator

        // Match terminal appearance
        textView.drawsBackground = true
        textView.backgroundColor = terminalBackgroundColor
        textView.insertionPointColor = terminalForegroundColor
        textView.font = adjustedFont
        textView.typingAttributes = makeTypingAttributes()
        textView.defaultParagraphStyle = makeParagraphStyle()

        if let textContainer = textView.textContainer {
            textContainer.widthTracksTextView = true
            textContainer.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        }

        scrollView.documentView = textView
        context.coordinator.textView = textView

        container.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        // Auto-focus the text view when it appears
        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }

        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        guard let scrollView = container.subviews.first as? NSScrollView,
              let textView = scrollView.documentView as? InputTextView else { return }
        context.coordinator.parent = self
        if textView.string != text {
            textView.string = text
        }
        // Keep colors in sync with terminal theme changes
        textView.backgroundColor = terminalBackgroundColor
        textView.insertionPointColor = terminalForegroundColor
        textView.typingAttributes = makeTypingAttributes()
        container.layer?.borderColor = terminalForegroundColor.withAlphaComponent(TextBoxLayout.borderOpacity).cgColor
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TextBoxInputView
        weak var textView: NSTextView?

        init(_ parent: TextBoxInputView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        /// Returns true if the action was handled (consumed).
        func handleCommand(_ selector: Selector) -> Bool {
            if selector == #selector(NSResponder.insertNewline(_:)) ||
               selector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)) {
                let shifted = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
                return handleNewline(shifted: shifted)
            }
            if selector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onEscape()
                return true
            }
            if selector == #selector(NSResponder.moveUp(_:)) {
                return handleEmpty { parent.onArrowUp() }
            }
            if selector == #selector(NSResponder.moveDown(_:)) {
                return handleEmpty { parent.onArrowDown() }
            }
            if selector == #selector(NSResponder.moveLeft(_:)) {
                return handleEmpty { parent.onArrowLeft() }
            }
            if selector == #selector(NSResponder.moveRight(_:)) {
                return handleEmpty { parent.onArrowRight() }
            }
            if selector == #selector(NSResponder.insertTab(_:)) {
                return handleEmpty { parent.onTab() }
            }
            if selector == #selector(NSResponder.deleteBackward(_:)) {
                return handleEmpty { parent.onBackspace() }
            }
            return false
        }

        /// Forward action to terminal only when TextBox is empty.
        /// When the user is typing text, arrow keys etc. should navigate
        /// within the TextBox normally. Forwarding only when empty prevents
        /// accidentally losing in-progress input.
        private func handleEmpty(_ action: () -> Void) -> Bool {
            guard let textView = textView, textView.string.isEmpty else { return false }
            action()
            return true
        }

        private func handleNewline(shifted: Bool) -> Bool {
            let shouldSend: Bool
            if parent.enterToSend {
                shouldSend = !shifted
            } else {
                shouldSend = shifted
            }

            if shouldSend {
                parent.onSubmit()
                return true
            }
            textView?.insertNewlineIgnoringFieldEditor(nil)
            return true
        }

    }
}

// MARK: - InputTextView

/// Custom NSTextView subclass that routes key events to the coordinator.
///
/// Two separate interception layers are used intentionally:
///
/// 1. **`keyDown`** — intercepts Ctrl+key *before* AppKit interprets them.
///    Ctrl+C, Ctrl+D, etc. must always reach the terminal regardless of
///    TextBox content. If we waited for `doCommandBySelector`, AppKit
///    would convert them into selectors and they wouldn't reach the
///    terminal correctly.
///
/// 2. **`doCommandBySelector`** — handles interpreted commands (arrows,
///    Tab, Backspace, Enter, Escape). These are forwarded to the terminal
///    only when the TextBox is empty (except Enter/Escape which are always
///    handled). Using `doCommandBySelector` instead of raw `keyDown`
///    forwarding avoids `^^` garbage characters that appear when
///    forwarding raw NSEvents.
final class InputTextView: NSTextView {
    weak var inputCoordinator: TextBoxInputView.Coordinator?

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.control) {
            inputCoordinator?.parent.onControlKey(event)
            return
        }
        super.keyDown(with: event)
    }

    override func doCommand(by selector: Selector) {
        if let coordinator = inputCoordinator, coordinator.handleCommand(selector) {
            return
        }
        super.doCommand(by: selector)
    }
}
