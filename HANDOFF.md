# SpellCheck — Project Handoff

Last updated: 2026-11-06, after the **v0.2.9** session (post-paste
verification REMOVED by explicit user decision — paste-only write-back;
follows v0.2.8: cursor spinner, identical-result write-back, own windows
lowered for the whole run; v0.2.7: intermittent picker/hotkey/focus fixes,
backup-model Fetch-models UI, Mistral prompt cache key).
Repo:
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

**SpellCheck** is a macOS menu-bar app for AI text editing (workflow
inspired by similar menu-bar text tools): a
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

Owner/user notes: uses the **Mistral API**
(`mistral-small-latest`, cheap+fast). Preferred icon: **Ω + checkmark**.
Existing v1 settings are migrated (⌥⌘K → ⌥L, `customPrompts` → `prompts`,
default prompt list seeded once) without losing anything else.

## 2. Architecture

Three SwiftPM packages (`// swift-tools-version:6.0`, `platforms: [.macOS(.v13)]`):

| Package | Target | Role | Tests |
|---|---|---|---|
| `Core/` | `SpellCheckCore` (lib) | Platform-independent: `TextScope`/`TextScopeExtractor` (unchanged), `HotKey` (default **⌥L**; any shortcut with ≥1 modifier is registerable — the Cmd/Ctrl requirement is gone), `PromptBuilder` (`messages(prompt:sharedPrompt:text:)`: system = fixed framing + shared prompt + selected prompt + output rules; user = marked text; `ChatCompletion.Response` content decodes leniently — plain string, part arrays, or null), `Settings` (Codable; v1→v2 migration in `init(from:)` + `migrated()`: legacy `customPrompts` → `prompts`, ⌥⌘K → ⌥L, one-time seeding of `Prompt.defaultPrompts`; NEW keys `sharedPrompt` — seeded once with the editable `Settings.defaultSharedPrompt` when absent — and `backupModel`, default empty), `Prompt`/`PromptIcon` (editable prompt model + glyphs), `APIProvider` presets (baseURL+model always paired), `CorrectionBackend` protocol (`correct(text:prompt:sharedPrompt:)`) + `CorrectionError` (`.http(status:message:)`, `.unusableResponse`, `isRetryableWithBackup`) + `FallbackPolicy` + `ResponseCleaner`. The rule-based offline corrector, `BuiltinAction`, `BackendKind` and `showConfirmation` were **removed** (v2: API-only, no confirmation) | 68 tests, Linux-runnable |
| `Engine/` | `SpellCheckEngine` (lib) | `CorrectionEngine` actor (grab→backend→replace — **no confirm step**; `run(prompt:)` grabs itself, `run(prompt:on:)` uses text captured earlier by the picker; `GrabbedText.replace` now **throws** with typed errors incl. `targetUnavailable(appName)`; replacement failures emit `EngineEvent.replaceFailed` — menu-bar only, NO alert popup; `sharedPrompt` passed through to the backend), `TextSource` protocol, `OpenAICompatibleBackend` (chat completions, 120 s timeout, lenient content decoding, sanitized short error bodies — never the full response), `FallbackBackend` (ONE retry on the backup model for retryable errors: 408/429/5xx, timeouts, empty/unusable response; combined error naming both models; never retries a paste), `SettingsStore` actor (JSON in Application Support/SpellCheck/settings.json), `APIEndpoint` (now requires http(s)), `ModelCatalog` (`GET /models` + `parseModelIDs`) | 43 tests, Linux-runnable |
| `App/` | `SpellCheck` (executable) + `SpellCheckTests` | macOS-only: `SpellCheckApp` (@main + AppDelegate: hot key → grab immediately → show picker → run chosen prompt on the pre-grabbed text; `saveSettings` persists then applies; SMAppService launch-at-login; `ErrorPresenter` shows real alerts for every failure — hot-key registration, accessibility, API, replacement), `HotKeyMonitor` (Carbon `RegisterEventHotKey`; `start()` returns a failure reason instead of failing silently; needs **no** Input Monitoring), `AccessibilityTextSource` (layered grab: `kAXSelectedTextAttribute` on focused element → descendant BFS → `kAXValue`+`kAXSelectedTextRange` → clipboard ⌘C fallback; replacement: re-activate captured app by pid, AX write with readback verification, clipboard-paste fallback with pasteboard save/restore), `PromptPickerWindowController` (FixKey-style dark non-activating panel: search field, ↑/↓/Enter/Esc, click-to-run, empty state), `PromptEditorWindowController` + SwiftUI (two-pane dark editor, CRUD, ⌘S), `SettingsView` (API-only, presets, fetch models, ⌘S + Saved indicator), `StatusBarController` (menu: Open Prompt Picker, Prompt Editor…, Settings…, Check for Updates…, Quit), `UpdaterController` (Sparkle; active only with `SUPublicEDKey`) | CI on macos-15 |

Local path dependencies are referenced by **directory name**: `package: "Core"`, `package: "Engine"`.

Data flow: ⌥L → `AccessibilityTextSource.grab()` (captures selection **and**
target app pid) → prompt picker → `engine.run(prompt:on:grabbed)` →
`OpenAICompatibleBackend` → `grabbed.replace(result)` (re-activates the
original app, verifies the write) → status event (+ alert on failure).

## 3. Current state

- **v0.2.9 changes (this session, user decision):**
  1. **Post-paste verification removed**: `AccessibilityTextSource.replace`
  now pastes once and returns — no ~300 ms settle, no document read-back
  loop, no `verify`/`expectedDocument`. Rationale (user's words): he sees the
  result on screen; verification only added ~0.5–1 s latency and
  notifications he never wanted. Success now means "the paste was issued
  over the validated selection", NOT "the document was verified". The
  PRE-paste safety checks remain (reactivate target, selection-intact check,
  stale-document guard) — they prevent writing into the wrong place.
  `TextSourceError.unverified` stays in the Engine API (sources may still
  throw it) but SpellCheck's own source no longer produces it. Issue #16
  (Fast/Thorough toggle) closed as resolved by this decision.
  2. **Replacement-failure messages removed entirely (v0.2.10, user
  decision)**: `StatusBarController.handle` is now a visual no-op — the old
  ⏳/✓/✗ title/tooltip logic was DEAD CODE in the packaged app anyway (the
  installed template image always replaced the title), and the user wanted
  no replacement messaging at all. The cursor spinner is the sole working
  indicator; real API/config/permission errors still alert via
  ErrorPresenter. NOTE: the v0.2.9 Release run failed only at the final
  "commit appcast to main" step (push race with the v0.2.10 commit) — v0.2.9
  was never published as a GitHub release; v0.2.10 supersedes it and its
  appcast entry.
- **v0.2.8 changes:**
  1. **Cursor spinner (user request)**: `WorkingIndicatorController` — a
     small dark non-activating panel with an `NSProgressIndicator` shown near
     the mouse pointer on `EngineEvent.working` and hidden on terminal events.
     `ignoresMouseEvents`, never key, no app activation. Wired in
     `AppDelegate.handle`; a `.busy` rejection leaves it up (the original run
     is still in flight).
  2. **Identical-result write-back (user request)**: the engine no longer
     skips `replace` when the corrected text equals the original — the visible
     replacement is the user's confirmation that the workflow ran. The AX
     `verify` treats an unchanged document as the expected outcome for an
     identical write-back (document snapshot == desired state ⇒ success).
  3. **Own windows lowered for the whole run (issue #12 remainder)**:
     `finishPickerSession(startedRun:)` keeps the level-lowering active until
     the run's terminal event (`succeeded`/`failed`/`replaceFailed`) instead
     of restoring at picker close; `.busy` is not terminal. Restoring earlier
     let our windows jump forward while SpellCheck was still active mid-run.
- **v0.2.7 changes:**
  1. **Intermittent ⌥L/menu/picker (issue #4)** — three root-cause findings:
     (a) `openPromptPicker` gated the picker on `engine.isBusy` and silently
     returned while a (up to 120 s) request was in flight → "nothing happens",
     later "sudden" correction when the old request finished; (b) the busy
     check + async grab allowed two rapid activations to both pass the guard
     and open two overlapping pickers (one leaked with its mouse monitors
     installed); (c) unbounded AX messaging could stall the grab for many
     seconds in slow apps. Fixes: a synchronous `pickerSessionActive` flag
     (set before the async work, cleared in one `finishPickerSession()` used by
     every path), the picker now opens even while the engine is busy, and a
     rejected second run emits a new `EngineEvent.busy` (menu-bar tooltip
     only — no popup, no duplicate request/paste). AX calls get a 0.75 s
     messaging timeout and the whole grab a 3 s deadline (`findEditorElement`
     checks the deadline each step).
  2. **Stale/delayed operations**: `CapturedTarget` now also snapshots the
     element's `kAXValue` at grab time (`documentValue`); `ensureSelectionIntact`
     aborts with `selectionChanged` if the document changed since the grab —
     a late response can no longer paste into a document the user has edited
     in the meantime. Normal refocus/reactivate for the requested workflow is
     unchanged; the single-attempt paste and existing selection checks remain.
  3. **Backup model selector (issue #10 UI request)**: new reusable
     `ModelPickerField` in Settings — the backup model gets the same Fetch
     models picker as the primary (own fetch state, manual entry kept, fetched
     list resets on base-URL change via view `.id`). Fetching never overwrites
     the saved backup model; the primary keeps its existing auto-select-first
     behavior. Fallback behavior unchanged.
  4. **Mistral prompt caching**: `PromptCacheKey` (Core) = FNV-1a 64-bit hex of
     trimmed shared+selected prompt, prefixed `spellcheck-` — stable per
     identical prefix, contains no content/secrets. `OpenAICompatibleBackend`
     sends it as `prompt_cache_key` ONLY for `*.mistral.ai` base URLs (other
     providers get a byte-identical body as before — tested).
     `ChatCompletion.Response` now decodes `usage.prompt_tokens_details.cached_tokens`
     (not surfaced in UI; for verification only). Real cache hits are NOT
     verified — no authorized live API test was run; user should check
     Mistral Admin → Usage. Docs: 64-token cache blocks, <64-token prompts
     never hit, cached tokens billed at 10%, key raises but does not
     guarantee hit rates.
  5. **Diagnostics**: `AccessibilityTextSource` logs non-sensitive markers via
     `os.Logger` (grab duration, capture layer, abort reasons). Never logs
     API keys, prompts, selected text or responses.
  6. Fixed a latent test bug: `await task` on a `Task` value is a no-op —
     `await task.value` is required (new busy-rejection test).
- **v0.2.6 changes:**
  1. **Shared prompt (issue #9)**: `Settings.sharedPrompt`, its own Settings
     section (TextEditor), sent in every request BEFORE the selected prompt
     (system message = framing + shared + instruction + output rules; user
     message = marked text). Default asks for result-only, original language,
     no unsolicited quotes/Markdown/fences; explicitly requested formats
     (bullets, Markdown, translation) still work. Seeded once for existing
     settings files (decodeIfPresent fallback); user edits always win.
  2. **Backup model + fallback (issue #10)**: `Settings.backupModel`, wired
     via `FallbackBackend` in `AppDelegate.makeBackend`. One retry on the
     backup for 408/429/5xx, URLError timeouts/connection loss, empty or
     unusable responses. Auth/config errors (401/400/notConfigured) do NOT
     fall back. Both-fail error names both models. Paste is never retried.
  3. **GLM-style parsing (issue #11)**: response `content` now decodes as a
     plain string, an OpenAI-style parts array, or null; HTTP error bodies are
     summarized short+sanitized (message + code only, 200-char cap — no
     full-response leakage). Undecodable 2xx payloads throw
     `CorrectionError.unusableResponse` with an actionable message instead of
     a raw "data couldn't be read" decoding error. Actual GLM 5.3 Flash
     compatibility is NOT verified against the provider — no model ID was
     invented; the user must test.
  4. **Outside-click dismissal (issue #15)**: global+local NSEvent mouse
     monitors while the picker is shown; a click outside closes it via
     `onDismiss` (NOT `onCancel` — no refocus of the target app, the click
     itself moves focus; nothing is edited). Monitors removed on close.
  5. **No replacement-failure popup (issues #5/#4)**: replacement errors
     (replaceFailed/selectionChanged/unverified/targetUnavailable) emit
     `EngineEvent.replaceFailed` — tooltip/status only. Real API/config/
     permission errors still alert via `.failed`.
  6. **Icons (issue #7)**: `omega` style now uses the SAME fitted full-size Ω
     as `omega-check` (it previously rendered the raw unfitted path, ~30%
     smaller). Previews committed in `docs/icon-previews/` (18pt@2x real
     menu-bar pixels + 144px enlargements) — real-Mac visual approval is the
     user's decision.
  7. **Loading window / Space switch (issue #12)**: the SwiftUI
     `SettingsWindowGroup` (whose "Loading…" placeholder window macOS state
     restoration could raise when the app activated) is GONE — the app's only
     scene is a never-opened `Settings { EmptyView }`; all real windows are
     manually managed NSWindowControllers.
  8. **Open windows raised by ⌥L (issue #12, low priority, done last)**: while
     the picker session is up, other SpellCheck windows get
     `level = -1` (below other apps' normal windows) and are restored to
     `.normal` when the session ends. Keyboard focus is untouched.
  9. **Release notes (issue #14)**: `release.yml` now REQUIRES
     `scripts/release-notes/vX.Y.Z.md` and publishes it as the release body
     (no more Full-Changelog-only pages).
- Latest release: **v0.2.6** (universal, ad-hoc signed, Sparkle-signed update; CI + Release workflows green; release notes from `scripts/release-notes/v0.2.6.md`). Previous: **v0.2.5** (universal, ad-hoc signed, Sparkle-signed
  update; contains everything from v0.2.4, which was never published
  separately). v0.2.4 = strip model-echoed <<< / >>> markers in
  ResponseCleaner (Notion pasted them as extra text / quote blocks; 6 new
  tests, legitimate angle brackets untouched; system prompt forbids the
  markers) + larger checkmark in the Ω+✓ icon. v0.2.5 = drag-and-drop
  prompt reordering in the Prompt Editor sidebar (persists immediately on
  drop, purely structural; disabled while a search filter is active), same
  order in the picker, first prompt highlighted on open, ⌥L still only
  opens the picker. `Prompt` is now Hashable.
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
  5. **Prompt reordering (v0.2.5)**: the Prompt Editor sidebar supports
     drag-and-drop reordering (bound `ForEach` + `onMove`; disabled while a
     search filter is active). The drop persists immediately via the normal
     save path — purely structural, no prompt data is touched. The picker
     uses the same persisted order and highlights the first prompt on open;
     ⌥L still only OPENS the picker. Tests: Core order round-trip +
     migration, Engine order survives a store reopen, App reorder-is-
     structural + persists + picker-opens-on-first.
- The repo is now **public** and Sparkle is **live end-to-end**: the user
  generated an EdDSA key pair, the public key is embedded as `SUPublicEDKey`
  in `App/Info.plist`, the private key is the repo secret
  `SPARKLE_PRIVATE_KEY`, and every release zip is signed (`sparkle:edSignature`
  in `appcast.xml`). Apps ≥ v0.2.1 should self-update via "Check for Updates…"
  — the user should confirm this works when v0.2.2+ ships.
- The user's v1 settings migrated in place (API key kept, ⌥⌘K → ⌥L, legacy
  customPrompts → prompts, defaults seeded once).
- Tests: Core 76/76, Engine 49/49 (Linux, this session); App sources parse-checked on Linux (`swiftc -parse`), real App compile + tests on macos-15 CI. macOS CI + Release green for
  v0.2.5 (the shipped zip was extracted, re-verified and smoke-launched).
  NOTE 05-06.11.2026: GitHub's macOS runner pool was congested for hours
  ("job was not acquired by Runner") — several v0.2.4/v0.2.5 release
  attempts died that way before one got a runner; re-pushing the tag is the
  only retry lever (the agent token cannot rerun runs). New App tests
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

**NEXT VERSION: v1.0.0** (direct user instruction, 06.11.2026): the next
release after v0.2.10 must be tagged `v1.0.0` — not v0.2.11. All release
notes, appcast and notes files follow the tag as usual.

**v1.0.0 planned content — updated default prompts (user instruction,
06.11.2026)**: the user's new default prompt list is PREPARED on the draft
branch **`vibe/v1-default-prompts`** (head b239139) — do NOT ship v1.0.0
without merging it. The draft: 19 prompts from the user's saved list;
Allvit, Napoloen-as-named and Juss dropped (Juss is Norway-specific);
Napoloen's text lives on as **Humanize** (Norwegian sections removed);
translation prompts trimmed to English, Esperanto and Norwegian (Bokmål +
Nynorsk) only, at the bottom of the list; every
Norwegian-language section removed from prompt bodies (only the
language names Bokmål/Nynorsk remain, in the two Norwegian translation
prompts the user dictated verbatim); Make Shorter's "REFERENCES" typos
fixed. **Migration (user's revised decision)**: on app update, existing
installs IMPORT default prompts whose titles they are missing — appended
AFTER the user's own prompts, never replacing, reordering or duplicating
them (match by exact title; a user-edited "Fix Grammar" keeps its text).
Guarded by a new persisted `importedDefaultPromptsVersion` + code constant
`Settings.defaultPromptsVersion` (= 1 for the v1.0.0 list): the import runs
ONCE per defaults version, so a user who later deletes an imported default
does not get it back on the next launch. Tests: Core 79/79 (import-by-title,
same-title never replaced, once-per-version, deletion stays deleted),
Engine 49/49, App parse-checked on the branch. **Autosave (user request,
same draft)**: Settings and Prompt Editor now persist EVERY change —
debounced 0.5 s after the last edit (title, text, icon, add, delete,
drag-to-reorder, any setting). ⌘S and the Save button still save
immediately, and the Saved indicator still confirms. `applySettings` now
only re-registers the hotkey / recreates the engine when the relevant
settings actually changed (autosave fires often; recreating the engine per
keystroke would drop a running correction's busy flag). **Circular
progress ring (user request, same draft)**: the v0.2.8 NSProgressIndicator
spinner is replaced by `CircularProgressView` — a ring (faint track +
bright arc) that fills from the top clockwise over the ESTIMATED response
time; when exceeded it wraps and refills repeatedly until the correction
completes; without an estimate one revolution takes 1 s. No dark square
background anymore — just the ring near the cursor. Estimates come from
`ResponseTimeEstimator` (Engine): per-model samples of (input length,
observed seconds) from a new `EngineEvent.requestTiming(model:seconds:
inputLength:)` emitted after each successful request; estimate = inter-quartile
mean (IQM) of seconds-per-char rates × current length, clamped to [0.5, 120] s; max 20
samples/model; a model with no samples falls back to the rate learned
across ALL models (user spec), so only a completely empty store uses the
1 s/revolution default; persisted to Application Support/SpellCheck/response-times.json
(numbers only — no text/prompts/keys). `CorrectionBackend.modelKey`
added (default = displayName; OpenAICompatibleBackend = model;
FallbackBackend = primary's). Tests: Engine 57/57 (estimator math incl. IQM trimming,
outlier-median, persistence, per-model, timing event), Core 79/79, App parse
+ ring show/hide tests. The app was NOT
updated/released with any of this yet (explicit user instruction —
merge + release as v1.0.0 when the user says go).

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

**v0.2.7 intermittent-behavior investigation (issue #4)**: the three code
weaknesses above fit the user's symptoms (silent busy-drop ≈ "nothing
happens" + "suddenly corrected later"; overlapping picker sessions; slow AX
grab ≈ "picker opens late/never"; late replacement reactivating the target ≈
"taken back to the text while typing in Notion chat"). They are FIXED in code
and covered by automated tests, but NONE of this is confirmed on the user's
Mac — issue #4 stays open until he re-tests repeatedly (also after toggling
permissions). The Loading-window/Space-switch report (issue #12) is considered
solved by the user; the open-windows-raised-by-⌥L part remains low priority.

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
- **ALL GitHub content must be in English** — issues, PRs, release notes,
  docs, commit messages. Nothing on GitHub may ever be in Norwegian.
  (Direct user instruction, 06.11.2026; all release notes v0.2.6–v0.2.10
  were translated to English retroactively.)
- Never claim the app is tested on the user's behalf; his verdict on the real
  Mac is ground truth over any green suite.
