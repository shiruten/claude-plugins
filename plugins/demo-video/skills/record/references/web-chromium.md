# Recording Chromium with agent-browser (`web`)

Use this for changes that do not depend on WebKit-specific behavior and are not inside a native app. It is fast, headless-capable, and records straight to mp4. Remember it is Chromium: cookie, IME and rendering-library quirks of Safari will not reproduce, so say "recorded in Chromium" in the summary.

## Prerequisites

- `npm install -g agent-browser` (https://github.com/vercel-labs/agent-browser). The npm postinstall downloads Chrome for Testing into `~/.agent-browser/browsers` through Node, which honors `NODE_EXTRA_CA_CERTS`; the Rust-side `agent-browser install` may fail behind corporate TLS interception, but you do not need it once Chrome is present.
- If the environment block shows `chrome=MISSING`, point at an installed browser: `export AGENT_BROWSER_EXECUTABLE_PATH="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"`.
- `agent-browser doctor` reporting "Chrome for Testing CDN unreachable" is harmless when a browser is already available.
- ffmpeg on PATH (recording is encoded with it).

## Recording

The command vocabulary (`snapshot -i` refs, `click`, `fill`, `wait text`) matches agent-device.

```bash
agent-browser open http://localhost/<path>
agent-browser set viewport 390 844                       # phone width; 1280 800 for desktop
agent-browser record start ~/Movies/pr-demo/<name>/scene1.mp4 --fps 30
# ... act on @refs; confirm with wait text
agent-browser record stop
agent-browser close
```

- Default to **one phone-width video**. Make a separate desktop-width video only when the request mentions desktop or responsive behavior; do not mix widths in one video (build.sh rejects differing resolutions).
- Local dev toolbars (Laravel Debugbar, Django toolbar, ...) show up in recordings. Close them via their own UI first; only ask the user to disable them in config if they keep coming back on reload.
- Framework-bound inputs: prefer `fill` on plain inputs, and `click` + `type` when a value must arrive as keystrokes.
