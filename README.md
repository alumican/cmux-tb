<h1 align="center">cmux + TextBox</h1>
<p align="center">A TextBox input mode for the terminal app <a href="https://github.com/manaflow-ai/cmux">cmux</a></p>

<p align="center">
  <a href="https://github.com/alumican/cmux-tb/releases/latest/download/cmux-tb-macos.dmg">
    <img src="./docs/assets/macos-badge.png" alt="Download cmux + TextBox for macOS" width="180" />
  </a>
</p>

<p align="center">Version 0.63.2-tb13 (Updated 2026/4/10)</p>

> [!Warning]
> On macOS 14 (Sonoma) / macOS 15 (Sequoia), versions prior to 0.62.2-tb7 have a bug where text typed in the TextBox is not displayed. Please select "Check for updates" from the "?" button in the bottom-left corner to update to the latest version.

<br>

<p align="center">
  English&nbsp;&nbsp;|&nbsp;&nbsp;<a href="README.ja.md"><strong>日本語はこちら</strong></a>
</p>

<br/>
<br/>

<p align="center">
  <img src="./docs/assets/textbox-top-image.png" alt="cmux + TextBox" />
</p>

## 🤔 Why TextBox?

If you're not used to terminals, typing in one can sometimes feel awkward. Line breaks, selection, cut & paste — things you do without thinking — just don't work the way you expect. With this TextBox-enabled terminal, just type what you want. The standard terminal input is still there too, of course.

Two input modes sounds complicated? Don't worry — careful interaction design blends the boundary between them, so it all feels natural.💪

<p align="center">
  <img src="./docs/assets/textbox-top.gif" alt="cmux + TextBox demo" />
</p>

## 🚀 Features

<table>
<tr>
<td width="50%" valign="middle">
<h3>Seamless and modeless</h3>
<strong>When the TextBox is empty</strong>, arrow keys, Tab, and Backspace pass through to the terminal.
<br/>
<br/>
Ctrl+key combinations (Ctrl+C, Ctrl+D, Ctrl+Z, etc.) and Escape are <strong>always forwarded regardless of content</strong>.
</td>
<td width="50%">
<img src="./docs/assets/textbox-seamless.gif" alt="Seamless and modeless" width="100%" />
</td>
</tr>
<tr>
<td width="50%" valign="middle">
<h3>Ready when you need it</h3>
Toggle the TextBox with a shortcut — focus moves smoothly between the input bar and terminal, so you can start typing right away.
<br/>
<br/>
You can choose "Toggle Display" or "Toggle Focus" in Settings.
</td>
<td width="50%">
<img src="./docs/assets/textbox-toggle.gif" alt="TextBox toggle" width="100%" />
</td>
</tr>
<tr>
<td width="50%" valign="middle">
<h3>Familiar editing</h3>
The TextBox uses your OS-native text input. Arrow keys, selection, copy & paste — the same operations you're used to, just working.
</td>
<td width="50%">
<img src="./docs/assets/textbox-edit.gif" alt="Familiar editing" width="100%" />
</td>
</tr>
<tr>
<td width="50%" valign="middle">
<h3>Great with Claude Code</h3>
Launch an agent, edit prompts, reply to questions, call "/" or "@" commands, interrupt a task — all without leaving the TextBox. Works with other terminal agents too, of course.
</td>
<td width="50%">
<img src="./docs/assets/textbox-agent.gif" alt="Great with Claude Code" width="100%" />
</td>
</tr>
<tr>
<td width="50%" valign="middle">
<h3>Settings</h3>
Send on Return or Shift+Return? What should ESC do? Customize it to fit your workflow.
</td>
<td width="50%">
<img src="./docs/assets/textbox-settings.gif" alt="TextBox settings" width="100%" />
</td>
</tr>
</table>

### 🚧 Not yet supported

- **Drag & drop paths** — Drop files or folders into the TextBox to insert their path (planned)
- **Tab completion in TextBox** — For now, tab completion requires using the terminal input directly

## 💻 Install

### DMG (recommended)

<a href="https://github.com/alumican/cmux-tb/releases/latest/download/cmux-tb-macos.dmg">
  <img src="./docs/assets/macos-badge.png" alt="Download cmux + TextBox for macOS" width="180" />
</a>

Open the `.dmg` and drag cmux to your Applications folder.

### Build from source

```bash
git clone --recurse-submodules https://github.com/alumican/cmux-tb.git
cd cmux
./scripts/setup.sh
./scripts/reload.sh --tag textbox
```

## ⌨ Keyboard Shortcuts

### TextBox

| Shortcut | Action |
|----------|--------|
| ⌘ ⌥ T (Cmd + Option + T) | Show/Hide TextBox (configurable) |
| Return | Send text to terminal (swappable with Shift+Return) |
| ⇧ Return (Shift + Return) | Insert newline (swappable with Return) |
| ESC | Focus terminal or send ESC key (configurable) |

All standard cmux shortcuts continue to work. See the [cmux README](https://github.com/manaflow-ai/cmux#keyboard-shortcuts) for the full list.

## Settings

| Setting | Default | Description |
|---------|---------|-------------|
| Enable Mode | On | Enable TextBox input |
| Send on Return | On | Return sends text, Shift+Return inserts newline (swap when off) |
| Escape Key | Send ESC Key | Action when pressing ESC (Focus Terminal / Send ESC Key) |
| Keyboard Shortcut (⌘⌥T) | Toggle Focus | **Toggle Focus**: switch focus between TextBox and terminal. **Toggle Display**: show/hide TextBox |

## 📄 License

Same as cmux — [AGPL-3.0-or-later](LICENSE).
