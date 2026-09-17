# demo-video

A [Claude Code](https://code.claude.com) plugin for macOS. It records a short video that shows a pull request's feature actually working, adds spoken narration (and captions if you ask), and can attach the video to the PR.

Reviewers press play and see the change; they do not have to check out the branch.

## What you get

- **Real screen recordings**, not screenshots. Two targets: `web` records Chromium through [agent-browser](https://github.com/vercel-labs/agent-browser); `ios` records Safari on the iOS Simulator (real WebKit) through [agent-device](https://www.npmjs.com/package/agent-device) and `xcrun simctl`.
- **One sentence of narration per scene**, spoken by macOS `say`. Pass `-c` to also burn it in as captions, so the video works with the sound off.
- **A short title card before each scene** naming what is about to happen.
- **A paste-ready PR comment** (`summary.md`) with a table of scenes, and optionally the upload itself via `gh pr comment --attach`.

Everything runs on your machine. Narration text is never sent to a service.

## How it works

```text
/demo-video:record [-w|-i] [-t "name"] [-pr #123|url] [-c] [-sr "scene requests"]
  1. Script      write scenes.tsv: one line per scene = id, what happens, narration sentence
  2. Record      one video file per scene, driving the app in Chromium or Simulator Safari
  3. Build       scripts/build.sh: narration → captions → title cards → ffmpeg → one mp4 + summary.md
  4. Show        open the mp4 for you; if a PR was given, ask, then attach it with gh
  5. Clean up    close sessions, undo fixtures, return to your branch, delete the work folder once the PR has the video
```

Each scene lasts as long as the longer of its video and its narration: the last frame is held while the voice finishes, or silence is added while the video finishes. Before joining scenes, the script checks that every piece has the same resolution, frame rate and audio format, and that the total length matches. Because the agent cannot watch a video, the build also writes a 3×3 contact sheet per scene (`sheets/`) that the agent reads to confirm the right things appear.

Claude never starts this on its own. You type the command.

## Requirements

macOS only (`say`, `xcrun simctl` and Swift are used).

| Needed for | Install |
| --- | --- |
| always | `ffmpeg` and `ffprobe`: `brew install ffmpeg` |
| captions and title cards | Xcode Command Line Tools: `xcode-select --install` (provides `swiftc`) |
| `web` target | `npm i -g agent-browser` (downloads its own Chrome on install) |
| `ios` target | `npm i -g agent-device`, plus Xcode with a booted iOS Simulator |
| attaching to a PR | GitHub CLI `gh` 2.99 or newer, logged in with `gh auth login` |

Without `gh` (or with an older version) the plugin still produces the video and prints the command you would run to attach it.

## Install

Inside Claude Code:

```text
/plugin marketplace add shiruten/claude-plugins
/plugin install demo-video@shiruten
```

To try it without installing, clone this repository and start Claude Code with it loaded:

```bash
git clone https://github.com/shiruten/claude-plugins.git
claude --plugin-dir ./demo-video
```

## Use

```text
/demo-video:record                                  # Chromium, named after the current branch; prints the gh command to attach
/demo-video:record -i -t checkout-flow -pr #123 -c   # Simulator Safari, saved as "checkout-flow", captions on, attached to PR #123 after you confirm
/demo-video:record -sr "show the empty state and the reset button"
```

| Flag | Meaning | Default |
| --- | --- | --- |
| `-w` | record Chromium | on |
| `-i` | record Safari on the iOS Simulator (real WebKit) | |
| `-t "name"` | video name (folder and file) | current branch name |
| `-pr #123` or a PR URL | attach to that PR after you confirm | none: build only and print the command |
| `-c` | burn the narration in as captions | off |
| `-sr "text"` | requests for what the scenes should show; bare words count too | none |

Flags can come in any order.

Videos are built in `~/Movies/pr-demo/<video-name>/` (set `PR_DEMO_DIR` to change). If the video is attached to the PR, that folder is deleted afterwards; the PR comment is the copy that matters. If nothing is attached, the folder is kept.

### Tell the plugin about your project

Create `.claude/demo-video.md` in your repository with facts the recording needs, and the plugin reads it at run time:

```markdown
- Local app: http://localhost:3000, started with `npm run dev`
- Test accounts: buyer@example.test / password123, seller@example.test / password123
- Roles: buyer and seller see different screens; record buyer first
- Title card colour: 0x1f3a5f
- Cleanup: delete orders created during the demo
```

The plugin itself contains nothing specific to any project.

### Narration voice and captions

`build.sh` uses the system's default voice unless you pass `--voice NAME` (for Japanese, `--voice Kyoko`). The name is checked first, because `say` silently uses a different voice when the name is wrong. Captions are off unless `--captions` is given (`-c` on the command does this); they use the system font, which covers Latin, CJK and other scripts, and `--font NAME` overrides it.

Other `build.sh` options: `--rate` (words per minute), `--height` (max output height, default 1280), `--crf` (quality), `--font-size`, `--title-color`, `--title-sec`, `--no-title-cards`.

## What is Claude Code-specific

The packaging (`plugin.json`), the `/demo-video:record` command, argument substitution and the shell blocks in `SKILL.md` that run when the skill loads are Claude Code features. Other tools that read `SKILL.md` files will show those blocks as plain text.

The scripts are not tied to Claude Code. `skills/record/scripts/build.sh`, `rec.sh` and `caption.swift` are ordinary bash and Swift: give `build.sh` a folder with `scenes.tsv` and one recording per scene, and it produces the video from any shell.

## Layout

```text
skills/record/
├── SKILL.md                 the workflow the agent follows
├── references/
│   ├── ios-safari.md        Simulator Safari: checks before recording, recording, input quirks
│   └── web-chromium.md      agent-browser: setup, viewport, recording
└── scripts/
    ├── args.sh              parses the command flags into key=value lines
    ├── build.sh             scenes.tsv → narration → captions → title cards → ffmpeg → mp4 + summary.md
    ├── rec.sh               start/stop a simulator screen recording
    └── caption.swift        draws caption and title images with CoreText (no ffmpeg text filters needed)
```

---

## 日本語

macOS 向けの [Claude Code](https://code.claude.com) plugin です。PR の機能が実際に動く様子を短い動画に録画し、ナレーション（指定すれば字幕も）を付けて、PR に添付できます。レビュアーは再生するだけで変更を確認でき、ブランチをチェックアウトする必要がありません。

### できること

- **実操作の録画**（静止画ではない）。`web` は agent-browser で Chromium を、`ios` は agent-device と `xcrun simctl` で iOS シミュレータの Safari（本物の WebKit）を録画
- **シーンごとに 1 文のナレーション**を macOS の `say` で読み上げ。`-c` を付けると同じ文を字幕として焼き込み、音を出せない環境でも内容が伝わる
- **各シーンの前に短いタイトルカード**
- **貼り付け用の PR コメント本文**（`summary.md`、シーンの表入り）。PR 番号を渡せば `gh pr comment --attach` で添付まで行う

すべて手元の Mac で完結し、ナレーション文は外部に送られません。

### 動き方

```text
/demo-video:record [-w|-i] [-t "動画名"] [-pr #123|URL] [-c] [-sr "シーンの要望"]
  1. 台本      scenes.tsv を書く。1 行 1 シーン = id、操作の要点、ナレーション 1 文
  2. 録画      シーンごとに 1 ファイル。Chromium かシミュレータ Safari でアプリを操作
  3. 組み立て  scripts/build.sh: 音声 → 字幕 → タイトルカード → ffmpeg → 1 本の mp4 + summary.md
  4. 確認      mp4 を開いて見せる。PR 指定があれば許可を得て gh で添付
  5. 後片付け  セッションを閉じ、フィクスチャを戻し、元のブランチへ。PR に貼れたら作業フォルダを削除
```

各シーンの長さは「映像と音声の長い方」です。声が長ければ最後のコマを止め絵にし、映像が長ければ無音を足します。結合前に全シーンの解像度・フレームレート・音声形式が揃っていることと、合計長が一致することを検査します。エージェントは動画を再生できないので、シーンごとの 3×3 コンタクトシート（`sheets/`）を読んで、狙った画面が映っていることを確認します。

このコマンドは Claude が勝手に起動することはありません。人が打ったときだけ動きます。

### 必要なもの

macOS 専用（`say`・`xcrun simctl`・Swift を使うため）。

| 用途 | 導入 |
| --- | --- |
| 常に | `ffmpeg` と `ffprobe`: `brew install ffmpeg` |
| 字幕とタイトルカード | Xcode Command Line Tools: `xcode-select --install`（`swiftc` が入る） |
| `web` | `npm i -g agent-browser`（導入時に自前の Chrome を取得） |
| `ios` | `npm i -g agent-device` と、Xcode で起動した iOS シミュレータ |
| PR への添付 | GitHub CLI `gh` 2.99 以上、`gh auth login` 済み |

`gh` が無い、または古いときも動画は作られ、添付に使うコマンドが表示されます。

### 導入

Claude Code の中で:

```text
/plugin marketplace add shiruten/claude-plugins
/plugin install demo-video@shiruten
```

導入せずに試すなら、clone して読み込んで起動します。

```bash
git clone https://github.com/shiruten/claude-plugins.git
claude --plugin-dir ./demo-video
```

### 使い方

```text
/demo-video:record                                  # Chromium で録画、動画名はブランチ名。添付用の gh コマンドを表示
/demo-video:record -i -t checkout-flow -pr #123 -c   # シミュレータ Safari で録画、「checkout-flow」として保存、字幕あり、確認のうえ PR #123 に添付
/demo-video:record -sr "空の状態とリセットボタンを見せて"
```

| フラグ | 意味 | 既定 |
| --- | --- | --- |
| `-w` | Chromium で録画 | これ |
| `-i` | iOS シミュレータの Safari（本物の WebKit）で録画 | |
| `-t "名前"` | 動画名（フォルダとファイル名） | 現在のブランチ名 |
| `-pr #123` か PR の URL | 確認のうえ、その PR に添付 | なし。動画を作ってコマンドを表示するだけ |
| `-c` | ナレーションを字幕として焼き込む | なし |
| `-sr "文"` | シーンで見せたいことの要望。フラグ無しの語も同じ扱い | なし |

フラグの順番は自由です。

動画は `~/Movies/pr-demo/<動画名>/` に作られます（`PR_DEMO_DIR` で変更可）。PR に添付できたらこのフォルダは削除されます。原本は PR のコメントです。添付しなかった場合は残ります。

### プロジェクトの事情を伝える

リポジトリに `.claude/demo-video.md` を置くと、実行時に読み込まれます。

```markdown
- ローカル: http://localhost:3000、起動は `npm run dev`
- テストアカウント: buyer@example.test / password123、seller@example.test / password123
- 役割: 購入者と出品者で画面が違う。購入者から撮る
- タイトルカードの色: 0x1f3a5f
- 後片付け: デモ中に作った注文を削除
```

plugin 本体には特定のプロジェクトの情報は入っていません。

### ナレーションの声と字幕

`build.sh` は `--voice 名前` を渡さなければ OS の既定音声を使います（日本語なら `--voice Kyoko`）。`say` は存在しない名前を渡すと黙って別の声になるので、先に名前を検証します。字幕は `--captions`（コマンドの `-c`）を付けたときだけ焼き込み、システムフォントで描くため日本語を含む多くの文字に対応します。`--font 名前` で変更できます。

### Claude Code 専用の部分

`plugin.json`、`/demo-video:record` コマンド、引数の置換、`SKILL.md` 内で読込時に実行されるシェルブロックは Claude Code の機能です。他のツールで `SKILL.md` を読むと、それらは文字列として表示されます。

スクリプトは Claude Code に依存しません。`skills/record/scripts/` の `build.sh`・`rec.sh`・`caption.swift` は普通の bash と Swift で、`scenes.tsv` とシーンごとの録画が入ったフォルダを `build.sh` に渡せば、どのシェルからでも動画ができます。

## License

MIT
