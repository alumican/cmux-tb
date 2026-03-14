<h1 align="center">cmux + TextBox</h1>
<p align="center">A fork of <a href="https://github.com/manaflow-ai/cmux">cmux</a> with a built-in TextBox input mode</p>

<p align="center">
  <a href="https://github.com/alumican/cmux-tb/releases/latest/download/cmux-macos.dmg">
    <img src="./docs/assets/macos-badge.png" alt="Download cmux + TextBox for macOS" width="180" />
  </a>
</p>

<p align="center">
  English | <a href="README.ja.md">日本語</a>
</p>

<p align="center">
  <video src="./docs/assets/textbox-top.mp4" autoplay loop muted playsinline></video>
</p>

## Why TextBox?

Terminals weren't designed for writing long-form input. There's no easy way to go back and edit a previous line, selecting and cutting arbitrary ranges of text is cumbersome, and multi-line text requires awkward escapes or heredocs. For anyone used to normal text editors, this friction adds up fast.

TextBox adds a persistent input bar at the bottom of each terminal pane. It bridges the gap between a rich text editor and the raw terminal — two input modes that feel like one seamless experience.

## Features

<table>
<tr>
<td width="40%" valign="middle">
<h3>Seamless and modeless</h3>
When the TextBox is empty, arrow keys, Tab, and Backspace pass through to the terminal.
<br/>
<br/>
Ctrl+key combinations (Ctrl+C, Ctrl+D, Ctrl+Z, etc.) and Escape are always forwarded regardless of content.
</td>
<td width="60%">
<video src="./docs/assets/textbox-seamless.mp4" autoplay loop muted playsinline width="100%"></video>
</td>
</tr>
<tr>
<td width="40%" valign="middle">
<h3>Ready when you need it</h3>
Toggle the TextBox with a shortcut — focus moves seamlessly between the input bar and terminal.
</td>
<td width="60%">
<img src="./docs/assets/textbox-toggle.gif" alt="TextBox toggle" width="100%" />
</td>
</tr>
<tr>
<td width="40%" valign="middle">
<h3>Familiar editing</h3>
Arrow keys, selection, copy/paste — it just works.
</td>
<td width="60%">
<video src="./docs/assets/textbox-edit.mp4" autoplay loop muted playsinline width="100%"></video>
</td>
</tr>
<tr>
<td width="40%" valign="middle">
<h3>AI agent friendly</h3>
Edit prompts freely, reply to agents, or send interrupt commands — all without fighting the terminal.
</td>
<td width="60%">
<video src="./docs/assets/textbox-agent.mp4" autoplay loop muted playsinline width="100%"></video>
</td>
</tr>
<tr>
<td width="40%" valign="middle">
<h3>Settings</h3>
Configure Send on Return, Show/Hide shortcut, and more from the settings panel.
</td>
<td width="60%">
<img src="./docs/assets/textbox-settings.gif" alt="TextBox settings" width="100%" />
</td>
</tr>
<tr>
<td colspan="2">
<h3>Send on Return</h3>
Choose whether Return sends text immediately or inserts a newline (Shift+Return for the other).
</td>
</tr>
</table>

## Install

### DMG (recommended)

<a href="https://github.com/alumican/cmux-tb/releases/latest/download/cmux-macos.dmg">
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

## Keyboard Shortcuts

### TextBox

| Shortcut | Action |
|----------|--------|
| ⌘ ⌥ T (Cmd + Option + T) | Toggle TextBox on/off |
| Return | Send text to terminal (when Send on Return is enabled) |
| ⇧ Return (Shift + Return) | Insert newline (when Send on Return is enabled) |
| ESC | Focus terminal or send ESC key (configurable) |

All standard cmux shortcuts continue to work. See the [cmux README](https://github.com/manaflow-ai/cmux#keyboard-shortcuts) for the full list.

## Settings

| Setting | Default | Description |
|---------|---------|-------------|
| Enable Mode | On | Enable TextBox input |
| Send on Return | On | Return sends text, Shift+Return inserts newline (swap when off) |
| Escape Key | Send ESC Key | Action when pressing ESC (Focus Terminal / Send ESC Key) |
| Show/Hide TextBox Input | ⌘⌥T | Keyboard shortcut to toggle TextBox |

## License

Same as cmux — [AGPL-3.0-or-later](LICENSE).
