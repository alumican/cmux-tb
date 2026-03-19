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
// - **Auto-grow**: Text box grows with content (1–5 lines), then scrolls internally
// - **Key routing**: Ctrl+key forwarding, Emacs editing, shell history,
//   prefix forwarding (/, @) — all rules are defined in `TextBoxKeyRouting`
//   as a centralized table. See the rule table comment above that enum.
// - **Theme sync**: Automatically matches terminal background/foreground colors and font
// - **Show/Hide**: Cmd+Option+T to show/hide with focus coordination
//
// ## Settings (Settings > TextBox Input)
//
// - **Enable Mode**: Toggle TextBox on/off (default: off)
// - **Send on Return**: On = Return sends / Shift+Return inserts newline,
//   Off = Enter inserts newline / Shift+Enter sends (default: on)
// - **Show/Hide TextBox Input**: Shows the toggle shortcut (Cmd+Option+T)
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
    /// Minimum number of visible lines.
    static let minLines: Int = 2
    /// Maximum number of visible lines before the text view starts scrolling internally.
    static let maxLines: Int = 6
    /// Added to the terminal font size for the TextBox font (slightly larger for readability).
    static let fontSizeOffset: CGFloat = 1
    /// Extra spacing between lines in multi-line input.
    static let lineSpacing: CGFloat = 4
    /// Inset between the text and the text view's border (width=horizontal, height=vertical).
    static let textInset = NSSize(width: 2, height: 6)
    /// Border stroke width around the text view container.
    static let borderWidth: CGFloat = 1
    /// Border color opacity when unfocused (fraction of the terminal foreground color).
    static let borderOpacity: CGFloat = 0.25
    /// Border color opacity when focused (caret is in the text view).
    static let focusedBorderOpacity: CGFloat = 0.45
    /// Corner radius of the text view container.
    static let cornerRadius: CGFloat = 6
    /// Opacity of the placeholder text (fraction of the terminal foreground color).
    static let placeholderOpacity: CGFloat = 0.35
    /// Placeholder text shown when the TextBox is empty.
    /// The send key name changes based on the Enter-to-Send setting.
    static func placeholderText(enterToSend: Bool) -> String {
        if enterToSend {
            return String(localized: "textbox.placeholder.enterToSend", defaultValue: "Commands or prompts here… Shift+Return for newline")
        } else {
            return String(localized: "textbox.placeholder.enterToNewline", defaultValue: "Commands or prompts here… Shift+Return to send")
        }
    }
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
    /// Scope of the Cmd+Opt+T toggle shortcut.
    /// `.active` = only the focused tab, `.all` = all tabs simultaneously.
    static let toggleScope: TextBoxToggleTarget = .all
}

// MARK: - Toggle Scope

/// Scope of the TextBox toggle shortcut (Cmd+Opt+T).
enum TextBoxToggleTarget {
    /// Toggle only the currently active (focused or TextBox-focused) panel.
    case active
    /// Toggle all terminal panels simultaneously.
    case all

    /// The configured default scope, read from TextBoxBehavior.
    static var `default`: TextBoxToggleTarget { TextBoxBehavior.toggleScope }
}

// MARK: - App Detection

/// Terminal apps detected by tab title for key routing decisions.
/// Used by `TextBoxKeyRouting` to determine which prefixes to forward.
enum TextBoxAppDetection: CaseIterable {
    case claudeCode
    case codex

    /// Regex pattern matched (case-insensitive) against the terminal tab title.
    /// The title may contain leading icons or symbols (e.g. "✱ Claude Code").
    private var tabTitlePattern: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codex:      return "Codex"
        }
    }

    /// Returns true if the terminal tab title indicates this app is running.
    func matches(terminalTitle: String) -> Bool {
        terminalTitle.range(
            of: tabTitlePattern,
            options: [.caseInsensitive, .regularExpression]
        ) != nil
    }
}

// MARK: - Focus State

/// The three observable states of the TextBox, used to decide what the
/// toggle shortcut (Cmd+Opt+T) should do.
///
/// Transitions on shortcut press:
///   hidden           → show TextBox + focus it
///   visibleUnfocused → focus TextBox (don't hide it)
///   visibleFocused   → hide TextBox + focus terminal
enum TextBoxFocusState {
    /// TextBox is not displayed.
    case hidden
    /// TextBox is displayed but the terminal (or another view) has focus.
    case visibleUnfocused
    /// TextBox is displayed and has keyboard focus.
    case visibleFocused

    /// Determine the current state from panel and window state.
    static func current(isTextBoxActive: Bool, window: NSWindow?) -> TextBoxFocusState {
        guard isTextBoxActive else { return .hidden }
        guard let firstResponder = window?.firstResponder else { return .visibleUnfocused }
        if firstResponder is InputTextView {
            return .visibleFocused
        }
        return .visibleUnfocused
    }

    /// Move keyboard focus to the InputTextView in the given window.
    static func focusTextBox(in window: NSWindow?) {
        guard let window else { return }
        if let textView = findInputTextView(in: window.contentView) {
            window.makeFirstResponder(textView)
        }
    }

    /// Recursively search for InputTextView in the view hierarchy.
    private static func findInputTextView(in view: NSView?) -> InputTextView? {
        guard let view else { return nil }
        if let inputTextView = view as? InputTextView {
            return inputTextView
        }
        for subview in view.subviews {
            if let found = findInputTextView(in: subview) {
                return found
            }
        }
        return nil
    }
}

// MARK: - Key Routing
//
// All TextBox key handling is governed by the rule table below.
// Rules are evaluated top-down; the first match wins. Unmatched
// keys fall through to default TextBox text input.
//
// Rules are evaluated within each input path (keyDown / insertText /
// doCommand). Groups never overlap because each NSTextView interception
// point produces a distinct input type.
//
// | # | Modifier | Key              | TextBox | App              | Action                                |
// |---|----------|------------------|---------|------------------|---------------------------------------|
// | 1 | Ctrl     | A/E/F/B/N/P/K/H  | any     | any              | Emacs editing (handled by NSTextView) |
// | 2 | Ctrl     | * (other)        | any     | any              | Forward to terminal (keep focus)      |
// | 3 | None     | /                | empty   | claudeCode,codex | Forward prefix + focus terminal       |
// | 4 | None     | @                | empty   | claudeCode       | Forward prefix + focus terminal       |
// | 5 | None     | Return           | any     | any              | Submit or newline (setting)           |
// | 6 | Shift    | Return           | any     | any              | Newline or submit (inverse of 5)      |
// | 7 | None     | Escape           | any     | any              | Focus terminal or send ESC (setting)  |
// | 8 | None     | ↑↓←→ Tab BS      | empty   | any              | Forward key to terminal (keep focus)  |
// | — | *        | *                | any     | any              | TextBox text input (fallback)         |

/// Normalized input from the three NSTextView interception points.
enum TextBoxKeyInput {
    /// From keyDown(): Ctrl + character key.
    case ctrl(String)
    /// From insertText(): committed text character.
    case text(String)
    /// From doCommand(): AppKit-interpreted command selector.
    case command(Selector, shifted: Bool)
}

/// Routing result — tells the caller what action to take.
enum TextBoxKeyAction {
    /// Rule 1: Pass to NSTextView for Emacs-style editing.
    case emacsEdit
    /// Rule 2: Forward raw Ctrl+key event to terminal (keep focus).
    case forwardControl
    /// Rule 3/4: Forward prefix character to terminal and move focus.
    case forwardPrefix(String)
    /// Rule 5/6: Send TextBox content to terminal.
    case submit
    /// Rule 5/6: Insert newline into TextBox.
    case insertNewline
    /// Rule 7: Escape action (setting-dependent).
    case escape
    /// Rule 8: Forward interpreted key to terminal (keep focus).
    case forwardKey(TextBoxKeyRouting.TerminalKey)
    /// Fallback: Default TextBox text input.
    case textInput
}

/// Centralized key routing for TextBox. All routing decisions are made here;
/// each NSTextView interception point (`keyDown`, `insertText`, `doCommand`)
/// converts its input to `TextBoxKeyInput` and calls `route()`.
///
/// All key definitions are collected in this enum so new rules can be added
/// in one place without touching the interception points.
enum TextBoxKeyRouting {

    // MARK: Key Definitions

    /// Named keys that TextBox forwards to the terminal via synthetic NSEvents.
    enum TerminalKey {
        case returnKey, arrowUp, arrowDown, arrowLeft, arrowRight, tab, backspace, escape

        var characters: String {
            switch self {
            case .returnKey: return "\r"
            case .arrowUp:   return "\u{F700}"
            case .arrowDown: return "\u{F701}"
            case .arrowLeft: return "\u{F702}"
            case .arrowRight: return "\u{F703}"
            case .tab:       return "\t"
            case .backspace: return "\u{7F}"
            case .escape:    return "\u{1B}"
            }
        }

        var keyCode: UInt16 {
            switch self {
            case .returnKey: return 36
            case .arrowUp:   return 126
            case .arrowDown: return 125
            case .arrowLeft: return 123
            case .arrowRight: return 124
            case .tab:       return 48
            case .backspace: return 51
            case .escape:    return 53
            }
        }
    }

    /// Rule 1: Emacs editing keys — Ctrl+key handled locally by NSTextView.
    private static let emacsEditingKeys: Set<String> = [
        "a",  // moveToBeginningOfLine:
        "e",  // moveToEndOfLine:
        "f",  // moveForward:
        "b",  // moveBackward:
        "n",  // moveDown:
        "p",  // moveUp:
        "k",  // deleteToEndOfLine: (via killLine:)
        "h",  // deleteBackward:
    ]

    /// Rules 5, 6: Prefixes forwarded to terminal when TextBox is empty.
    /// Per-app prefix sets are defined in `TextBoxAppDetection`.
    private static let prefixForwardKeys: [TextBoxAppDetection: [String]] = [
        .claudeCode: ["/", "@"],
        .codex:      ["/"],
    ]

    /// Rule 7: Selectors forwarded to terminal when TextBox is empty.
    private static let emptyStateSelectors: [Selector: TerminalKey] = [
        #selector(NSResponder.moveUp(_:)):         .arrowUp,
        #selector(NSResponder.moveDown(_:)):       .arrowDown,
        #selector(NSResponder.moveLeft(_:)):       .arrowLeft,
        #selector(NSResponder.moveRight(_:)):      .arrowRight,
        #selector(NSResponder.insertTab(_:)):      .tab,
        #selector(NSResponder.deleteBackward(_:)): .backspace,
    ]

    // MARK: Routing

    /// Single entry point for all key routing decisions.
    static func route(
        _ input: TextBoxKeyInput,
        isEmpty: Bool,
        terminalTitle: String,
        enterToSend: Bool
    ) -> TextBoxKeyAction {
        switch input {

        // Rules 1, 2: Ctrl+key
        case .ctrl(let char):
            if emacsEditingKeys.contains(char) { return .emacsEdit }      // Rule 1
            return .forwardControl                                        // Rule 2

        // Rules 3, 4, fallback: Inserted text
        case .text(let str):
            if isEmpty {
                for (app, prefixes) in prefixForwardKeys
                    where prefixes.contains(str) && app.matches(terminalTitle: terminalTitle) {
                    return .forwardPrefix(str)                            // Rule 3, 4
                }
            }
            return .textInput                                             // Fallback

        // Rules 5, 6, 7, 8: Command selectors
        case .command(let selector, let shifted):
            // Rule 5, 6: Return
            if selector == #selector(NSResponder.insertNewline(_:)) ||
               selector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)) {
                let shouldSend = enterToSend ? !shifted : shifted
                return shouldSend ? .submit : .insertNewline
            }
            // Rule 7: Escape
            if selector == #selector(NSResponder.cancelOperation(_:)) {
                return .escape
            }
            // Rule 8: Empty-state navigation
            if isEmpty, let key = emptyStateSelectors[selector] {
                return .forwardKey(key)
            }
            return .textInput                                             // Fallback
        }
    }
}

// MARK: - Key Events

/// Events dispatched from the TextBox to its parent for terminal forwarding.
enum TextBoxKeyEvent {
    /// User pressed Return/Shift+Return to submit text.
    case submit
    /// User pressed Escape.
    case escape
    /// A named key to forward to the terminal (arrows, Tab, Backspace).
    case key(TextBoxKeyRouting.TerminalKey)
    /// A Ctrl+key combination to forward as a raw NSEvent.
    case control(NSEvent)
}

// MARK: - Settings

/// Settings for TextBox Input Mode
enum TextBoxInputSettings {
    static let enabledKey = "textBoxEnabled"
    static let enterToSendKey = "textBoxEnterToSend"
    static let escapeBehaviorKey = "textBoxEscapeBehavior"
    static let shortcutBehaviorKey = "textBoxShortcutBehavior"

    static let defaultEnabled = true
    static let defaultEnterToSend = true
    static let defaultEscapeBehavior = TextBoxEscapeBehavior.sendEscape
    static let defaultShortcutBehavior = TextBoxShortcutBehavior.toggleDisplay

    /// Opacity applied to settings rows when TextBox is disabled.
    static let disabledSettingsOpacity: Double = 0.5

    /// Reset all TextBox settings to defaults via UserDefaults.
    static func resetAll() {
        UserDefaults.standard.removeObject(forKey: enabledKey)
        UserDefaults.standard.removeObject(forKey: enterToSendKey)
        UserDefaults.standard.removeObject(forKey: escapeBehaviorKey)
        UserDefaults.standard.removeObject(forKey: shortcutBehaviorKey)
    }

    private static func bool(forKey key: String, default defaultValue: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) == nil
            ? defaultValue
            : UserDefaults.standard.bool(forKey: key)
    }

    static func isEnabled() -> Bool {
        bool(forKey: enabledKey, default: defaultEnabled)
    }

    static func isEnterToSend() -> Bool {
        bool(forKey: enterToSendKey, default: defaultEnterToSend)
    }

    static func escapeBehavior() -> TextBoxEscapeBehavior {
        guard let raw = UserDefaults.standard.string(forKey: escapeBehaviorKey),
              let value = TextBoxEscapeBehavior(rawValue: raw) else {
            return defaultEscapeBehavior
        }
        return value
    }

    static func shortcutBehavior() -> TextBoxShortcutBehavior {
        guard let raw = UserDefaults.standard.string(forKey: shortcutBehaviorKey),
              let value = TextBoxShortcutBehavior(rawValue: raw) else {
            return defaultShortcutBehavior
        }
        return value
    }
}

/// What the keyboard shortcut (Cmd+Opt+T) does.
enum TextBoxShortcutBehavior: String, CaseIterable, Identifiable {
    /// Toggle TextBox visibility (show/hide).
    case toggleDisplay = "toggleDisplay"
    /// Keep TextBox always visible, toggle focus between TextBox and terminal.
    case toggleFocus = "toggleFocus"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .toggleDisplay:
            return String(localized: "textbox.shortcutBehavior.toggleDisplay", defaultValue: "Toggle Display")
        case .toggleFocus:
            return String(localized: "textbox.shortcutBehavior.toggleFocus", defaultValue: "Toggle Focus")
        }
    }
}

/// What happens when the user presses Escape in the TextBox.
enum TextBoxEscapeBehavior: String, CaseIterable, Identifiable {
    /// Send the ESC key to the terminal and keep focus in the TextBox.
    case sendEscape = "sendEscape"
    /// Move focus back to the terminal without sending ESC.
    case focusTerminal = "focusTerminal"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sendEscape:
            return String(localized: "textbox.escapeBehavior.sendEscape", defaultValue: "Send ESC Key")
        case .focusTerminal:
            return String(localized: "textbox.escapeBehavior.focusTerminal", defaultValue: "Focus Terminal")
        }
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
            surface.sendKey(.returnKey)
        } else {
            let delay = TimeInterval(effectiveDelayMs) / 1000.0
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak surface] in
                surface?.sendKey(.returnKey)
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
    let terminalTitle: String
    /// Called when the InputTextView is created, so the panel can store a direct
    /// reference for focus management across multiple tabs.
    let onInputTextViewCreated: ((InputTextView) -> Void)?
    @State private var textViewHeight: CGFloat = 0

    /// Computes the height for a given number of lines using the current font.
    private func heightForLines(_ count: Int) -> CGFloat {
        let fontSize = max(1, terminalFont.pointSize + TextBoxInputViewLayout.fontSizeOffset)
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let lineHeight = font.ascender - font.descender + font.leading
            + TextBoxInputViewLayout.lineSpacing
        return lineHeight * CGFloat(count) + TextBoxInputViewLayout.textInset.height * 2
    }

    var body: some View {
        let minH = heightForLines(TextBoxInputViewLayout.minLines)
        let maxH = heightForLines(TextBoxInputViewLayout.maxLines)
        let clampedHeight = max(minH, min(maxH, textViewHeight))

        HStack(alignment: .bottom, spacing: TextBoxLayout.contentSpacing) {
            TextBoxInputView(
                text: $text,
                enterToSend: enterToSend,
                textViewHeight: $textViewHeight,
                onKeyEvent: { event in
                    switch event {
                    case .submit:
                        submit()
                    case .escape:
                        switch TextBoxInputSettings.escapeBehavior() {
                        case .focusTerminal:
                            surface.focusTerminalView()
                        case .sendEscape:
                            surface.sendKey(.escape)
                        }
                    case .key(let key):
                        surface.sendKey(key)
                    case .control(let nsEvent):
                        surface.forwardKeyEvent(nsEvent)
                    }
                },
                onPrefixForward: { prefix in
                    surface.sendText(prefix)
                    surface.focusTerminalView()
                },
                onInputTextViewCreated: onInputTextViewCreated,
                terminalBackgroundColor: terminalBackgroundColor,
                terminalForegroundColor: terminalForegroundColor,
                terminalFont: terminalFont,
                terminalTitle: terminalTitle
            )
            .frame(height: clampedHeight)

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
        // Reset height to minimum so the TextBox shrinks after sending
        // multi-line content. The binding update (text = "") triggers
        // updateNSView which calls recalcHeight, but the layout pass
        // may not run soon enough for the frame to shrink visually.
        textViewHeight = 0
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
    @Binding var textViewHeight: CGFloat
    let onKeyEvent: (TextBoxKeyEvent) -> Void
    let onPrefixForward: (String) -> Void
    let onInputTextViewCreated: ((InputTextView) -> Void)?
    let terminalBackgroundColor: NSColor
    let terminalForegroundColor: NSColor
    let terminalFont: NSFont
    let terminalTitle: String

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
        // Ensure the text view resizes horizontally with the scroll view's
        // content area. Without this, the text container width may stay at 0
        // on macOS Sonoma/Sequoia, making typed text invisible. (#6)
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainerInset = TextBoxInputViewLayout.textInset
        textView.delegate = context.coordinator
        textView.inputCoordinator = context.coordinator
        textView.enterToSend = enterToSend

        // Match terminal appearance — background is drawn by the outer
        // SwiftUI .background() to avoid double-compositing when the
        // terminal uses background-opacity < 1.
        textView.drawsBackground = false
        textView.insertionPointColor = terminalForegroundColor
        textView.textColor = terminalForegroundColor
        // Match terminal selection colors: foreground on background inverted.
        textView.selectedTextAttributes = [
            .backgroundColor: terminalForegroundColor,
            .foregroundColor: terminalBackgroundColor.withAlphaComponent(1.0),
        ]
        textView.font = adjustedFont
        textView.typingAttributes = makeTypingAttributes()
        textView.defaultParagraphStyle = makeParagraphStyle()

        if let textContainer = textView.textContainer {
            textContainer.widthTracksTextView = true
            textContainer.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        }

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.container = container

        container.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        // Register this InputTextView with the panel for direct focus management
        onInputTextViewCreated?(textView)

        // Auto-focus the text view and calculate initial height.
        // Only auto-focus if nothing else currently has focus (i.e. the
        // window has no first responder yet). When toggling all tabs at once,
        // the active tab's terminal already has focus and must not be stolen.
        DispatchQueue.main.async {
            if textView.window?.firstResponder == textView.window {
                textView.window?.makeFirstResponder(textView)
            }
            context.coordinator.recalcHeight(textView)
        }

        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        guard let scrollView = container.subviews.first as? NSScrollView,
              let textView = scrollView.documentView as? InputTextView else { return }
        context.coordinator.parent = self
        // Skip text sync during IME composition: textView.string includes marked
        // (uncommitted) text while the binding only has committed text. Overwriting
        // here would disrupt the active input method session.
        if !textView.hasMarkedText(), textView.string != text {
            textView.string = text
            context.coordinator.recalcHeight(textView)
        }
        // Keep enterToSend, colors, and terminal title in sync
        textView.enterToSend = enterToSend
        textView.terminalTitle = terminalTitle
        textView.insertionPointColor = terminalForegroundColor
        textView.textColor = terminalForegroundColor
        textView.selectedTextAttributes = [
            .backgroundColor: terminalForegroundColor,
            .foregroundColor: terminalBackgroundColor.withAlphaComponent(1.0),
        ]
        textView.typingAttributes = makeTypingAttributes()
        let isFocused = textView.window?.firstResponder === textView
        let opacity = isFocused
            ? TextBoxInputViewLayout.focusedBorderOpacity
            : TextBoxInputViewLayout.borderOpacity
        container.layer?.borderColor = terminalForegroundColor.withAlphaComponent(opacity).cgColor
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TextBoxInputView
        weak var textView: NSTextView?
        weak var container: NSView?

        init(_ parent: TextBoxInputView) {
            self.parent = parent
        }

        func updateBorderOpacity(focused: Bool) {
            let opacity = focused
                ? TextBoxInputViewLayout.focusedBorderOpacity
                : TextBoxInputViewLayout.borderOpacity
            container?.layer?.borderColor = parent.terminalForegroundColor
                .withAlphaComponent(opacity).cgColor
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            recalcHeight(textView)
        }

        func recalcHeight(_ textView: NSTextView) {
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }
            layoutManager.ensureLayout(for: textContainer)
            let contentHeight = layoutManager.usedRect(for: textContainer).height
                + textView.textContainerInset.height * 2
            parent.textViewHeight = contentHeight
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
    var enterToSend: Bool = false
    /// Current terminal process title, used for app detection in key routing.
    var terminalTitle: String = ""

    // Shell-escape characters matching terminal drag-and-drop behavior.
    private static let shellEscapeCharacters = "\\ ()[]{}<>\"'`!#$&;|*?\t"

    private static func escapeForShell(_ value: String) -> String {
        var result = value
        for char in shellEscapeCharacters {
            result = result.replacingOccurrences(of: String(char), with: "\\\(char)")
        }
        return result
    }

    /// Insert shell-escaped file paths, focus the TextBox, and select the
    /// inserted text. Called from FileDropOverlayView when a Finder file drag
    /// is dropped over the TextBox area.
    ///
    /// Uses asyncAfter(0.05s) because the drop is routed through
    /// FileDropOverlayView's performDragOperation, and synchronous text
    /// insertion during a drag session stalls until the next mouse event.
    func insertDroppedFilePaths(_ urls: [URL]) {
        let escaped = urls
            .map { Self.escapeForShell($0.path) }
            .joined(separator: " ")

        let capturedWindow = window
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            let range = capturedWindow?.firstResponder === self
                ? self.selectedRange()
                : NSRange(location: self.string.count, length: 0)
            let insertionPoint = range.location
            capturedWindow?.makeFirstResponder(self)
            self.insertText(escaped, replacementRange: range)
            self.setSelectedRange(NSRange(location: insertionPoint, length: (escaped as NSString).length))
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty {
            let placeholder = TextBoxInputViewLayout.placeholderText(enterToSend: enterToSend)
            let color = (insertionPointColor ?? .white)
                .withAlphaComponent(TextBoxInputViewLayout.placeholderOpacity)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font ?? NSFont.systemFont(ofSize: 13),
                .foregroundColor: color,
            ]
            let inset = textContainerInset
            let origin = NSPoint(
                x: inset.width + (textContainer?.lineFragmentPadding ?? 0),
                y: inset.height
            )
            NSString(string: placeholder).draw(at: origin, withAttributes: attrs)
        }
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result { inputCoordinator?.updateBorderOpacity(focused: true) }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result { inputCoordinator?.updateBorderOpacity(focused: false) }
        return result
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        if let str = string as? String {
            let action = TextBoxKeyRouting.route(
                .text(str), isEmpty: self.string.isEmpty,
                terminalTitle: terminalTitle, enterToSend: enterToSend)
            switch action {
            case .forwardPrefix(let prefix):
                inputCoordinator?.parent.onPrefixForward(prefix)
                return
            case .textInput:
                break  // fall through to super
            default:
                break
            }
        }
        super.insertText(string, replacementRange: replacementRange)
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.control),
           let chars = event.charactersIgnoringModifiers {
            let action = TextBoxKeyRouting.route(
                .ctrl(chars), isEmpty: string.isEmpty,
                terminalTitle: terminalTitle, enterToSend: enterToSend)
            switch action {
            case .emacsEdit:
                super.keyDown(with: event)
            case .forwardControl:
                inputCoordinator?.parent.onKeyEvent(.control(event))
            default:
                break
            }
            return
        }
        super.keyDown(with: event)
    }

    override func doCommand(by selector: Selector) {
        let shifted = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
        let action = TextBoxKeyRouting.route(
            .command(selector, shifted: shifted), isEmpty: string.isEmpty,
            terminalTitle: terminalTitle, enterToSend: enterToSend)
        switch action {
        case .submit:
            inputCoordinator?.parent.onKeyEvent(.submit)
        case .insertNewline:
            insertNewlineIgnoringFieldEditor(nil)
        case .escape:
            inputCoordinator?.parent.onKeyEvent(.escape)
        case .forwardKey(let key):
            inputCoordinator?.parent.onKeyEvent(.key(key))
        case .textInput:
            super.doCommand(by: selector)
        default:
            super.doCommand(by: selector)
        }
    }
}

// MARK: - Settings View Modifier

extension View {
    /// Dims and disables a settings row when TextBox is not enabled.
    func textBoxSettingsDisabled(_ isDisabled: Bool) -> some View {
        self
            .disabled(isDisabled)
            .opacity(isDisabled ? TextBoxInputSettings.disabledSettingsOpacity : 1.0)
    }
}
