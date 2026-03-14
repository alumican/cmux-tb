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

// MARK: - Command History

/// Manages command history for TextBox input, enabling Up/Down arrow navigation.
final class CommandHistory {
    private var entries: [String] = []
    private var index: Int = 0
    private var draftText: String = ""
    private let maxEntries: Int

    init(maxEntries: Int = 200) {
        self.maxEntries = maxEntries
    }

    var count: Int { entries.count }
    var currentIndex: Int { index }
    var currentDraft: String { draftText }

    /// Add a command to history and reset index to the end.
    func add(_ command: String) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Avoid consecutive duplicates
        if entries.last != trimmed {
            entries.append(trimmed)
            if entries.count > maxEntries {
                entries.removeFirst(entries.count - maxEntries)
            }
        }
        index = entries.count
        draftText = ""
    }

    /// Navigate to the previous (older) entry. Returns the entry text, or nil if already at the oldest.
    func navigateBack(currentText: String) -> String? {
        guard !entries.isEmpty else { return nil }
        if index == entries.count {
            draftText = currentText
        }
        guard index > 0 else { return nil }
        index -= 1
        return entries[index]
    }

    /// Navigate to the next (newer) entry. Returns the entry text or draft, or nil if already at the newest.
    func navigateForward() -> String? {
        guard index < entries.count else { return nil }
        index += 1
        if index == entries.count {
            return draftText
        }
        return entries[index]
    }

    /// Reset navigation position to the end (latest).
    func resetNavigation() {
        index = entries.count
        draftText = ""
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
    let commandHistory: CommandHistory
    let terminalBackgroundColor: NSColor
    let terminalForegroundColor: NSColor
    let terminalFont: NSFont
    let onSend: (String) -> Void
    let onEscape: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            TextBoxInputView(
                text: $text,
                enterToSend: enterToSend,
                onSubmit: submit,
                onEscape: onEscape,
                commandHistory: commandHistory,
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
    let commandHistory: CommandHistory
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

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

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

        // Visible border
        textView.wantsLayer = true
        textView.layer?.borderWidth = TextBoxLayout.borderWidth
        textView.layer?.borderColor = terminalForegroundColor.withAlphaComponent(TextBoxLayout.borderOpacity).cgColor
        textView.layer?.cornerRadius = TextBoxLayout.cornerRadius

        if let textContainer = textView.textContainer {
            textContainer.widthTracksTextView = true
            textContainer.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        }

        scrollView.documentView = textView
        context.coordinator.textView = textView

        // Auto-focus the text view when it appears
        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? InputTextView else { return }
        context.coordinator.parent = self
        if textView.string != text {
            textView.string = text
        }
        // Keep colors in sync with terminal theme changes
        textView.backgroundColor = terminalBackgroundColor
        textView.insertionPointColor = terminalForegroundColor
        textView.typingAttributes = makeTypingAttributes()
        textView.layer?.borderColor = terminalForegroundColor.withAlphaComponent(TextBoxLayout.borderOpacity).cgColor
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
                return handleMoveUp()
            }
            if selector == #selector(NSResponder.moveDown(_:)) {
                return handleMoveDown()
            }
            return false
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

        private func handleMoveUp() -> Bool {
            guard let textView = textView else { return false }
            let selectedRange = textView.selectedRange()
            guard selectedRange.location == 0 && selectedRange.length == 0 else {
                return false
            }
            if let entry = parent.commandHistory.navigateBack(currentText: textView.string) {
                textView.string = entry
                parent.text = entry
                textView.setSelectedRange(NSRange(location: entry.count, length: 0))
                return true
            }
            return false
        }

        private func handleMoveDown() -> Bool {
            guard let textView = textView else { return false }
            let selectedRange = textView.selectedRange()
            let textLength = (textView.string as NSString).length
            guard selectedRange.location == textLength && selectedRange.length == 0 else {
                return false
            }
            if let entry = parent.commandHistory.navigateForward() {
                textView.string = entry
                parent.text = entry
                textView.setSelectedRange(NSRange(location: entry.count, length: 0))
                return true
            }
            return false
        }
    }
}

// MARK: - InputTextView

/// Custom NSTextView subclass that routes doCommandBy to the coordinator.
final class InputTextView: NSTextView {
    weak var inputCoordinator: TextBoxInputView.Coordinator?

    override func doCommand(by selector: Selector) {
        if let coordinator = inputCoordinator, coordinator.handleCommand(selector) {
            return
        }
        super.doCommand(by: selector)
    }
}
