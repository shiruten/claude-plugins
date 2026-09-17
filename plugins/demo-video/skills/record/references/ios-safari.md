# Recording Safari on the iOS Simulator (`ios`)

Use this when the change touches WebKit-specific behavior (cookies, IME, rendering libraries, WebView bridges) or when the subject is a WebView inside an app. Mobile-web pages render identically in Simulator Safari and in a WKWebView, so you usually do not need the native app running.

## Prerequisites

- A booted simulator: `xcrun simctl list devices booted`. Recordings come out at the device's native resolution (e.g. 1206×2622 on iPhone 17 Pro); `build.sh` downsizes.
- `agent-device` for driving the UI (`npm i -g agent-device`). Recording is done by `scripts/rec.sh`, not by agent-device.
- Test accounts and URLs come from the project notes or the request. Never type real user credentials.

## Pre-flight checks (read the environment block)

1. **Keyboard**: if narration or inputs use a non-Latin language, the simulator's software keyboard can mangle ASCII typed by automation (a Japanese keyboard turns `dummy` into `づっmy`). The `keyboard=` value should contain `en_US@sw=QWERTY;hw=Automatic`. If not: `xcrun simctl spawn booted defaults write com.apple.Preferences AppleKeyboards -array "en_US@sw=QWERTY;hw=Automatic"`, then `xcrun simctl shutdown booted && xcrun simctl boot <udid>`. The setting only applies after a reboot and survives until the simulator is erased.
2. **Secure cookies on http://localhost**: Safari and WKWebView drop cookies flagged `Secure` on plain-http localhost, while Chrome and Firefox treat localhost as an exception. If login loops or returns 419/CSRF errors only in the simulator, the app's session cookie is `Secure`; ask the user to disable that for local development.
3. **agent-device sessions**: `agent-device session list`; close leftovers. A session held by another working directory shows as `DEVICE_IN_USE`. If closing does not help, kill the agent-device daemon by pid and remove `~/.agent-device/sessions/<name>` and `device-claims`. Do not `pkill -f agent-device` (it can kill your own shell). Always pass `--session ios` afterwards.
4. **One recorder at a time**: the simulator allows a single screen recording. Close any live simulator panel that captures the screen. `pgrep -fl recordVideo`; a leftover can be finished with `kill -INT <pid>` (the mp4 gets its moov atom and stays playable).

## Recording

Drive with agent-device, record with `rec.sh`. Do not use agent-device's own `record` here: it loses ownership of the simctl process when other commands run in between and leaves a 0-byte file. Do not use `agent-browser -p ios` either: as of 0.37 it has no iOS implementation of `snapshot`, `type`, `viewport` or `record`, its `tap` ignores selectors and taps fixed coordinates, and merely opening it downloads Appium via npx.

```bash
agent-device open com.apple.mobilesafari http://localhost/login --platform ios --foreground --session ios
REC=${CLAUDE_SKILL_DIR}/scripts/rec.sh
$REC start ~/Movies/pr-demo/<name>/scene1.mp4
# ... act on @refs from `agent-device snapshot -i`; confirm with wait text / is / find
$REC stop  ~/Movies/pr-demo/<name>/scene1.mp4     # waits for the moov atom
```

To change page, run `agent-device open com.apple.mobilesafari <url> --platform ios --session ios` again. To switch roles, log out and log in as the other account.

## Input recipe (iOS Safari specifics)

- **Focus with `press @ref`, then `type`.** `fill` sets the value without firing `input`, so framework-bound fields (v-model, controlled inputs) may not update.
- **type → neutral tap → button.** iOS consumes the first tap after typing to dismiss the keyboard, so pressing Submit right after `type` only closes the keyboard. Tap a harmless point first (`press 200 70`, e.g. the header), then `press 'role=button label="Send"'`. `agent-device keyboard dismiss` reports UNSUPPORTED on some devices.
- **Refs expire** after every mutation. Re-run `snapshot -i` before the next `press`.
- **Prefer refs and `role=… label=…` selectors** over coordinates. Coordinates drift when banners change the layout; use them only for unlabeled `<img>` controls, and measure from a zoomed screenshot.
- **Scroll inside lists with `gesture pan <x> <y> <dx> <dy> <ms>`**, keeping start and end points away from screen edges (edge starts become OS gestures). Plain `scroll` moves the outer page, not inner scroll containers.
- **Reactive UI caveat**: state added to an existing item may not render until a full reload (e.g. Vue 2 non-reactive properties plus incremental polling). Show the result on the other user's freshly loaded screen instead of waiting on the same one.

## If the subject really is the native app

Open the app bundle with `agent-device open <bundle-id> --platform ios --foreground --session ios` and record the same way. Dev clients (Expo etc.) need their bundler reachable from the simulator; keep that setup in the project notes. Dismiss red error overlays with `agent-device react-native dismiss-overlay`.
