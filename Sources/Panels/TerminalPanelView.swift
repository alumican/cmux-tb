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

    @AppStorage(TextBoxInputSettings.enabledKey) private var textBoxEnabled = TextBoxInputSettings.defaultEnabled
    @AppStorage(TextBoxInputSettings.enterToSendKey) private var enterToSend = TextBoxInputSettings.defaultEnterToSend

    private var showTextBox: Bool {
        textBoxEnabled && panel.isTextBoxActive
    }

    var body: some View {
        let config = GhosttyConfig.load()
        let runtimeBg = GhosttyApp.shared.defaultBackgroundColor
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

            if showTextBox {
                TextBoxInputContainer(
                    text: $panel.textBoxContent,
                    enterToSend: enterToSend,
                    commandHistory: panel.commandHistory,
                    terminalBackgroundColor: runtimeBg,
                    terminalForegroundColor: runtimeFg,
                    terminalFont: font,
                    onSend: { text in
                        panel.sendTextFromTextBox(text)
                    },
                    onEscape: {
                        panel.surface.focusTerminalView()
                    }
                )
            }
        }
        .onChange(of: textBoxEnabled) { enabled in
            if enabled && !panel.isTextBoxActive {
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
