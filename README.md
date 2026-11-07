# SpellCheck

A macOS menu-bar app that edits the text you are working on —
anywhere, through an AI API. Select some text (or just place the caret inside
a sentence), press **⌥L**, pick a prompt from the popup, and the AI's result
directly replaces your original text in the app you were using. No review
window, no confirmation step.

## Features

- **Works in every app** — grabs the selection (or the current sentence) from
  the frontmost application via the Accessibility API, with layered
  fallbacks (selected-text attribute → document value + range → clipboard)
  for editors that expose text differently, and writes the result back over
  the exact same range. The original app is re-activated before the text is
  replaced, so the result never lands in the wrong app.
- **Global shortcut ⌥L** opens the prompt picker (configurable in Settings;
  Option-only shortcuts are supported). Registration failures — e.g. a
  shortcut already taken by another app — are shown as an alert, never
  silently ignored. Carbon `RegisterEventHotKey` needs **no** Input
  Monitoring permission; only Accessibility is required.
- **Prompt picker** — a compact dark popup with a search field
  (focused, filters as you type), a scrollable list of prompts with icons,
  keyboard ↑/↓ selection, Enter to run, click to run, Escape to close,
  clicking outside dismisses it without editing anything, and an
  empty state when the search matches nothing.
- **Shared prompt** — an editable common instruction in its own Settings
  section, included in every request before the selected prompt. The default
  asks the model to return only the requested result, in the text's original
  language, without explanations, quotes or unsolicited Markdown.
- **Backup model** — optionally configure a second model; when a request fails
  temporarily (capacity, rate limit, server error, timeout) or returns an
  unusable response, the same request is retried once on the backup.
  Replacement is never retried automatically.
- **Fully editable prompts** — every prompt is an ordinary editable entry.
  The built-in defaults (Fix Grammar, Improve Writing, Make Shorter,
  Summarize, Explain this, Convert to Bullet Points, Translate to English —
  shipped as editable defaults) can be edited and deleted like your own.
- **Prompt Editor** — a separate two-pane window: searchable prompt list
  on the left, title + full prompt text + icon on the right, with Add, Save
  and Delete. ⌘S saves there too.
- **AI-only** — all editing runs through an OpenAI-compatible API (Mistral,
  OpenAI, DeepSeek, OpenRouter, Ollama, LM Studio, …). Provider presets pair
  the base URL with a matching model (the Mistral preset sets
  `mistral-small-latest`), and Settings can **fetch the model list** from the
  API so you pick from a dropdown. API errors are reported clearly.
- **Saves with confirmation** — ⌘S and the Save button persist Settings and
  Prompt Editor changes; a visible "Saved" indicator appears only after the
  write succeeded, and failures show an actionable error.
- **Launch at login** (via SMAppService).
- **Auto-update** — built on [Sparkle](https://sparkle-project.org); see
  [Auto-update setup](#auto-update-setup-for-maintainers) for the two things
  that must be configured before it goes live.

## Install

SpellCheck is a menu-bar app for **macOS 13 (Ventura) or later**.

### Option A — download the prebuilt app (recommended)

1. Go to the repo's [**Releases**](https://github.com/lyngvaldarnegard/SpellCheck/releases)
   page and download **`SpellCheck-macOS.zip`** from the latest release.
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

Requires Xcode 16+ / Swift 6 toolchain.

```sh
git clone https://github.com/lyngvaldarnegard/SpellCheck.git
cd SpellCheck
scripts/build-app.sh        # creates build/SpellCheck.app (release build)
# optional: also produce the distributable zip:
scripts/package-release.sh  # creates build/SpellCheck-macOS.zip
```

Then open `build/SpellCheck.app` (right-click → Open on first launch) or move
it to Applications. To produce a signed build for distribution:

```sh
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" scripts/package-release.sh
```

## Troubleshooting

### "the app won't open"

Releases are bundle-verified in CI (`scripts/verify-bundle.sh`), so a missing
framework can no longer ship silently. If the app still won't start:

1. Make sure you downloaded the **latest** release and deleted any older
   `SpellCheck.app` / zip from Downloads.
2. Gatekeeper: right-click the app → **Open** → **Open** (or run
   `xattr -dr com.apple.quarantine ~/Applications/SpellCheck.app` in Terminal).
   This is needed once per download until the app is notarized.
3. Run the binary directly in Terminal to see the real error:
   ```sh
   /Applications/SpellCheck.app/Contents/MacOS/SpellCheck
   ```

### macOS keeps asking for Accessibility permission

Bundles are always code-signed as a whole (Info.plist bound into the
signature). Without a Developer ID certificate the build is **ad-hoc signed
without the hardened runtime** — hardened runtime + ad-hoc would turn on
library validation and make macOS abort the launch with
`dyld: ... different Team IDs` (embedded frameworks like Sparkle ship
pre-signed by their own team). CI rejects that combination and smoke-launches
the packaged app from the shipped zip on every build, so a launch-breaking
release can no longer slip through. Ad-hoc signing still yields a *new*
identity on every build — after installing a new build, remove and re-add
SpellCheck under System Settings → Privacy & Security → Accessibility.
The permanent fix is a Developer ID Application certificate (Apple Developer
Program membership required): set it as the `SIGNING_IDENTITY` secret and the
identity stays stable across updates.

## Requirements

- macOS 13 (Ventura) or later
- Swift 6 toolchain (Xcode 16+) — only needed to build from source
- Accessibility permission (System Settings → Privacy & Security →
  Accessibility) — SpellCheck prompts for it on first use
- An API key for an OpenAI-compatible provider (e.g. [console.mistral.ai](https://console.mistral.ai/api-keys/))

## Project layout

| Path      | Contents                                                        |
|-----------|-----------------------------------------------------------------|
| `Core/`   | Platform-independent logic: prompt model, provider presets, sentence extraction, prompt building, settings model + v1→v2 migration, hot-key model. Fully unit tested on any OS. |
| `Engine/` | Platform-independent orchestration: grabbing text, running the API backend, settings persistence. Fully unit tested on any OS. |
| `App/`    | The macOS menu-bar app (AppKit/SwiftUI): status bar, Carbon hot key, Accessibility text source with fallbacks, prompt picker, Prompt Editor, Settings. Build only on macOS. |
| `scripts/`| Helper scripts: `test-core.sh`, `test-engine.sh`, `test-app.sh`, `build-app.sh` (assembles + signs `SpellCheck.app`), `package-release.sh`, `make-appcast.sh`, `verify-bundle.sh` (bundle + signature checks). |

## Auto-update setup (for maintainers)

The app ships with Sparkle wired up, but the updater stays **disabled** until
two things are in place:

1. **A Sparkle signing key pair** (updates are verified, so releases must be
   signed):
   - On a Mac, download a Sparkle release and run `bin/generate_keys`
     (or `swift run sign_update --generate-keys` from a Sparkle checkout).
   - Put the **public** key into `App/Info.plist` → `SUPublicEDKey`
     (currently absent on purpose — do not invent one).
   - Add the **private** key as the GitHub repo secret `SPARKLE_PRIVATE_KEY`.
     The release workflow extracts the `sparkle:edSignature` value from
     `sign_update` output and embeds it in `appcast.xml`.
2. **A feed the app can read without private credentials.** This repository
   is private, so `raw.githubusercontent.com` and GitHub release asset URLs
   are not reachable by Sparkle. Options:
   - Publish `appcast.xml` + release zips to a public host (a public
     "releases" repo served via GitHub Pages, or object storage such as
     S3/R2), and point `SUFeedURL` in `App/Info.plist` at it; or
   - make this repository public (only with the owner's permission).
   Embedding a GitHub token in the app is **not** an option — it would expose
   private credentials in every installed copy.
3. For reliable update installs, also set the `SIGNING_IDENTITY` secret
   (Developer ID Application) and, to remove Gatekeeper warnings, the
   notarization secrets `NOTARY_API_KEY` (base64 .p8), `NOTARY_API_KEY_ID`,
   `NOTARY_ISSUER_ID`.

Because the currently installed versions have no working updater, the first
properly signed build must be **installed manually** once; after that Sparkle
can offer subsequent updates.

## Using an API provider (e.g. Mistral)

1. Open SpellCheck → **Settings…** (menu-bar icon).
2. Click the **Mistral** provider preset — it fills in `https://api.mistral.ai/v1`
   and the cheap, fast `mistral-small-latest` model (base URL and model are
   always set together).
3. Paste your API key from [console.mistral.ai](https://console.mistral.ai/api-keys/).
4. Click **Fetch models** — the dropdown is filled from Mistral's `/v1/models`
   endpoint. Fetch failures are shown inline; note that a successful fetch
   only proves the model list endpoint works, not the whole edit workflow.
5. Click **Save** (or press ⌘S) — a "Saved" indicator appears once the
   settings are safely on disk.

Other presets: OpenAI, DeepSeek, OpenRouter, Ollama (local, no key needed —
models are fetched from `http://localhost:11434/v1`). You can always type a
custom base URL and model name manually.

## Testing

```sh
scripts/test-core.sh          # Core unit tests (any OS)
scripts/test-engine.sh        # Engine unit tests (any OS)
scripts/test-app.sh           # App tests (macOS)
scripts/build-app.sh release && scripts/verify-bundle.sh build/SpellCheck.app
```

CI runs Core + Engine tests on Linux and macOS, and builds + tests the app
and verifies (and now also checks the signature of) the packaged bundle on
macOS 15.

## Usage

1. Launch SpellCheck. A keyboard icon appears in the menu bar.
2. Grant Accessibility permission when asked.
3. In any app (Notion, TextEdit, Mail, …), select text — or click inside a
   sentence.
4. Press **⌥L**. The prompt picker opens over the app.
5. Search (optional), pick a prompt with ↑/↓ + Enter or by clicking it.
6. The chosen prompt runs through your API and the result replaces the
   selected text directly in the original app. Errors (no text, API failure,
   lost target app) appear as alert windows.

## Privacy

Text you run a prompt on is sent to the configured API provider. The API key
is stored in the app's Application Support directory and is never sent
anywhere except to your chosen provider.
