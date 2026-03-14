# Upstream sync guide

This fork tracks [manaflow-ai/cmux](https://github.com/manaflow-ai/cmux). Follow these rules when merging upstream changes.

## Remote setup

```bash
git remote add upstream https://github.com/manaflow-ai/cmux.git
git fetch upstream
```

## Sync procedure

```bash
git fetch upstream
git merge upstream/main
```

## Conflict resolution rules

### README.md — always keep ours

The fork has its own `README.md` and `README.ja.md`. The upstream version is archived in `upstream-readme/`.

```bash
git checkout --ours README.md
git add README.md
```

After resolving, manually update `upstream-readme/README.md` to match the latest upstream version if it changed:

```bash
git show upstream/main:README.md > upstream-readme/README.md
git add upstream-readme/README.md
```

Repeat for any upstream `README.*.md` language files that changed.

### Localizable.xcstrings — merge carefully

Fork adds Japanese translations for `textbox.*` and `settings.textBoxInput.*` keys. Upstream may add/modify other keys. Accept both sides and verify JSON is valid.

### Source files with [TextBox] markers

Fork changes in upstream files are marked with `// [TextBox]` comments. When conflicts occur in these files:

- **Keep fork additions** (lines near `[TextBox]` markers)
- **Accept upstream changes** for everything else
- Files with TextBox modifications:
  - `Sources/GhosttyTerminalView.swift` — `sendEscapeKey()`, `sendSyntheticKey` helpers, focus guard
  - `Sources/Panels/TerminalPanelView.swift` — TextBox container, background opacity
  - `Sources/Panels/TerminalPanel.swift` — `toggleTextBoxMode()`
  - `Sources/cmuxApp.swift` — TextBox settings UI, `@AppStorage`, menu item, reset
  - `Sources/AppDelegate.swift` — keyboard shortcut handler
  - `Sources/KeyboardShortcutSettings.swift` — `toggleTextBoxInput` action

### Fork-only files — no conflicts expected

These files exist only in the fork and should never conflict:

- `Sources/TextBoxInput.swift`
- `README.md` (fork version)
- `README.ja.md`
- `upstream-readme/`
- `upstream-sync.md`

## After merge

1. Build and verify: `xcodebuild -project GhosttyTabs.xcodeproj -scheme cmux -configuration Debug -destination 'platform=macOS' build`
2. Check TextBox still works (toggle, input, ESC behavior, settings)
3. If upstream added new localizable strings, consider adding Japanese translations
