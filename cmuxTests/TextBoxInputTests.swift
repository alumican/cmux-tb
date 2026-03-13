import XCTest
import AppKit

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

// MARK: - CommandHistory Tests

final class CommandHistoryTests: XCTestCase {

    // MARK: - Basic add/navigate

    func testEmptyHistoryNavigateBackReturnsNil() {
        let history = CommandHistory()
        XCTAssertNil(history.navigateBack(currentText: ""))
    }

    func testEmptyHistoryNavigateForwardReturnsNil() {
        let history = CommandHistory()
        XCTAssertNil(history.navigateForward())
    }

    func testAddSingleEntry() {
        let history = CommandHistory()
        history.add("ls -la")
        XCTAssertEqual(history.count, 1)
    }

    func testNavigateBackReturnsPreviousEntry() {
        let history = CommandHistory()
        history.add("echo hello")
        history.add("ls -la")

        let entry = history.navigateBack(currentText: "")
        XCTAssertEqual(entry, "ls -la")
    }

    func testNavigateBackTwiceReturnsOlderEntry() {
        let history = CommandHistory()
        history.add("echo hello")
        history.add("ls -la")

        _ = history.navigateBack(currentText: "")
        let entry = history.navigateBack(currentText: "")
        XCTAssertEqual(entry, "echo hello")
    }

    func testNavigateBackBeyondOldestReturnsNil() {
        let history = CommandHistory()
        history.add("echo hello")

        _ = history.navigateBack(currentText: "")
        let entry = history.navigateBack(currentText: "")
        XCTAssertNil(entry)
    }

    func testNavigateForwardAfterBackReturnsNewerEntry() {
        let history = CommandHistory()
        history.add("echo hello")
        history.add("ls -la")

        _ = history.navigateBack(currentText: "")
        _ = history.navigateBack(currentText: "")
        let entry = history.navigateForward()
        XCTAssertEqual(entry, "ls -la")
    }

    // MARK: - Draft preservation

    func testDraftPreservedWhenNavigatingBack() {
        let history = CommandHistory()
        history.add("echo hello")

        let currentDraft = "partial command"
        _ = history.navigateBack(currentText: currentDraft)

        // Navigate forward should restore draft
        let restored = history.navigateForward()
        XCTAssertEqual(restored, currentDraft)
    }

    func testDraftOnlySetOnFirstNavigateBack() {
        let history = CommandHistory()
        history.add("cmd1")
        history.add("cmd2")

        // First navigateBack saves "my draft"
        _ = history.navigateBack(currentText: "my draft")
        // Second navigateBack should NOT overwrite draft
        _ = history.navigateBack(currentText: "cmd2")

        // Go forward past all entries to get draft
        _ = history.navigateForward() // cmd2
        let draft = history.navigateForward() // draft
        XCTAssertEqual(draft, "my draft")
    }

    // MARK: - Deduplication

    func testConsecutiveDuplicatesNotAdded() {
        let history = CommandHistory()
        history.add("ls")
        history.add("ls")
        history.add("ls")
        XCTAssertEqual(history.count, 1)
    }

    func testNonConsecutiveDuplicatesAdded() {
        let history = CommandHistory()
        history.add("ls")
        history.add("pwd")
        history.add("ls")
        XCTAssertEqual(history.count, 3)
    }

    // MARK: - Whitespace / empty

    func testEmptyStringNotAdded() {
        let history = CommandHistory()
        history.add("")
        XCTAssertEqual(history.count, 0)
    }

    func testWhitespaceOnlyStringNotAdded() {
        let history = CommandHistory()
        history.add("   \n\t  ")
        XCTAssertEqual(history.count, 0)
    }

    func testAddTrimsWhitespace() {
        let history = CommandHistory()
        history.add("  echo hello  \n")

        let entry = history.navigateBack(currentText: "")
        XCTAssertEqual(entry, "echo hello")
    }

    // MARK: - Max entries

    func testMaxEntriesRespected() {
        let history = CommandHistory(maxEntries: 3)
        history.add("cmd1")
        history.add("cmd2")
        history.add("cmd3")
        history.add("cmd4")

        XCTAssertEqual(history.count, 3)

        // Oldest (cmd1) should have been evicted
        _ = history.navigateBack(currentText: "")
        _ = history.navigateBack(currentText: "")
        let oldest = history.navigateBack(currentText: "")
        XCTAssertEqual(oldest, "cmd2")
    }

    // MARK: - Reset navigation

    func testResetNavigationMovesToEnd() {
        let history = CommandHistory()
        history.add("cmd1")
        history.add("cmd2")

        _ = history.navigateBack(currentText: "")
        history.resetNavigation()

        // After reset, navigateForward should return nil (already at end)
        XCTAssertNil(history.navigateForward())
    }

    func testAddResetsNavigationIndex() {
        let history = CommandHistory()
        history.add("cmd1")

        _ = history.navigateBack(currentText: "draft")
        // Adding new entry resets index
        history.add("cmd2")

        // Should be at end now, navigateBack returns latest
        let entry = history.navigateBack(currentText: "")
        XCTAssertEqual(entry, "cmd2")
    }

    // MARK: - Full cycle

    func testFullNavigationCycle() {
        let history = CommandHistory()
        history.add("alpha")
        history.add("beta")
        history.add("gamma")

        // Navigate all the way back
        XCTAssertEqual(history.navigateBack(currentText: "draft"), "gamma")
        XCTAssertEqual(history.navigateBack(currentText: ""), "beta")
        XCTAssertEqual(history.navigateBack(currentText: ""), "alpha")
        XCTAssertNil(history.navigateBack(currentText: ""))

        // Navigate all the way forward
        XCTAssertEqual(history.navigateForward(), "beta")
        XCTAssertEqual(history.navigateForward(), "gamma")
        XCTAssertEqual(history.navigateForward(), "draft")
        XCTAssertNil(history.navigateForward())
    }
}

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
