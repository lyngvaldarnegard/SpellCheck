# SpellCheck — Project Handoff

Last updated: 2026-11-05, after release **v0.1.4** (latest). Repo:
https://github.com/lyngvaldarnegard/SpellCheck (default branch `main`, **not protected** on purpose).

## 1. What this project is

**SpellCheck** is a clone of the macOS menu-bar app **FixKey** (fixkey.ai): a global
hot key (default **⌥⌘K**) grabs the selected text — or the sentence around the caret —
in ANY app via the Accessibility API, sends it to a correction backend (offline
rule-based, or any OpenAI-compatible chat API), shows a confirmation window, and
pastes the corrected text back over the original range. Supports built-in actions
(fix typos, professional, casual, summarize, expand, translate), custom prompts,
a model picker that fetches `GET {base}/models`, a menu-bar icon picker, and
Sparkle-based auto-update.

Owner/user notes: speaks Norwegian; uses the **Mistral API** (`mistral-small-latest`,
cheap+fast); wants the app downloadable as a release zip; plans to cancel FixKey
after testing SpellCheck. Preferred icon: **Ω + checkmark** (FixKey-style, Ω instead
of the letter A), selectable in Settings → Menu Bar Icon.

## 2. Architecture

Three SwiftPM packages (`// swift-tools-version:6.0`, `platforms: [.macOS(.v13)]`):

| Package | Target | Role | Tests |
|---|---|---|---|
| `Core/` | `SpellCheckCore` (lib) | Platform-independent: `TextScope`/`TextScopeExtractor` (UTF-16 caret offsets, sentence boundaries at `.?!….！？？`, abbreviations/decimals excluded, newlines always boundaries), `HotKey` (Carbon key codes, ⌥⌘K default, must contain Cmd/Ctrl), `PromptBuilder` (`<<<`/`>>>` markers, `BuiltinAction`), `RuleBasedCorrector` (misspellings, doubled words same-line only, missing space after punctuation, capitalization, tripled consonants), `CorrectionBackend` protocol + `ResponseCleaner`, `Settings` (Codable; custom `init(from:)` so old JSON without `menuBarIconStyle` still decodes) | 57 tests, Linux-runnable |
| `Engine/` | `SpellCheckEngine` (lib) | `CorrectionEngine` actor (grab→backend→confirm→replace, `EngineEvent` idle/working/succeeded/failed, `isBusy` guard), `TextSource` protocol + `GrabbedText{scope, replace}`, `RuleBasedBackend`, `OpenAICompatibleBackend` (chat completions), `SettingsStore` actor (JSON in Application Support/SpellCheck/settings.json), `APIEndpoint` (string-based URL normalization — URL mutation crashed swiftc 6.0.3), `ModelCatalog` (`GET /models` + `parseModelIDs`) | 29 tests, Linux-runnable |
| `App/` | `SpellCheck` (executable) + `SpellCheckTests` | macOS-only: `SpellCheckApp` (`@main` App + `@NSApplicationDelegateAdaptor`, `typealias AppSettings = SpellCheckCore.Settings` to avoid SwiftUI `Settings` clash, first-run notice opens Settings + alert), `HotKeyMonitor` (Carbon `RegisterEventHotKey`), `AccessibilityTextSource` (AX read `kAXValueAttribute`/`kAXSelectedTextRangeAttribute` CFRange UTF-16 / `kAXSelectedTextAttribute`; replace = select range + clipboard Cmd-V via CGEvent), `StatusBarController` (template image from `MenuBarIcons/<style>.png`, `isTemplate=true`, text-glyph fallback ⌨/⏳/✓/✗), `MenuBarIconStyle` (omega-check/omega/spellcheck/checkmark), `SettingsView` + `SettingsWindowController: NSWindowController` (provider presets — **Mistral first** — API key/base URL, Fetch models + dropdown, hotkey recorder, icon picker), `ConfirmationWindowController`, `UpdaterController` (Sparkle; auto-start only when `SUPublicEDKey` present, else friendly alert) | CI on macos-15 |

Local path dependencies are referenced by **directory name**: `package: "Core"`, `package: "Engine"`.

Data flow: hot key → `engine.run(action:)` → `source.grab()` → backend → optional
confirmation → `GrabbedText.replace` → status icon event.

## 3. Current state

- **Latest release: v0.1.4** (https://github.com/lyngvaldarnegard/SpellCheck/releases/tag/v0.1.4),
  CI + Release green. Releases: v0.1.0 (broken: no `CFBundleExecutable`, arm64-only),
  v0.1.1 (launch fixed, universal binary), v0.1.2 (checkmark icon), v0.1.3 (Ω✓ icon +
  icon picker), **v0.1.4 (embeds `Sparkle.framework` + rpath — fixes instant dyld
  launch crash; version-stamped Info.plist; bundle verification in CI/release)**.
- Each release publishes `SpellCheck-macOS.zip` + `appcast.xml`; the release workflow
  also commits the updated `appcast.xml` to `main` (that's why `main` must stay
  unprotected and Actions need **Read and write** permissions — already set).
- v0.1.4 artifact verified externally (Mach-O parse): `Contents/Frameworks/Sparkle.framework`
  present, both arch slices' `@rpath/Sparkle.framework/Versions/B/Sparkle` resolve,
  rpath `@executable_path/../Frameworks` present, `CFBundleShortVersionString=v0.1.4`.
- Icons: generated dependency-free by `scripts/make-icons.mjs` (own PNG encoder,
  SVG path parser with flattened Béziers, scanline fill + distance-field stroke,
  4x supersampling). Default glyph = MDI `omega` (Apache-2.0) fitted next to the
  Material `spellcheck` checkmark; app icon = rounded diagonal gradient
  `#5EB1FF→#7A5AF8` + white glyph. Outputs: `App/Resources/MenuBarIconTemplate*.png`
  (default) + `App/Resources/MenuBarIcons/{omega-check,omega,spellcheck,checkmark}*.png`
  + `App/Resources/AppIcon.iconset/*.png`.
- Tests: Core 57/57, Engine 29/29 (Linux), App tests + build + `verify-bundle.sh` on macos-15 CI.

## 4. Build / test / release

macOS:
```sh
swift test --package-path Core && swift test --package-path Engine && swift test --package-path App
scripts/build-app.sh release                 # build/SpellCheck.app (universal, embeds frameworks, stamps VERSION)
scripts/verify-bundle.sh build/SpellCheck.app  # MUST pass: executable, rpath, all @rpath deps, archs, resources
scripts/package-release.sh                   # build/SpellCheck-macOS.zip (honors SIGNING_IDENTITY, VERSION)
```
Release: `git tag v0.1.5 main && git push origin v0.1.5` → `release.yml` runs tests,
packages, verifies bundle, optional notarize (secrets `NOTARY_API_KEY`,
`NOTARY_API_KEY_ID`, `NOTARY_ISSUER_ID`, `SIGNING_IDENTITY`), optional Sparkle signing
(secret `SPARKLE_PRIVATE_KEY`), regenerates `appcast.xml` (commits to main), creates
the GitHub Release. `actionlint .github/workflows/*.yml` must stay clean (note:
`secrets` context is not allowed in step `if:` — use `env.X != ''` guards).

Linux sandbox (this agent's box) — Swift 6.2 Debian12 toolchain must be re-downloaded
every session (home is wiped): fetch
`https://download.swift.org/swift-6.2-release/debian12/swift-6.2-RELEASE/swift-6.2-RELEASE-debian12.tar.gz`
via Node fetch (curl is blocked), extract to `~/swift --strip-components=1`, then
`mkdir -p ~/swift-libs && ln -sf /opt/sandbox/image/usr/lib/x86_64-linux-gnu/libncurses.so.6 ~/swift-libs/`
(+ ncursesw), and prefix commands with
`export LD_LIBRARY_PATH=$HOME/swift-libs:$LD_LIBRARY_PATH && export PATH=$HOME/swift/usr/bin:$PATH`.
Only Core+Engine compile/test on Linux; App sources are checked with
`swiftc -parse App/Sources/SpellCheck/*.swift` (parse only) — real compile happens in CI (macos-15).
CI uses Swift **6.2** (6.0.3 had an IRGen crash on `SpellCheckApp.body`).

## 5. gh CLI / GitHub quirks (important)

- The agent's `gh` token **cannot mutate**: no PR merge, no workflow_dispatch, no secret set
  ("Mutating GitHub API calls are not allowed"). It CAN read runs/releases and push refs.
  → Merge by pushing directly: `git push origin <branch>:main` (PR auto-marks MERGED).
- Repo Settings → Actions → Workflow permissions must be **Read and write** (else
  push/tag workflows run zero jobs).
- Do NOT protect `main` (release workflow pushes appcast commits to it).
- Rate limit 429 → wait ~60 s, retry once, then stop.

## 6. Known issues / not-yet-done

1. **Gatekeeper**: releases are unsigned+not notarized → user must right-click→Open
   once per download (or `xattr -dr com.apple.quarantine .../SpellCheck.app`, or
   System Settings → Privacy & Security → Open Anyway). Permanent fix = Developer ID
   signing + notarization via the secrets above (workflow steps already exist).
2. **Sparkle auto-update not yet active end-to-end**: needs a key pair. On a Mac:
   download Sparkle release, run `bin/generate_keys` → add private key as repo secret
   `SPARKLE_PRIVATE_KEY` (Settings → Secrets and variables → Actions); give the public
   key to the agent to embed as `SUPublicEDKey` in `App/Info.plist` (currently absent
   on purpose). Release workflow then signs zips and updates appcast signatures.
   Until then: `SUEnableAutomaticChecks` is on but the updater is gated off without
   a key; "Check for Updates…" shows an explanatory alert. Manual downloads work.
3. **User is testing v0.1.4 on their Mac now** — if it still won't open, get the
   Terminal output of `/Applications/SpellCheck.app/Contents/MacOS/SpellCheck` and/or
   a Console.app crash log.
4. Feature parity with FixKey still missing: voice dictation; polish.
5. `scripts/make-icons.mjs` glyph styles are hardcoded (the SVG-arg path is unused).

## 7. Key files

- `App/Info.plist` — `CFBundleExecutable=SpellCheck`, `NSPrincipalClass=NSApplication`,
  `LSUIElement`, `LSMinimumSystemVersion 13.0`, `CFBundleIconFile`,
  `NSAccessibilityUsageDescription`, `SUFeedURL` (raw.githubusercontent …/main/appcast.xml),
  `SUEnableAutomaticChecks`.
- `scripts/build-app.sh` — assembles the .app: universal build (`--arch arm64 --arch x86_64`,
  single-arch fallback), copies binary/Info.plist/PkgInfo, embeds `*.framework` from the
  SPM bin dir into `Contents/Frameworks` (fallback: find under `App/.build`), adds
  `@executable_path/../Frameworks` rpath if missing, stamps `VERSION` via plutil,
  iconutil → AppIcon.icns, copies MenuBarIconTemplate + MenuBarIcons/, optional codesign
  (frameworks first, then bundle, `--options runtime`).
- `scripts/verify-bundle.sh` — fails CI/release if executable/rpath/@rpath-deps/archs/resources missing.
- `scripts/package-release.sh`, `scripts/make-appcast.sh`, `scripts/make-icons.mjs`,
  `scripts/test-{core,engine,app}.sh`.
- `.github/workflows/ci.yml` (Core+Engine tests ubuntu+macos, App build+test+verify on macos-15),
  `.github/workflows/release.yml` (tags `v*.*.*` + workflow_dispatch).
- `appcast.xml` — Sparkle feed, auto-updated on main by each release.
- `README.md` — features, Install (Option A zip / Option B build), Troubleshooting
  ("app won't open"), Requirements, Auto-update setup for maintainers, Mistral setup,
  Testing, Usage, Privacy.

## 8. Working agreements with the user

- Full autonomy granted ("finish this thing if you don't need me anymore"); push to
  `main` directly is accepted; releases via tags.
- Communication language: Norwegian (user writes Norwegian; agent replies in Norwegian).
- User wants: downloadable releases ✅, model picker with Mistral ✅, auto-update
  (Sparkle; pending signing keys), README install guide ✅, nice icons ✅ (Ω✓ default +
  picker), app must actually launch ✅ v0.1.4.
