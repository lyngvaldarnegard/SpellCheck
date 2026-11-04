# SpellCheck

A FixKey-style macOS menu-bar app that corrects the text you are working on —
anywhere. Select some text (or just place the caret inside a sentence), press
the global hot key, review the correction, and it is typed back into the app
you were using.

## Features

- **Works in every app** — grabs the selection (or the current sentence) from
  the frontmost application via the Accessibility API and pastes the corrected
  text back over it.
- **Global hot key** — default ⌥⌘K, configurable in Settings.
- **Two backends**
  - *Offline (rule-based)* — fixes common misspellings, doubled words, doubled
    letters, missing spaces after punctuation, and capitalization. No account
    needed.
  - *OpenAI-compatible API* — any chat-completions endpoint (OpenAI, DeepSeek,
    OpenRouter, Ollama, LM Studio, …) for rewriting, summarizing, expanding and
    translating. Settings can **fetch the model list from the API** so you can
    pick the model from a dropdown instead of typing its name.
- **Built-in actions** — Fix typos and grammar, Make professional, Make casual,
    Summarize, Expand, Translate (with configurable target language).
- **Custom prompts** — define your own actions in Settings; they appear in the
  menu-bar menu.
- **Confirmation window** — review the original and corrected text side by
  side before anything is replaced (can be turned off).

## Install

### Download (recommended)

Releases are published on the [Releases](https://github.com/lyngvaldarnegard/SpellCheck/releases)
page (tagged `v*.*.*`, built by CI on macOS). Download `SpellCheck-macOS.zip`,
unzip it, move `SpellCheck.app` to your **Applications** folder and launch it.

Because the app is not notarized yet, macOS Gatekeeper may block the first
launch: **right-click the app → Open → Open** (or allow it in System Settings →
Privacy & Security). Then grant **Accessibility** permission (System Settings →
Privacy & Security → Accessibility → add SpellCheck) — the app prompts for it
on first use.

### Build from source

```sh
git clone https://github.com/lyngvaldarnegard/SpellCheck.git
cd SpellCheck
scripts/build-app.sh        # creates build/SpellCheck.app (release)
# or, to also produce the distributable zip:
scripts/package-release.sh  # creates build/SpellCheck-macOS.zip
```

To distribute a signed/notarized build, set `SIGNING_IDENTITY`:

```sh
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" scripts/package-release.sh
```

## Requirements

- macOS 13 (Ventura) or later
- Swift 6 toolchain (Xcode 16+) — only needed to build from source
- Accessibility permission (System Settings → Privacy & Security →
  Accessibility) — SpellCheck prompts for it on first use

## Project layout

| Path      | Contents                                                        |
|-----------|-----------------------------------------------------------------|
| `Core/`   | Platform-independent logic: rule-based corrector, sentence extraction, prompt building, settings model, hot-key model. Fully unit tested on any OS. |
| `Engine/` | Platform-independent orchestration: grabbing text, running a backend, confirmation, settings persistence. Fully unit tested on any OS. |
| `App/`    | The macOS menu-bar app (AppKit/SwiftUI): status bar, hot key, Accessibility text source, settings and confirmation windows. Build only on macOS. |
| `scripts/`| Helper scripts: `test-core.sh`, `test-engine.sh`, `test-app.sh`, `build-app.sh` (assembles `SpellCheck.app`), `package-release.sh` (zips it for Releases). |
| `App/Info.plist` | App bundle metadata (menu-bar agent, Accessibility usage description). Used when packaging the app bundle in Xcode; SPM ignores it. |

## Using an API provider (e.g. DeepSeek)

1. Open SpellCheck → **Settings…** (or press `,` in the menu-bar menu).
2. Choose backend **OpenAI-compatible API**.
3. Click the **DeepSeek** provider preset (fills in `https://api.deepseek.com/v1`
   and the cheap, fast `deepseek-chat` model; `deepseek-reasoner` is the
   slower reasoning model — both appear in the list).
4. Paste your API key from [platform.deepseek.com](https://platform.deepseek.com/api_keys).
5. Click **Fetch models** — the dropdown is filled from the API's `/models`
   endpoint, so you can pick exactly the model you want.
6. Click **Save**.

Other presets: OpenAI, OpenRouter, Ollama (local, no key needed — models are
fetched from `http://localhost:11434/v1`). You can always type a custom base
URL and model name manually.

## Testing

```sh
scripts/test-core.sh          # Core unit tests (any OS)
scripts/test-engine.sh        # Engine unit tests (any OS)
scripts/test-app.sh           # App tests (macOS)
```

## Usage

1. Launch SpellCheck. A keyboard icon appears in the menu bar.
2. Grant Accessibility permission when asked.
3. In any app, select text (or click inside a sentence).
4. Press ⌥⌘K (or click the menu-bar icon and pick an action).
5. Review the proposed correction and click **Replace**.

## Privacy

Text is only sent to the network when you configure an API backend. The
offline rule-based backend never leaves your machine. The API key is stored in
the app's Application Support directory.
