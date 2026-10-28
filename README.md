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
  - *OpenAI-compatible API* — any chat-completions endpoint (OpenAI,
    OpenRouter, Ollama, LM Studio, …) for rewriting, summarizing, expanding and
    translating.
- **Built-in actions** — Fix typos and grammar, Make professional, Make casual,
    Summarize, Expand, Translate (with configurable target language).
- **Custom prompts** — define your own actions in Settings; they appear in the
  menu-bar menu.
- **Confirmation window** — review the original and corrected text side by
  side before anything is replaced (can be turned off).

## Requirements

- macOS 13 (Ventura) or later
- Swift 6 toolchain (Xcode 16+)
- Accessibility permission (System Settings → Privacy & Security →
  Accessibility) — SpellCheck prompts for it on first use

## Project layout

| Path      | Contents                                                        |
|-----------|-----------------------------------------------------------------|
| `Core/`   | Platform-independent logic: rule-based corrector, sentence extraction, prompt building, settings model, hot-key model. Fully unit tested on any OS. |
| `Engine/` | Platform-independent orchestration: grabbing text, running a backend, confirmation, settings persistence. Fully unit tested on any OS. |
| `App/`    | The macOS menu-bar app (AppKit/SwiftUI): status bar, hot key, Accessibility text source, settings and confirmation windows. Build only on macOS. |
| `scripts/`| Helper scripts: `test-core.sh`, `test-engine.sh`, `test-app.sh`, `build-app.sh`. |
| `App/Info.plist` | App bundle metadata (menu-bar agent, Accessibility usage description). Used when packaging the app bundle in Xcode; SPM ignores it. |

## Building

```sh
scripts/build-app.sh          # release build (macOS)
```

or open `App/Package.swift` in Xcode and run the `SpellCheck` scheme.

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
