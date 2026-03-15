<h1 align="center">cmux + TextBox</h1>
<p align="center"><a href="https://github.com/manaflow-ai/cmux">cmux</a> にテキストボックス入力モードを組み込んだフォーク</p>

<p align="center">
  <a href="https://github.com/alumican/cmux-tb/releases/latest/download/cmux-tb-macos.dmg">
    <img src="./docs/assets/macos-badge.png" alt="cmux + TextBox for macOS をダウンロード" width="180" />
  </a>
</p>

<p align="center">
  <a href="README.md">English</a> | 日本語
</p>

<p align="center">
  <video src="https://github.com/user-attachments/assets/9e83cc01-97a2-4c06-90cd-1c98422e9f3a" autoplay loop muted playsinline></video>
</p>

## なぜテキストボックス？

普段のテキストエディタに慣れていると、ターミナルの書き心地は難しいと感じるでしょう。改行・選択・カット・ペーストなど、普段無意識にやっていることがいちいちうまくいかない・・・。

このテキストボックス付きのターミナルは、書きたいことをそのまま書けばOKです。もちろん、ターミナルの入力インターフェースもそのまま使えます。

ややこしそう？大丈夫。2つ入力モードの境界を自然に溶け合わせる工夫が散りばめられているので、違和感なく使えます。

## 機能

<table>
<tr>
<td width="40%" valign="middle">
<h3>シームレス＆モードレス</h3>
テキストボックスが空のとき、矢印キー・Tab・Backspace はそのままターミナルに送られます。
<br/>
<br/>
Ctrl+キー（Ctrl+C、Ctrl+D、Ctrl+Z など）や ESCキー は、入力中でも関係なく常にターミナルに送られます。
</td>
<td width="60%">
<video src="https://github.com/user-attachments/assets/f305e06e-a55e-4477-93f2-11d3bd17d03a" autoplay loop muted playsinline width="100%"></video>
</td>
</tr>
<tr>
<td width="40%" valign="middle">
<h3>必要なときすぐそこに</h3>
ショートカットでテキストボックスの表示を切り替えると、フォーカスもテキストボックスとターミナルの間をスムーズに移動するので、すぐにタイピングを始められます。
</td>
<td width="60%">
<img src="./docs/assets/textbox-toggle.gif" alt="テキストボックス トグル" width="100%" />
</td>
</tr>
<tr>
<td width="40%" valign="middle">
<h3>使い慣れた操作感</h3>
テキストボックスは使い慣れたOSネイティブのものを使用。矢印キー、選択、コピー＆ペースト、いつもの操作がそのまま使えます。
</td>
<td width="60%">
<video src="https://github.com/user-attachments/assets/a7777bfa-f63f-4273-bf5a-2778bea643dd" autoplay loop muted playsinline width="100%"></video>
</td>
</tr>
<tr>
<td width="40%" valign="middle">
<h3>Claude Codeとの相性抜群</h3>
エージェントの起動、プロンプト編集、エージェントへの返答、処理の中断。テキストボックスの中にいたままで操作できます。もちろん他のターミナルエージェントとも。
</td>
<td width="60%">
<video src="https://github.com/user-attachments/assets/69e0cea8-c975-49b3-87cc-711cf64b2ff4" autoplay loop muted playsinline width="100%"></video>
</td>
</tr>
<tr>
<td width="40%" valign="middle">
<h3>設定</h3>
送信はEnter or Shift+Enter？ESCキーの動作は？あなたに馴染む設定にカスタマイズできます。
</td>
<td width="60%">
<img src="./docs/assets/textbox-settings.gif" alt="テキストボックス設定" width="100%" />
</td>
</tr>
</table>

### 今はまだできないこと

- **ファイル・フォルダのドロップ入力** — テキストボックスにドロップしてパスを挿入する機能（実装予定）
- **テキストボックス内へのTabによる入力補完** — 現状、Tab補完を使う場合はターミナル入力を使う必要があります

## インストール

### DMGでインストール（推奨）

<a href="https://github.com/alumican/cmux-tb/releases/latest/download/cmux-tb-macos.dmg">
  <img src="./docs/assets/macos-badge.png" alt="cmux + TextBox for macOS をダウンロード" width="180" />
</a>

`.dmg` を開いて cmux を Applications フォルダにドラッグしてください。

### ソースからビルド

```bash
git clone --recurse-submodules https://github.com/alumican/cmux-tb.git
cd cmux
./scripts/setup.sh
./scripts/reload.sh --tag textbox
```

## キーボードショートカット

### テキストボックス

| ショートカット | 操作 |
|----------|--------|
| ⌘ ⌥ T (Cmd + Option + T) | テキストボックスの表示/非表示（設定で変更可） |
| Return | テキストをターミナルに送信（Shift + Returnと入れ替え可） |
| ⇧ Return (Shift + Return) | 改行を挿入（Returnと入れ替え可） |
| ESC | ターミナルにフォーカスを戻す or ESCキーを送信（設定で切替） |

cmux の標準ショートカットもそのまま使えます。全一覧は [cmux README](https://github.com/manaflow-ai/cmux#keyboard-shortcuts) をご覧ください。

## 設定

| 設定 | デフォルト | 説明 |
|---------|---------|-------------|
| モードを有効化 | オン | テキストボックス入力を有効化する |
| Enterで送信 | オン | Returnで送信、Shift+Returnで改行（オフで逆） |
| Escapeキー | ESCキーを送信 | ESCキーの動作（ターミナルにフォーカス / ESCキーを送信） |
| テキストボックス入力の表示/非表示 | ⌘⌥T | 表示/非表示のキーボードショートカット |

## ライセンス

cmux と同じ — [AGPL-3.0-or-later](LICENSE)。
