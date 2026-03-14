import SwiftUI
import Foundation
import AppKit

/// View for rendering a terminal panel
struct TerminalPanelView: View {
    @ObservedObject var panel: TerminalPanel
    let isFocused: Bool
    let isVisibleInUI: Bool
    let portalPriority: Int
    let isSplit: Bool
    let appearance: PanelAppearance
    let hasUnreadNotification: Bool
    let onFocus: () -> Void
    let onTriggerFlash: () -> Void

    // [TextBox]
    @AppStorage(TextBoxInputSettings.enabledKey) private var textBoxEnabled = TextBoxInputSettings.defaultEnabled
    @AppStorage(TextBoxInputSettings.enterToSendKey) private var enterToSend = TextBoxInputSettings.defaultEnterToSend

    /// Whether the TextBox is visible. Requires both the global Enabled setting
    /// AND the per-panel `isTextBoxActive` flag. When Enabled is toggled on,
    /// `onChange` below forces `isTextBoxActive = true` so that TextBox always
    /// appears — even if the user had previously hidden it via the keyboard
    /// shortcut. This is intentional: Enabled on = TextBox visible.
    private var showTextBox: Bool {
        textBoxEnabled && panel.isTextBoxActive
    }

    var body: some View {
        let config = GhosttyConfig.load()
        // [TextBox] Apply background-opacity so TextBox matches the terminal
        let runtimeBg = GhosttyApp.shared.defaultBackgroundColor
            .withAlphaComponent(GhosttyApp.shared.defaultBackgroundOpacity)
        let runtimeFg = config.foregroundColor
        let font = NSFont.monospacedSystemFont(ofSize: config.fontSize, weight: .regular)

        VStack(spacing: 0) {
            GhosttyTerminalView(
                terminalSurface: panel.surface,
                isActive: isFocused,
                isVisibleInUI: isVisibleInUI,
                portalZPriority: portalPriority,
                showsInactiveOverlay: isSplit && !isFocused,
                showsUnreadNotificationRing: hasUnreadNotification,
                inactiveOverlayColor: appearance.unfocusedOverlayNSColor,
                inactiveOverlayOpacity: appearance.unfocusedOverlayOpacity,
                searchState: panel.searchState,
                reattachToken: panel.viewReattachToken,
                onFocus: { _ in onFocus() },
                onTriggerFlash: onTriggerFlash
            )
            .id(panel.id)
            .background(Color.clear)

            // [TextBox]
            if showTextBox {
                TextBoxInputContainer(
                    text: $panel.textBoxContent,
                    enterToSend: enterToSend,
                    surface: panel.surface,
                    terminalBackgroundColor: runtimeBg,
                    terminalForegroundColor: runtimeFg,
                    terminalFont: font
                )
            }
        }
        // [TextBox]
        .onChange(of: textBoxEnabled) { enabled in
            if enabled && !panel.isTextBoxActive {
                // Enabled on = always show TextBox, even if previously hidden via shortcut.
                panel.isTextBoxActive = true
            }
        }
    }
}

/// Shared appearance settings for panels
struct PanelAppearance {
    let dividerColor: Color
    let unfocusedOverlayNSColor: NSColor
    let unfocusedOverlayOpacity: Double

    static func fromConfig(_ config: GhosttyConfig) -> PanelAppearance {
        PanelAppearance(
            dividerColor: Color(nsColor: config.resolvedSplitDividerColor),
            unfocusedOverlayNSColor: config.unfocusedSplitOverlayFill,
            unfocusedOverlayOpacity: config.unfocusedSplitOverlayOpacity
        )
    }
}
