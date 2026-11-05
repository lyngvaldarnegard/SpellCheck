# SpellCheck — Project Handoff

Last updated: 2026-11-05, after the **v0.2.3 fixes** (picker keyboard focus,
clipboard-based replacement with honest verification, prompt-persistence
hardening, vector menu-bar icons). Repo:
https://github.com/lyngvaldarnegard/SpellCheck (default branch `main`,
**not protected** on purpose).

**v0.2.2 user verdict (real Mac, ground truth over any green suite):** the
picker appeared but **Enter reached the original text field** (replaced the
selection with a line break — destructive). Clicking a prompt in **TextEdit**
changed the text (removed the first part of a sentence, corrected the second)
yet showed "Could not replace the text in the original app". Saved prompts
were **lost across the update** (API key survived). The menu-bar icon looked
**low-resolution**. All four are tracked in GitHub issues; do NOT close them
until the user confirms the fixes on his Mac.

## 1. What this project is

**SpellCheck** is a clone of the macOS menu-bar app **FixKey** (fixkey.ai): a
global hot key (default **⌥L**) opens a prompt picker over the current
selection — or the sentence around the caret — in ANY app via the
Accessibility API. The chosen prompt is sent to any OpenAI-compatible chat
API and the result **directly replaces** the original text (no
review/confirmation window — that feature was removed on purpose). Prompts
are fully editable in a separate FixKey-style Prompt Editor; Settings holds
API configuration, shortcut and behaviour. Supports a model picker that
fetches `GET {base}/models`, a menu-bar icon picker, launch-at-login
(SMAppService) and Sparkle-based auto-update (still gated on a Sparkle key
pair + a public feed, see §6).

Owner/user notes: speaks Norwegian; uses the **Mistral API**
(`mistral-small-latest`, cheap+fast). Preferred icon: **Ω + checkmark**.
Existing v1 settings are migrated (⌥⌘K → ⌥L, `customPrompts` → `prompts`,
default prompt list seeded once) without losing anything else.

## 2. Architecture

Three SwiftPM packages (`// swift-tools-version:6.0`, `platforms: [.macOS(.v13)]`):

| Package | Target | Role | Tests |
|---|---|---|---|
| `Core/` | `SpellCheckCore` (lib) | Platform-independent: `TextScope`/`TextScopeExtractor` (unchanged), `HotKey` (default **⌥L**; any shortcut with ≥1 modifier is registerable — the Cmd/Ctrl requirement is gone), `PromptBuilder` (prompt-only: `messages(prompt:text:)`), `Settings` (Codable; v1→v2 migration in `init(from:)` + `migrated()`: legacy `customPrompts` → `prompts`, ⌥⌘K → ⌥L, one-time seeding of `Prompt.defaultPrompts`), `Prompt`/`PromptIcon` (editable prompt model + glyphs), `APIProvider` presets (baseURL+model always paired), `CorrectionBackend` protocol + `ResponseCleaner`. The rule-based offline corrector, `BuiltinAction`, `BackendKind` and `showConfirmation` were **removed** (v2: API-only, no confirmation) | 48 tests, Linux-runnable |
| `Engine/` | `SpellCheckEngine` (lib) | `CorrectionEngine` actor (grab→backend→replace — **no confirm step**; `run(prompt:)` grabs itself, `run(prompt:on:)` uses text captured earlier by the picker; `GrabbedText.replace` now **throws** with typed errors incl. `targetUnavailable(appName)`), `TextSource` protocol, `OpenAICompatibleBackend` (chat completions, 120 s timeout), `SettingsStore` actor (JSON in Application Support/SpellCheck/settings.json), `APIEndpoint` (now requires http(s)), `ModelCatalog` (`GET /models` + `parseModelIDs`) | 27 tests, Linux-runnable |
| `App/` | `SpellCheck` (executable) + `SpellCheckTests` | macOS-only: `SpellCheckApp` (@main + AppDelegate: hot key → grab immediately → show picker → run chosen prompt on the pre-grabbed text; `saveSettings` persists then applies; SMAppService launch-at-login; `ErrorPresenter` shows real alerts for every failure — hot-key registration, accessibility, API, replacement), `HotKeyMonitor` (Carbon `RegisterEventHotKey`; `start()` returns a failure reason instead of failing silently; needs **no** Input Monitoring), `AccessibilityTextSource` (layered grab: `kAXSelectedTextAttribute` on focused element → descendant BFS → `kAXValue`+`kAXSelectedTextRange` → clipboard ⌘C fallback; replacement: re-activate captured app by pid, AX write with readback verification, clipboard-paste fallback with pasteboard save/restore), `PromptPickerWindowController` (FixKey-style dark non-activating panel: search field, ↑/↓/Enter/Esc, click-to-run, empty state), `PromptEditorWindowController` + SwiftUI (two-pane dark editor, CRUD, ⌘S), `SettingsView` (API-only, presets, fetch models, ⌘S + Saved indicator), `StatusBarController` (menu: Open Prompt Picker, Prompt Editor…, Settings…, Check for Updates…, Quit), `UpdaterController` (Sparkle; active only with `SUPublicEDKey`) | CI on macos-15 |

Local path dependencies are referenced by **directory name**: `package: "Core"`, `package: "Engine"`.

Data flow: ⌥L → `AccessibilityTextSource.grab()` (captures selection **and**
target app pid) → prompt picker → `engine.run(prompt:on:grabbed)` →
`OpenAICompatibleBackend` → `grabbed.replace(result)` (re-activates the
original app, verifies the write) → status event (+ alert on failure).

## 3. Current state

- Latest release: **v0.2.3** (universal, ad-hoc signed, Sparkle-signed update).
  Release history: v0.2.0 (BROKEN — ad-hoc + hardened runtime dyld abort) →
  v0.2.1 (launch fixed) → v0.2.2 (picker X button + field-editor delegate —
  **did NOT fix Enter reaching the original app**) → v0.2.3.
- **v0.2.3 changes (this session):**
  1. **Picker keyboard focus**: root cause of the v0.2.2 Enter bug — the
     borderless panel never became the KEY window (borderless NSPanels refuse
     key status), and SpellCheck never ACTIVATED itself, so keyboard input
     went to the frontmost app. Fix: `PickerPanel` (NSPanel subclass,
     `canBecomeKey == true`), `NSApp.activate(ignoringOtherApps: true)` +
     `makeKeyAndOrderFront` + `makeFirstResponder(searchField)` in `show()`
     (re-asserted next runloop tick), `hidesOnDeactivate = false`,
     `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`.
     Target app/text/selection are captured BEFORE the picker opens, so the
     focus change cannot lose them; Escape/X now returns focus to the
     original app via `GrabbedText.refocus`.
  2. **Replacement**: rewritten FixKey-style. AX is used to CAPTURE and
     VERIFY; the write itself is a clipboard paste (⌘V posted once) —
     undoable, works in Notion/Electron. Before pasting: re-activate target,
     verify the selection is still the captured one (read selected text /
     range, re-select captured range if needed, else focused-element check)
     — aborts with `selectionChanged` otherwise. After pasting: document
     readback; exact match = success, unchanged = replaceFailed ("nothing
     was changed"), other = `unverified` ("pasted but could not verify —
     check the text; corrected text is on the clipboard"). **A paste is issued
     at most once; a failed verification NEVER retries.** The corrected text
     intentionally STAYS on the clipboard (user preference; old
     save/restore-on-success behavior removed). The clipboard is only
     restored when the paste could not be issued at all.
  3. **Prompt persistence**: prompts decode lossily (one malformed entry
     can't wipe the list; missing keys fall back instead of failing);
     `Prompt.init(from:)` is lenient; SettingsStore backs up an undecodable
     settings.json to `settings.corrupt-<ts>.json` instead of silently
     defaulting; the Settings window never saves a stale prompt snapshot (it
     always keeps the live list) and both Settings and Prompt Editor rebuild
     their hosted views on open so they always show current data.
  4. **Icons**: `scripts/make-icons.mjs` now emits true vector template PDFs
     (18pt, `MenuBarIcons/<style>.pdf`) + SVG sources (`MenuBarIcons/svg/`)
     + PNG fallbacks. Root cause of the blur: `NSImage(contentsOfFile:)`
     loaded the 22px PNG and never picked the @2x variant. Ω+checkmark
     redesigned: Ω at full size, smaller check knocked out of the Ω's
     lower-right (transparent gap via reversed enlarged contour under
     nonzero winding). `MenuBarIconStyle.templateImage` prefers the PDF.
     **Visual check: only rendered previews were inspected programmatically
     (ASCII/pixel diff) — NOT verified on a real Mac screen.**
- The repo is now **public** and Sparkle is **live end-to-end**: the user
  generated an EdDSA key pair, the public key is embedded as `SUPublicEDKey`
  in `App/Info.plist`, the private key is the repo secret
  `SPARKLE_PRIVATE_KEY`, and every release zip is signed (`sparkle:edSignature`
  in `appcast.xml`). Apps ≥ v0.2.1 should self-update via "Check for Updates…"
  — the user should confirm this works when v0.2.2+ ships.
- The user's v1 settings migrated in place (API key kept, ⌥⌘K → ⌥L, legacy
  customPrompts → prompts, defaults seeded once).
- Tests: Core 51/51, Engine 32/32 (Linux, this session). New App tests
  (macos-15 CI): picker key-window status, first responder, Enter via
  `panel.sendEvent`, Escape cancel, arrow/search behavior, icon template
  assets. CI also builds + verifies the bundle + smoke-launches the app.
- **Signing rules (hard-won, do not regress)**: ad-hoc builds must NOT use
  `--options runtime` — hardened runtime turns on library validation, which
  rejects Sparkle's Developer-ID-signed framework ("dyld: different Team
  IDs" launch abort). `build-app.sh` re-signs all embedded components
  innermost-first (XPC services → helper apps → helper binaries → framework
  → bundle) preserving entitlements; `verify-bundle.sh` fails ad-hoc+runtime
  builds and team mismatches; CI/release extract the SHIPPED zip, re-verify
  it, and smoke-launch the app for 8s. With a real Developer ID identity
  (`SIGNING_IDENTITY` secret) the hardened runtime is used again.

## 4. Build / test / release

macOS:
```sh
swift test --package-path Core && swift test --package-path Engine && swift test --package-path App
scripts/build-app.sh release                 # build/SpellCheck.app (universal, embeds frameworks, stamps VERSION, always signs)
scripts/verify-bundle.sh build/SpellCheck.app  # MUST pass: executable, rpath, @rpath deps, archs, resources, signature
scripts/package-release.sh                   # build/SpellCheck-macOS.zip (honors SIGNING_IDENTITY, VERSION)
```
Release: `git tag v0.2.0 main && git push origin v0.2.0` → `release.yml` runs
tests, packages, verifies bundle, optional notarize (secrets `NOTARY_API_KEY`,
`NOTARY_API_KEY_ID`, `NOTARY_ISSUER_ID`, `SIGNING_IDENTITY`), optional Sparkle
signing (secret `SPARKLE_PRIVATE_KEY` — the workflow now extracts ONLY the
`sparkle:edSignature` value from `sign_update` output instead of embedding the
whole XML-attribute line), regenerates `appcast.xml` (commits to main), creates
the GitHub Release. `actionlint .github/workflows/*.yml` must stay clean
(`secrets` context is not allowed in step `if:` — use `env.X != ''` guards).

Linux sandbox — Swift 6.2 Debian12 toolchain re-download per session (see git
history of this file for the recipe). Only Core+Engine compile/test on Linux;
App sources are checked with `swiftc -parse App/Sources/SpellCheck/*.swift`.

## 5. gh CLI / GitHub quirks (important)

- The agent's `gh` token **cannot mutate GitHub**: no PR merge, no
  workflow_dispatch, no secret set. It CAN read runs/releases and push refs.
- Repo Settings → Actions → Workflow permissions must be **Read and write**.
- Do NOT protect `main` (release workflow pushes appcast commits to it).
- Rate limit 429 → wait ~60 s, retry once, then stop.

## 6. Known issues / not-yet-done / user actions required

The four v0.2.2 problems are tracked in GitHub issues (keep them OPEN until
the user confirms on his Mac): #4 picker keyboard/focus, #5 capture/
replacement + misleading error, #6 prompt persistence, #7 icon resolution.
v0.2.3 is released (CI + Release workflows green; the shipped zip was
extracted, re-verified and smoke-launched by CI). No in-app update install
was observed — the user should run "Check for Updates…" from v0.2.2.
**v0.2.2 → v0.2.3 user verdict:** the workflow now works in Notion (third
attempt) — but earlier attempts pasted model-echoed `<<<`/`>>>` input
markers (extra text + Notion quote blocks). v0.2.4 strips exactly that echoed
framing in `ResponseCleaner` (legitimate angle brackets untouched; 6 new
tests) and forbids the markers in the system prompt; tracked in issue #8,
open until the user re-tests repeatedly in Notion. v0.2.4 also enlarges the
Ω+checkmark's checkmark for menu-bar legibility (issue #7).

1. **Real-Mac verification of the whole workflow (STILL THE TOP PRIORITY)**:
   the user has v0.2.2 installed; he must confirm select-text-in-**Notion**
   and **TextEdit** → ⌥L → picker (search, ↑/↓, Enter, click, X button, Esc)
   → result replaces the selection in the original app. CI proves launch +
   unit logic only; Notion (Electron) may rely on the clipboard fallback
   layer. His verdict is ground truth.
2. **Auto-update check**: with v0.2.1+ installed, "Check for Updates…" in the
   menu-bar menu should find v0.2.2+ — Sparkle setup is complete (public
   repo, SUPublicEDKey embedded, SPARKLE_PRIVATE_KEY secret, signed appcast);
   end-to-end update install not yet observed by anyone.
3. **Stable signing identity (optional, recommended)**: ad-hoc signing yields
   a new identity per build → Accessibility may need re-adding per update,
   and Gatekeeper needs right-click→Open (or `xattr -dr
   com.apple.quarantine`) per download. Permanent fix = Apple Developer
   Program ($99/yr) + `Developer ID Application` certificate as
   `SIGNING_IDENTITY` secret + notarization secrets (`NOTARY_API_KEY`
   base64 .p8, `NOTARY_API_KEY_ID`, `NOTARY_ISSUER_ID`) — workflow steps
   already exist.
4. FixKey feature parity still missing: voice dictation; polish.
5. `scripts/make-icons.mjs` glyph styles are hardcoded, but the SVG sources
   now live in `App/Resources/MenuBarIcons/svg/` and the script emits vector
   PDFs + PNGs from the same geometry.
6. GitHub macOS runners occasionally fail with "job was not acquired by
   Runner" (capacity) — that is infrastructure, not the code; re-push the tag
   to retry (the agent token cannot `gh run rerun`).

## 7. Key files

- `App/Info.plist` — `CFBundleExecutable=SpellCheck`, `NSPrincipalClass`,
  `LSUIElement`, `LSMinimumSystemVersion 13.0`, `CFBundleIconFile`,
  `NSAccessibilityUsageDescription`, `SUFeedURL` (raw.githubusercontent …
  main/appcast.xml — reachable now that the repo is public),
  `SUEnableAutomaticChecks`, `SUPublicEDKey` (the user's real Sparkle public
  key — never remove or change it, installed apps verify updates against it).
- `scripts/build-app.sh` — assembles the .app, embeds frameworks, rpath,
  stamps VERSION, iconutil → AppIcon.icns, **always code-signs** (identity or
  ad-hoc).
- `scripts/verify-bundle.sh` — fails CI/release if executable/rpath/@rpath
  deps/archs/resources missing or the bundle is unsigned.
- `scripts/package-release.sh`, `scripts/make-appcast.sh` (takes the raw
  EdDSA signature), `scripts/make-icons.mjs`, `scripts/test-{core,engine,app}.sh`.
- `.github/workflows/ci.yml` (Core+Engine tests ubuntu+macos, App
  build+test+package+verify on macos-15), `.github/workflows/release.yml`.
- `appcast.xml` — Sparkle feed, auto-updated on main by each release.
- `README.md` — features, install, troubleshooting (incl. Accessibility
  re-prompting), auto-update setup, Mistral setup, usage.

## 8. Working agreements with the user

- Full autonomy granted; push to `main` directly is accepted; releases via tags.
- Communication language: Norwegian (user writes Norwegian; agent replies in Norwegian).
- Never claim the app is tested on the user's behalf; his verdict on the real
  Mac is ground truth over any green suite.
