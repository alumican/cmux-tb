import XCTest
import AppKit

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

// MARK: - TextBoxInputSettings Tests

final class TextBoxInputSettingsTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: TextBoxInputSettings.enabledKey)
        UserDefaults.standard.removeObject(forKey: TextBoxInputSettings.enterToSendKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: TextBoxInputSettings.enabledKey)
        UserDefaults.standard.removeObject(forKey: TextBoxInputSettings.enterToSendKey)
        super.tearDown()
    }

    func testDefaultEnabledIsFalse() {
        XCTAssertFalse(TextBoxInputSettings.isEnabled())
    }

    func testDefaultEnterToSendIsTrue() {
        XCTAssertTrue(TextBoxInputSettings.isEnterToSend())
    }

    func testSetEnabledTrue() {
        UserDefaults.standard.set(true, forKey: TextBoxInputSettings.enabledKey)
        XCTAssertTrue(TextBoxInputSettings.isEnabled())
    }

    func testSetEnterToSendFalse() {
        UserDefaults.standard.set(false, forKey: TextBoxInputSettings.enterToSendKey)
        XCTAssertFalse(TextBoxInputSettings.isEnterToSend())
    }
}

// MARK: - KeyboardShortcutSettings Integration Tests

final class TextBoxShortcutTests: XCTestCase {

    override func tearDown() {
        KeyboardShortcutSettings.resetShortcut(for: .toggleTextBoxInput)
        super.tearDown()
    }

    func testToggleTextBoxInputDefaultShortcut() {
        let shortcut = KeyboardShortcutSettings.Action.toggleTextBoxInput.defaultShortcut
        XCTAssertEqual(shortcut.key, "t")
        XCTAssertTrue(shortcut.command)
        XCTAssertTrue(shortcut.shift)
        XCTAssertTrue(shortcut.option)
        XCTAssertFalse(shortcut.control)
    }

    func testToggleTextBoxInputDefaultsKey() {
        XCTAssertEqual(
            KeyboardShortcutSettings.Action.toggleTextBoxInput.defaultsKey,
            "shortcut.toggleTextBoxInput"
        )
    }

    func testToggleTextBoxInputLabel() {
        let label = KeyboardShortcutSettings.Action.toggleTextBoxInput.label
        XCTAssertEqual(label, "Toggle TextBox Input")
    }

    func testCustomShortcutPersistence() {
        let custom = StoredShortcut(key: "j", command: true, shift: false, option: false, control: false)
        KeyboardShortcutSettings.setShortcut(custom, for: .toggleTextBoxInput)

        let loaded = KeyboardShortcutSettings.shortcut(for: .toggleTextBoxInput)
        XCTAssertEqual(loaded, custom)
    }

    func testResetShortcutRestoresDefault() {
        let custom = StoredShortcut(key: "j", command: true, shift: false, option: false, control: false)
        KeyboardShortcutSettings.setShortcut(custom, for: .toggleTextBoxInput)
        KeyboardShortcutSettings.resetShortcut(for: .toggleTextBoxInput)

        let loaded = KeyboardShortcutSettings.shortcut(for: .toggleTextBoxInput)
        XCTAssertEqual(loaded, KeyboardShortcutSettings.Action.toggleTextBoxInput.defaultShortcut)
    }
}
