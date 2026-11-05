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
- **Proper icons** — an Ω + checkmark glyph in the menu bar (template image, so
  it follows light/dark mode like FixKey's) and a full app icon (`AppIcon.icns`)
  shown in the Dock, Finder and Applications folder. The menu-bar icon is
  **selectable in Settings → Menu Bar Icon** (Ω + checkmark, Ω only, classic
  spellcheck, or plain checkmark).
- **Two backends**
  - *Offline (rule-based)* — fixes common misspellings, doubled words, doubled
    letters, missing spaces after punctuation, and capitalization. No account
    needed.
  - *OpenAI-compatible API* — any chat-completions endpoint (Mistral, OpenAI,
    DeepSeek, OpenRouter, Ollama, LM Studio, …) for rewriting, summarizing,
    expanding and translating. Settings can **fetch the model list from the
    API** so you can pick the model from a dropdown instead of typing its name.
- **Built-in actions** — Fix typos and grammar, Make professional, Make casual,
    Summarize, Expand, Translate (with configurable target language).
- **Custom prompts** — define your own actions in Settings; they appear in the
  menu-bar menu.
- **Confirmation window** — review the original and corrected text side by
  side before anything is replaced (can be turned off).
- **Auto-update** — built on [Sparkle](https://sparkle-project.org): the app
  checks an appcast feed (`appcast.xml` on `main`) and offers to download and
  install new releases. There is also a **Check for Updates…** item in the
  menu-bar menu.

## Install

SpellCheck is a menu-bar app for **macOS 13 (Ventura) or later**. Pick one of
the two ways below.

### Option A — download the prebuilt app (recommended)

1. Go to the repo's [**Releases**](https://github.com/lyngvaldarnegard/SpellCheck/releases)
   page and download **`SpellCheck-macOS.zip`** from the latest release.
   - If no release exists yet, create one: merge the PR into `main`, then in
     the repo go to **Actions → Release → Run workflow** (branch `main`,
     version e.g. `v0.1.0`) and wait for it to finish — it builds on a macOS
     runner, tests, signs (if secrets are set) and uploads the zip.
     (Push-triggered workflows are restricted in this repo, so the manual
     dispatch is the reliable way.)
2. Unzip the archive (double-click it in Downloads).
3. Drag **`SpellCheck.app`** into your **Applications** folder.
4. The first launch may be blocked by Gatekeeper because the app is not
   notarized: **right-click `SpellCheck.app` → Open → Open**. (If macOS shows
   "app can't be opened", also check System Settings → Privacy & Security for
   an "Open Anyway" button.)
5. Grant **Accessibility** permission: System Settings → Privacy & Security →
   **Accessibility** → enable **SpellCheck**. This is required so the app can
   read and edit text in other apps. The app will prompt you on first use.
6. Launch SpellCheck from Applications. An Ω✓ icon appears in the
   menu bar — click it for **Settings…** to enter your API key.

### Option B — build from source on your Mac

Requires Xcode 16+ / Swift 6 toolchain (preinstalled or via `xcode-select --install`).

```sh
git clone https://github.com/lyngvaldarnegard/SpellCheck.git
cd SpellCheck
git checkout vibe/spellcheck-scaffold-6a9537   # or main once merged
scripts/build-app.sh        # creates build/SpellCheck.app (release build)
# optional: also produce the distributable zip:
scripts/package-release.sh  # creates build/SpellCheck-macOS.zip
```

Then open `build/SpellCheck.app` (right-click → Open on first launch) or move
it to Applications. To produce a signed build for distribution:

```sh
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" scripts/package-release.sh
```

## Troubleshooting — "the app won't open"

Releases are bundle-verified in CI (`scripts/verify-bundle.sh`), so a missing
framework can no longer ship silently. If the app still won't start:

1. Make sure you downloaded the **latest** release (v0.1.4+) and deleted any
   older `SpellCheck.app` / zip from Downloads.
2. Gatekeeper: right-click the app → **Open** → **Open** (or run
   `xattr -dr com.apple.quarantine ~/Applications/SpellCheck.app` in Terminal).
   This is needed once per download until the app is notarized.
3. Run the binary directly in Terminal to see the real error:
   ```sh
   /Applications/SpellCheck.app/Contents/MacOS/SpellCheck
   ```
   (A missing-library error would print `dyld: Library not loaded: @rpath/...` —
   that was fixed in v0.1.4 by embedding `Sparkle.framework`.)
4. Check **Console.app** for a crash report named `SpellCheck`.
5. After launch: enable **Accessibility** in System Settings → Privacy & Security,
   then Settings opens automatically on first run.

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

## Auto-update setup (for maintainers)

Updates are served from the `appcast.xml` file on `main`; the `Release`
workflow regenerates it for every release and signs the zip when the
`SPARKLE_PRIVATE_KEY` secret is set.

1. Generate a Sparkle key pair (from a Sparkle checkout):
   `swift run sign_update --generate-keys`
2. Put the **public** key into `App/Info.plist` → `SUPublicEDKey`.
3. Add the **private** key as the GitHub repo secret `SPARKLE_PRIVATE_KEY`.
4. For reliable update installs, also code-sign releases: set the
   `SIGNING_IDENTITY` secret to your `Developer ID Application: …` identity.
   To also remove the Gatekeeper "not from an identified developer" warning,
   add notarization: create an App Store Connect API key with the *Developer
   ID* role and set the secrets `NOTARY_API_KEY` (base64 .p8),
   `NOTARY_API_KEY_ID` and `NOTARY_ISSUER_ID` — the release workflow then
   notarizes and staples the app automatically.
5. Publish a release — either push a tag (`git tag v0.1.0 && git push origin
   v0.1.0`) or, if push-triggered Actions are restricted in the repo, run it
   manually: **Actions → Release → Run workflow** (branch `main`, version
   `v0.1.0`). CI builds, tests, signs, publishes the GitHub Release with
   `SpellCheck-macOS.zip` and updates `appcast.xml` on `main`.

## Using an API provider (e.g. Mistral)

1. Open SpellCheck → **Settings…** (menu-bar icon, or press `,`).
2. Choose backend **OpenAI-compatible API**.
3. Click the **Mistral** provider preset — it fills in `https://api.mistral.ai/v1`
   and the cheap, fast `mistral-small-latest` model.
4. Paste your API key from [console.mistral.ai](https://console.mistral.ai/api-keys/).
5. Click **Fetch models** — the dropdown is filled from Mistral's `/v1/models`
   endpoint, so you can pick exactly the model you want (`mistral-small-latest`,
   `mistral-medium-latest`, `mistral-large-latest`, `codestral-latest`, …).
6. Click **Save**.

Other presets: OpenAI, DeepSeek, OpenRouter, Ollama (local, no key needed —
models are fetched from `http://localhost:11434/v1`). You can always type a
custom base URL and model name manually.

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
