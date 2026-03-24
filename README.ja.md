<h1 align="center">cmux + TextBox</h1>
<p align="center">ターミナルアプリ (<a href="https://github.com/manaflow-ai/cmux">cmux</a>) + テキストボックス入力モード</p>

<p align="center">
  <a href="https://github.com/alumican/cmux-tb/releases/latest/download/cmux-tb-macos.dmg">
    <img src="./docs/assets/macos-badge.png" alt="cmux + TextBox for macOS をダウンロード" width="180" />
  </a>
</p>

<p align="center">バージョン 0.62.2-tb11（2026/3/24更新）</p>

> [!Warning]
> macOS 14 (Sonoma) / macOS 15 (Sequoia) では、0.62.2-tb7 より前のバージョンでテキストボックスに入力した文字が表示されない不具合があります。左下の「?」ボタンから「Check for updates」を選択し、最新版にアップデートしてください。

<br>

<p align="center">
  <a href="README.md"><strong>English here</strong></a>&nbsp;&nbsp;|&nbsp;&nbsp;日本語
</p>

<br/>
<br/>

<p align="center">
  <img src="./docs/assets/textbox-top-image.png" alt="cmux + TextBox" />
</p>

## 🤔 なぜターミナルにテキストボックスを付けたのか

使い慣れてない人にとって、ターミナルの書き心地は難しいと感じることがあります。改行・選択・カット・ペーストなど、普段無意識にやっていることがいちいちうまくいかない・・・。このテキストボックス付きのターミナルは、書きたいことをそのまま書けばOKです。もちろん、ターミナルの入力インターフェースもそのまま使えます。

ややこしそう？大丈夫。2つ入力モードの境界を自然に溶け合わせる工夫が散りばめられているので、違和感なく使えます💪

<p align="center">
  <img src="./docs/assets/textbox-top.gif" alt="cmux + TextBox デモ" />
</p>

## 🚀 機能

<table>
<tr>
<td width="50%" valign="middle">
<h3>シームレス＆モードレス</h3>
<strong>テキストボックスが空のとき</strong>、矢印キー・Tab・Backspace はそのままターミナルに送られます。
<br/>
<br/>
Ctrl+キー（Ctrl+C、Ctrl+D、Ctrl+Z など）や ESCキー は、<strong>入力中でも関係なく</strong>常にターミナルに送られます。
</td>
<td width="50">
<img src="./docs/assets/textbox-seamless.gif" alt="シームレス＆モードレス" width="100%" />
</td>
</tr>
<tr>
<td width="50%" valign="middle">
<h3>必要なときすぐそこに</h3>
ショートカットでテキストボックスの表示を切り替えると、フォーカスもテキストボックスとターミナルの間をスムーズに移動するので、すぐにタイピングを始められます。
<br/>
<br/>
設定で「表示の切り替え」と「フォーカスの切り替え」から選べます。
</td>
<td width="50%">
<img src="./docs/assets/textbox-toggle.gif" alt="テキストボックス トグル" width="100%" />
</td>
</tr>
<tr>
<td width="50%" valign="middle">
<h3>使い慣れた操作感</h3>
テキストボックスは使い慣れたOSネイティブのものを使用。矢印キー、選択、コピー＆ペースト、いつもの操作がそのまま使えます。
</td>
<td width="50%">
<img src="./docs/assets/textbox-edit.gif" alt="使い慣れた操作感" width="100%" />
</td>
</tr>
<tr>
<td width="50%" valign="middle">
<h3>Claude Codeとの相性抜群</h3>
エージェントの起動、プロンプト編集、エージェントへの返答、「/」「@」コマンドの実行、処理の中断。テキストボックスの中にいたままで操作できます。もちろん他のターミナルエージェントとも。
</td>
<td width="50%">
<img src="./docs/assets/textbox-agent.gif" alt="Claude Codeとの相性抜群" width="100%" />
</td>
</tr>
<tr>
<td width="50%" valign="middle">
<h3>設定</h3>
送信はEnter or Shift+Enter？ESCキーの動作は？あなたに馴染む設定にカスタマイズできます。
</td>
<td width="50%">
<img src="./docs/assets/textbox-settings.gif" alt="テキストボックス設定" width="100%" />
</td>
</tr>
</table>

### 🚧 今はまだできないこと

- **ファイル・フォルダのドロップ入力** — テキストボックスにドロップしてパスを挿入する機能（実装予定）
- **テキストボックス内へのTabによる入力補完** — 現状、Tab補完を使う場合はターミナル入力を使う必要があります

## 💻 インストール

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

## ⌨ キーボードショートカット

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
| キーボードショートカット (⌘⌥T) | フォーカスの切り替え | **フォーカスの切り替え**: テキストボックスとターミナル間のフォーカス移動。**表示の切り替え**: テキストボックスの表示/非表示 |

## 📄 ライセンス

cmux と同じ — [AGPL-3.0-or-later](LICENSE)。
