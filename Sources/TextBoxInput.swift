// TextBoxInput.swift
//
// # TextBox Input Mode
//
// Replaces terminal input with a native NSTextView-based text box,
// providing a standard text editing experience that terminal emulators
// typically struggle with.
//
// ## Rationale
//
// ghostty (libghostty)'s key input path has limitations with IME,
// macOS standard keybindings, and system clipboard operations. TextBox
// handles these natively via AppKit and sends only committed text to the
// terminal. Shell history, tab completion, and Ctrl+key commands are
// transparently forwarded while keeping focus in the TextBox, so users
// get a seamless experience without being aware of two input modes.
//
// ## Features
//
// - **Native text editing**: Full macOS standard operations including
//   Cmd+A/C/V/X/Z, Option+Arrow word navigation, mouse selection, drag & drop
// - **IME support**: Input methods (e.g. Japanese) work correctly
// - **Multi-line input**: Insert newlines for multi-line text submission.
//   Enter=send / Shift+Enter=newline by default (reversible in settings)
// - **Scrolling**: Text box scrolls internally when content grows; frame stays fixed
// - **Shell history integration**: When TextBox is empty, arrow keys / Tab /
//   Backspace are forwarded to the terminal for shell completion and history
// - **Ctrl+key forwarding**: Ctrl+C/D/Z etc. are always forwarded to the
//   terminal regardless of TextBox content
// - **Theme sync**: Automatically matches terminal background/foreground colors and font
// - **Toggle**: Cmd+Shift+Option+T to toggle on/off with focus coordination
//
// ## Settings (Settings > TextBox Input)
//
// - **Enable Mode**: Toggle TextBox on/off (default: off)
// - **Send to Enter**: On = Enter sends / Shift+Enter inserts newline,
//   Off = Enter inserts newline / Shift+Enter sends (default: on)
// - **Toggle Input Mode**: Shows the toggle shortcut (Cmd+Shift+Option+T)
//
// ## Upstream impact
//
// Code added to upstream (manaflow-ai/cmux) files is marked with `[TextBox]`.
// Run `grep -r '\[TextBox\]' Sources/` to list all locations.

import AppKit
import SwiftUI

// MARK: - Constants

/// Layout constants for the TextBox bar (outer container with padding, button, spacing).
private enum TextBoxLayout {
    /// Font size of the send button icon.
    static let sendButtonSize: CGFloat = 18
    /// Spacing between the text view and the send button.
    static let contentSpacing: CGFloat = 4
    /// Left padding of the entire TextBox bar.
    static let leftPadding: CGFloat = 8
    /// Right padding of the entire TextBox bar.
    static let rightPadding: CGFloat = 8
    /// Top padding of the entire TextBox bar.
    static let topPadding: CGFloat = 8
    /// Bottom padding of the entire TextBox bar.
    static let bottomPadding: CGFloat = 8
}

/// Layout constants for the internal NSTextView (font, sizing, border, insets).
private enum TextBoxInputViewLayout {
    /// Minimum height of the text view (fits a single line of text).
    static let minHeight: CGFloat = 20
    /// Maximum height before the text view starts scrolling internally.
    static let maxHeight: CGFloat = 100
    /// Added to the terminal font size for the TextBox font (slightly larger for readability).
    static let fontSizeOffset: CGFloat = 1
    /// Extra spacing between lines in multi-line input.
    static let lineSpacing: CGFloat = 4
    /// Inset between the text and the text view's border (width=horizontal, height=vertical).
    static let textInset = NSSize(width: 2, height: 6)
    /// Border stroke width around the text view container.
    static let borderWidth: CGFloat = 1
    /// Border color opacity (fraction of the terminal foreground color).
    static let borderOpacity: CGFloat = 0.3
    /// Corner radius of the text view container.
    static let cornerRadius: CGFloat = 6
}

/// Behavioral constants for TextBox (timing, thresholds, etc.).
private enum TextBoxBehavior {
    /// Delay (ms) between sending pasted text and the Return key.
    /// Apps using bracket paste mode (zsh, Claude CLI) need time to process
    /// the paste before receiving Return. 50ms/100ms are insufficient;
    /// 200ms is the minimum reliable value. See `TextBoxSubmit` for details.
    /// Set to 0 to send Return immediately after the paste.
    static let returnKeyDelayMs: Int = 200
    /// Delay (ms) before sending Return when the TextBox is empty (no paste).
    /// Set to 0 to send Return immediately (default).
    static let emptyReturnKeyDelayMs: Int = 0
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

// MARK: - Text Submission

/// Send text through TextBox: writes to PTY via bracket paste, then
/// sends Return as a separate synthetic key event after a delay.
///
/// **Why not `sendText(text + "\r")` or `sendText(text + "\n")`?**
/// `sendText` wraps content in bracket paste (`\x1b[200~…\x1b[201~`).
/// Applications that enable bracket paste mode (zsh, Claude CLI, etc.)
/// treat `\r`/`\n` inside the paste as literal characters, not as
/// command execution. Return must be sent as a separate synthetic key
/// event *outside* the paste sequence.
/// Note: `sendText(text + "\n")` does work for apps that don't use
/// bracket paste (e.g., node REPL), but fails for shell and Claude CLI.
///
/// **Why 200ms delay?**
/// Claude CLI shows "pasting text…" while processing bracket paste
/// (~100ms). If Return arrives before processing finishes, it is
/// silently ignored. 50ms and 100ms were tested and are insufficient.
/// 200ms is the minimum reliable value.
enum TextBoxSubmit {
    static func send(_ text: String, via surface: TerminalSurface) {
        let trimmed = text.trimmingCharacters(in: .newlines)
        let delayMs = TextBoxBehavior.returnKeyDelayMs
        if !trimmed.isEmpty {
            surface.sendText(trimmed)
        }
        let effectiveDelayMs = trimmed.isEmpty
            ? TextBoxBehavior.emptyReturnKeyDelayMs
            : delayMs
        if effectiveDelayMs <= 0 {
            surface.sendReturnKey()
        } else {
            let delay = TimeInterval(effectiveDelayMs) / 1000.0
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak surface] in
                surface?.sendReturnKey()
            }
        }
    }
}

// MARK: - Container View

/// Inline text input that sits flush at the bottom of the terminal.
///
/// Styled as a thin single-line field with the terminal's own colors so it looks
/// like the prompt's caret area was replaced by a native text field.
///
/// Accepts a `TerminalSurface` directly so that all key forwarding and
/// text submission logic stays inside TextBoxInput.swift, minimizing
/// TextBox-specific code in upstream files.
struct TextBoxInputContainer: View {
    @Binding var text: String
    let enterToSend: Bool
    let surface: TerminalSurface
    let terminalBackgroundColor: NSColor
    let terminalForegroundColor: NSColor
    let terminalFont: NSFont

    var body: some View {
        HStack(alignment: .bottom, spacing: TextBoxLayout.contentSpacing) {
            TextBoxInputView(
                text: $text,
                enterToSend: enterToSend,
                onSubmit: submit,
                onEscape: { surface.focusTerminalView() },
                onArrowUp: { surface.sendArrowUpKey() },
                onArrowDown: { surface.sendArrowDownKey() },
                onArrowLeft: { surface.sendArrowLeftKey() },
                onArrowRight: { surface.sendArrowRightKey() },
                onTab: { surface.sendTabKey() },
                onBackspace: { surface.sendBackspaceKey() },
                onControlKey: { event in surface.forwardKeyEvent(event) },
                terminalBackgroundColor: terminalBackgroundColor,
                terminalForegroundColor: terminalForegroundColor,
                terminalFont: terminalFont
            )
            .frame(
                minHeight: TextBoxInputViewLayout.minHeight,
                maxHeight: TextBoxInputViewLayout.maxHeight
            )

            Button(action: submit) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: TextBoxLayout.sendButtonSize))
            }
            .buttonStyle(TextBoxSendButtonStyle(foregroundColor: Color(nsColor: terminalForegroundColor)))
            .help(String(localized: "textbox.send.tooltip", defaultValue: "Send"))
        }
        .padding(.leading, TextBoxLayout.leftPadding)
        .padding(.trailing, TextBoxLayout.rightPadding)
        .padding(.top, TextBoxLayout.topPadding)
        .padding(.bottom, TextBoxLayout.bottomPadding)
        .background(Color(nsColor: terminalBackgroundColor))
    }

    private func submit() {
        let content = text
        TextBoxSubmit.send(content, via: surface)
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
        let size = max(1, terminalFont.pointSize + TextBoxInputViewLayout.fontSizeOffset)
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    private func makeParagraphStyle() -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = TextBoxInputViewLayout.lineSpacing
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
        container.layer?.borderWidth = TextBoxInputViewLayout.borderWidth
        container.layer?.borderColor = terminalForegroundColor.withAlphaComponent(TextBoxInputViewLayout.borderOpacity).cgColor
        container.layer?.cornerRadius = TextBoxInputViewLayout.cornerRadius
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
        textView.textContainerInset = TextBoxInputViewLayout.textInset
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
        container.layer?.borderColor = terminalForegroundColor.withAlphaComponent(TextBoxInputViewLayout.borderOpacity).cgColor
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

// MARK: - Send Button Style

/// Button style with hover/press highlight for the TextBox send button.
private struct TextBoxSendButtonStyle: ButtonStyle {
    let foregroundColor: Color

    func makeBody(configuration: Configuration) -> some View {
        TextBoxSendButtonBody(configuration: configuration, foregroundColor: foregroundColor)
    }
}

private struct TextBoxSendButtonBody: View {
    let configuration: TextBoxSendButtonStyle.Configuration
    let foregroundColor: Color
    @State private var isHovered = false

    private var backgroundOpacity: Double {
        if configuration.isPressed { return 0.16 }
        if isHovered { return 0.08 }
        return 0.0
    }

    var body: some View {
        configuration.label
            .foregroundColor(foregroundColor)
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(foregroundColor.opacity(backgroundOpacity))
            )
            .onHover { hovering in
                isHovered = hovering
            }
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
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
