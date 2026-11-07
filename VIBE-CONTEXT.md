<!-- VIBE-CONTEXT.md — living project context maintained by Sigurd's Vibe chat. The knowledge twin of HANDOFF.md: what the next phase must change and why. Kept in sync with the Personal Knowledge topic "spellcheck-app". -->

# SpellCheck app — Vibe context

Sigurd's macOS menu-bar app that corrects text in any app: select text (or place the caret in a sentence), press the global hot key, review the correction, and it is typed back over the original. A standalone AI text-editing app, built in Swift. Repo: **lyngvaldarnegard/SpellCheck** (private, branch `main`). Old scaffold branch `vibe/spellcheck-scaffold-6a9537` is stale — main is the source of truth.

The app was built by a different chat (Vibe Nuage Agent). The Vibe chat's job: hold the standing context and build the next-phase prompt with the prompt-bygger skill.

## Status (06.11.2026 — v0.2.10 session)

- **Next release must be v1.0.0** (Sigurd's instruction): the version after
  v0.2.10 is version 1 — tag `v1.0.0`, not v0.2.11. Recorded in HANDOFF §4.
- **v1.0.0 must ship updated default prompts** (Sigurd's instruction): he
  will provide the new prompt list (titles + text) to replace
  `Prompt.defaultPrompts`. Existing installs keep their own prompts
  untouched (his explicit choice — the one-time seeding guard already
  guarantees this; new defaults only apply to fresh installs). Do not ship
  v1.0.0 before his list is received.
- **All GitHub content must be in English** (Sigurd's instruction): issues,
  PRs, release notes, docs, commit messages — never Norwegian. Release notes
  v0.2.6–v0.2.10 were translated retroactively; HANDOFF working agreements
  updated so future sessions follow this automatically. The only Norwegian
  left is the seeded "Fix Grammar" prompt content (functional app data —
  Norwegian legal-term spell-out instructions), kept unless Sigurd says
  otherwise.
- **v0.2.10 published** (paste-only write-back, no messages, icon cleanup):
  see below for v0.2.9/v0.2.10 details. v0.2.9 was never published as a
  release (appcast push race) — v0.2.10 supersedes it.

## Status (06.11.2026 — v0.2.9 session)

- **v0.2.9 (this session)**: post-paste verification REMOVED by explicit user
  decision ("I literally see the verification"): the write-back now pastes
  once over the validated selection and returns immediately — no settle
  wait, no document read-back, no unverified/replace-failed reports after a
  paste. Saves ~0.5–1 s per correction and removes the last "could not verify"
  noise. Pre-paste safety kept (target reactivation, selection-intact check,
  stale-document guard) so nothing is ever written to the wrong place.
  Success = "paste issued", not "document verified" — if a paste silently
  fails, the menu bar still shows ✓; the corrected text is on the clipboard
  as the manual fallback. Issue #16 closed (Fast/Thorough toggle moot);
  issue #5's misleading-report complaint is resolved by this design change
  (open until Sigurd confirms). Tests: Core 76/76, Engine 49/49 (Linux), App
  parse-checked; real-Mac confirmation pending.
- **v0.2.8**: FixKey-style spinner (`WorkingIndicatorController`)
  near the cursor while the AI is working (non-activating, click-through,
  never key; shown on `working`, hidden on terminal events, stays up on a
  `busy` rejection while the original run is in flight); identical AI results
  are now written back over the selection too (visible replacement = user's
  confirmation; AX verify treats an unchanged document as the expected
  outcome for an identical write-back); SpellCheck's own windows stay lowered
  behind other apps' windows until the correction finishes, not just while
  the picker is open (issue #12 remainder — not reproducible dev-side, needs
  Sigurd's confirmation). Tests: Core 76/76, Engine 49/49 (Linux); App
  parse-checked + new App tests in macOS CI. All three changes await
  Sigurd's real-Mac testing.
- **v0.2.7**: intermittent ⌥L/picker/focus investigation
  (issue #4) — root causes found in code: the picker silently refused to open
  while a request was in flight (busy gate) and a second run was silently
  dropped, explaining "nothing happens" + "suddenly corrected later"; rapid
  activations could open overlapping pickers (async guard race); unbounded
  Accessibility calls could stall the grab for seconds. Fixes: picker opens
  even while busy, rejected runs emit a menu-bar-only `busy` event (no popup,
  no duplicate request/paste), synchronous picker-session flag, 0.75 s AX
  messaging timeout + 3 s grab deadline, and a stale-operation guard (document
  value snapshot at grab; abort if it changed before paste — a late response
  can no longer edit a document the user moved on from). Backup model now has
  the same Fetch-models picker as the primary (never overwrites the saved
  value). Mistral prompt caching: stable non-sensitive `prompt_cache_key`
  (FNV-1a of shared+selected prompt) sent only to *.mistral.ai; other
  providers' bodies unchanged (tested). Cache hits NOT verified live — Sigurd
  should check Admin → Usage (64-token blocks, <64-token prompts never hit,
  cached tokens at 10% price). Tests: Core 76/76, Engine 49/49 (Linux); App
  parse-checked, real App tests in macOS CI. Issue #12 (Loading window) is
  solved per Sigurd. All fixes await Sigurd's real-Mac testing.
- **v0.2.6**: shared prompt (Settings section, sent before the
  selected prompt in every request, editable default asking for result-only
  in the original language), backup model with one-retry fallback
  (408/429/5xx, timeouts, empty/unusable responses; auth errors never fall
  back; both-fail error names both models), lenient GLM-style response
  parsing (string/part-array/null content; actionable `unusableResponse`
  error instead of "data couldn't be read"), outside-click picker dismissal
  (no refocus, nothing edited), replacement failures now menu-bar-only (no
  intrusive popup), Ω-only icon at the same full scale as Ω+checkmark
  (previews in `docs/icon-previews/`), the stray SwiftUI "Loading…" window
  scene removed (no more Space switch), and other SpellCheck windows no
  longer raised by ⌥L (temporarily window-level −1 during a picker session).
  Release notes now require `scripts/release-notes/vX.Y.Z.md` (issue #14).
  Tests: Core 68/68, Engine 43/43 on Linux; App on macOS CI. Issues stay
  OPEN until Sigurd confirms each on his Mac. GLM 5.3 Flash compatibility is
  NOT verified against the provider — Sigurd must test.
- **v0.2.5 live** (Sparkle-signed, CI green): contains the v0.2.3 workflow
  fixes, the v0.2.4 fix (model-echoed ```<<< / >>>``` input markers were
  pasted into Notion as extra text / quote blocks — ResponseCleaner now strips
  exactly that framing; Sigurd confirmed the workflow itself works in Notion
  on the third attempt) and drag-and-drop prompt reordering in the Prompt
  Editor. **Sigurd confirmed drag-to-reorder works.** Issues #4–#8 stay open
  until Sigurd has re-tested on his Mac (persistence across restart/update
  and first-item picker highlight still unconfirmed).

- **Sigurd tested v0.2.2 on his Mac (ground truth):** Enter in the picker reached the ORIGINAL text field (destructive line break); a clicked prompt in TextEdit partially changed the text but showed "Could not replace the text"; saved prompts were lost across the update (API key survived); the menu-bar icon looked low-res. The v0.2.2 handoff claim that the field-editor delegate fixed the keyboard was WRONG.
- **v0.2.3** fixes all four: `PickerPanel` (canBecomeKey) + explicit `NSApp.activate` so the picker owns the keyboard; FixKey-style clipboard-paste replacement with pre-paste selection verification, single-attempt paste, honest unverified/failed distinction, corrected text stays on the clipboard; lossy prompt decoding + corrupt-file backup + no stale-snapshot saves; vector template PDFs (+SVG sources) for all four icon styles with the Ω full-size and a knocked-out checkmark. Tracked in GitHub issues — they stay OPEN until Sigurd confirms on his Mac.
- v2 history: v0.2.0 broken (ad-hoc + hardened runtime dyld abort) → v0.2.1 launch fixed → v0.2.2 picker X button + field-editor delegate (insufficient) → v0.2.3.
- Repo **made public** (Sigurd's choice) → Sparkle feed reachable. Sigurd generated the Sparkle EdDSA key pair: public key embedded as `SUPublicEDKey`, private key is repo secret `SPARKLE_PRIVATE_KEY`. Releases sign the zip (`sparkle:edSignature` verified in appcast.xml).
- Sigurd's v1 settings migrated automatically (API key preserved — he noticed and asked why; that's the intended `Settings.migrated()` behavior).
- CI now: tests + package + verify the SHIPPED zip + signature-consistency checks + 8-second launch smoke test on macos-15.
- **Pending Sigurd**: hands-on test of the full workflow (Notion + TextEdit, ⌥L picker, replacement in the original app) and a "Check for Updates…" run to confirm the auto-update install end to end. Optional: Apple Developer Program for a stable Developer ID identity + notarization.
- The older v2 requirements below are now implemented; kept for context.

- **The v2 refactor is implemented** (branch `vibe/v2-core-workflow-720d1f`, PR to main): ⌥L prompt picker (FixKey-style dark popup, search/↑↓/Enter/Esc/click/empty state), API-only (offline mode deleted), all prompts editable via a separate FixKey-style Prompt Editor, Review/confirmation window + setting removed, ⌥L accepted as a global shortcut with visible registration failures, v1 settings migrated without loss, AX grab with layered fallbacks (selected text → value+range → clipboard), target app re-activated + write verified before replacing, errors as alert windows, ⌘S + visible Saved indicator in Settings and Prompt Editor, Mistral preset pairs base URL with `mistral-small-latest`, bundles always signed (ad-hoc fallback), release workflow extracts the real `sparkle:edSignature`. Tests: Core 48/48, Engine 27/27 on Linux; App compiles/tests on macos-15 CI.
- **Still needs Sigurd's real-Mac verification**: the full workflow in Notion and TextEdit (Notion is Electron and may only work through the clipboard fallback layer).
- **Still needs user actions**: Sparkle key pair (generate_keys on a Mac + `SPARKLE_PRIVATE_KEY` secret + `SUPublicEDKey` in Info.plist), a credential-free public feed for appcast+zips (repo is private; or make repo public), and optionally a Developer ID certificate + notarization secrets for a stable signing identity.
- Pre-v2 history: latest release **v0.1.4** (Sparkle.framework embedded + rpath; bundle verification in CI/release). v0.1.0 broken (no CFBundleExecutable) → v0.1.1 launch fixed, universal → v0.1.2 icon → v0.1.3 Ω✓ icon + picker → v0.1.4 crash fix.
- CI uses Swift 6.2 (6.0.3 had an IRGen crash).
- Sigurd's v2 requirements below are now implemented; kept for context.

## Handoff key facts (HANDOFF.md on main)

- Three SwiftPM packages, path deps by directory name (`package: "Core"`, `package: "Engine"`). Data flow: hot key → engine.run → source.grab → backend → confirm → replace → status event.
- Release: `git tag v0.1.5 main && git push origin v0.1.5` → release.yml (tests, package, verify-bundle, optional notarize secrets NOTARY_API_KEY/NOTARY_API_KEY_ID/NOTARY_ISSUER_ID + SIGNING_IDENTITY, optional Sparkle signing secret SPARKLE_PRIVATE_KEY, regenerates appcast.xml and commits it to main — main must stay unprotected, Actions need Read and write permissions).
- The building chat's gh token cannot mutate GitHub (no PR merge, workflow_dispatch, secrets); it pushes refs directly.
- Not yet done: Gatekeeper (unsigned/not notarized — right-click→Open per download), Sparkle auto-update inactive end-to-end (needs key pair; SUPublicEDKey intentionally absent), FixKey feature parity (voice dictation).
- Linux sandbox: only Core+Engine test on Linux; App sources parse-checked only (`swiftc -parse`); real App compile in CI.

## Sigurd's v2 requirements (05.11.2026, his words — binding)

1. **Remove the offline mode entirely.** (User's words, translated from Norwegian: "it's dumb — it should just be API; the whole point is AI editing of the text.") API-only: the whole point of the app is AI text editing. The rule-based backend, its Settings entry and the offline code paths go away. API configuration becomes mandatory, not an alternative.
2. **No non-editable preset prompts.** The six BuiltinActions (Fix typos, Make professional, Make casual, Summarize, Expand, Translate) are hardcoded and cannot be edited in-app. Remove them, or at minimum move them into the prompt list as ordinary editable entries. Every prompt must be creatable, editable and deletable inside the app.
3. **Copy FixKey's UI wholesale**, at least the prompt page. Settings must contain: API configuration, hot key, and such settings — and prompts get their own separate tab/window: a FixKey-style Prompt Editor (reference description below).
4. **⌘S saves.** Cmd+S must save the prompts and the settings (standard macOS save shortcut in the Prompt Editor and Settings windows — not just a Save button click).
5. **Save indicator.** There must be a visible indicator when something is saved — both after pressing the Save button and after ⌘S. The user must get confirmation that the save landed.
6. **Global hot key: ⌥L (Option+L) opens the prompt picker** — Sigurd's pick, replacing ⌥⌘K. The primary global entry point is the prompt picker (like FixKey's "Open prompt picker ⌘G"), from which he runs any prompt on the current selection/sentence. ⌘S stays reserved for in-app saving only. Consequence for the build: `HotKey.isUsableAsGlobalHotkey` currently requires Cmd or Ctrl in the modifier mask — that validation must be relaxed so a bare Option+key can register as the global default. A separate global quick-fix hotkey is not specified — assume the picker is the only global shortcut unless Sigurd says otherwise. **Confirmed by test (05.11.2026):** setting ⌥L in the current app does nothing — it just types "ﬁ" — because `HotKeyMonitor.start()` silently returns when `isUsableAsGlobalHotkey` fails. v2 must also surface hot-key registration failures instead of failing silently. Registered Carbon hot keys consume the keystroke, so once working the ﬁ character is not typed; if any app still receives it, the fallback is a Cmd-including combo.
7. FixKey reference screenshots: menu dropdown + Prompt Editor (held by Vibe; description below). The prompt for the coding AI must carry the full UI description.

## FixKey UI reference (from Sigurd's screenshots — prompt source material)

Menu-bar dropdown (dark, rounded, thin separators, white on dark, macOS status items visible above): items verbatim in order: "Fix current line ⌘S" · "Open prompt picker ⌘G" · "Languages ›" · "Settings" · "Prompt Editor" · "Vocabulary" · "Onboarding" · "✨ Follow on X" · "Open Website" · "Submit feedback or bug" · "Check for Updates…" · "Quit ⌘Q". Note the two hot-key actions at top (fix the current line, open the prompt picker), the dedicated Prompt Editor and Vocabulary entries, and Check for Updates/Quit at the bottom.

Prompt Editor window (dark theme): standard macOS window, traffic lights top-left, centered title "Prompt Editor". Two-column split. Left sidebar (~30% width): a "Search prompts" search field with magnifying-glass icon at the top; below it a vertical scrollable list of prompt rows. Each row is a small card: a glyph icon on the left (A✓ for Fix Grammar, pen for Improve Writing, ⚡ for Summarize, ? for Explain this, ≡ for Make Shorter / Convert to Bullet Points, 📄 for translation prompts), a bold white prompt title, and a one-line gray description preview truncated with "…". The selected row is highlighted in green. User-created prompts (Allvit, Napoloen, Juss) sit in the same list as the default ones, same styling, same editability — no visible distinction between "builtin" and "custom" prompts. Right editor panel (~70%): a "Enter prompt title" text field at the top (filled with the selected prompt's name), below it a large multi-line "Description" text area holding the full prompt text (e.g. "Polish the text by fixing grammar, spelling, punctuation, and capitalization only. Keep the same language, meaning, tone, names, numbers, dates, links, and formatting. Return only the polished text." and for the Allvit/Juss prompts a second paragraph "Write legal terms and law names in full, e.g., «skatteloven» instead of «sktl.» and «jamfør» instead of «jf.». Keep FSFIN abbreviated."), and at the bottom-right two buttons: "Delete" (red) and "Save" (green). Fields sit on slightly lighter dark surfaces against the window's dark background; white text, gray labels, clean sans-serif, consistent spacing. Design consequences for SpellCheck: the Prompt Editor is a master–detail two-pane window (list + editor), prompts are plain data rows (icon, title, description/prompt body), all CRUD happens in-app, and the prompt body is free-form text a user can write anything into — including domain-specific instructions like full legal-term spell-outs.

## Known gaps from code review (context for the prompt; some are superseded by v2)

1. `Settings.showConfirmation` persisted but not wired — confirmation window always shows regardless of the toggle.
2. `Settings.launchAtLogin` persisted but no implementation (no SMAppService).
3. Replace clobbers the clipboard (NSPasteboard + synthetic ⌘V).
4. Sentence mode needs the target app to expose kAXValue (full document); otherwise silent "No text found".
5. No API request timeout/retry; errors surface only as menu-bar tooltips.
6. Custom prompts currently ride through the engine as action .fixTypos + customPrompt.

## The prompt workflow (standing plan)

Build the next-phase prompt with the prompt-bygger skill (iterative, until Sigurd says ready). Inputs now in hand: HANDOFF.md (on main), the v2 requirements above, and the FixKey UI reference. The prompt targets an expensive coding AI (Vibe Code, Cursor, Claude Code or similar) and must be self-contained: architecture summary, current state, v2 requirements (API-only, all prompts editable, FixKey-style Prompt Editor + Settings, ⌥L opens the prompt picker), the UI reference description, and the review gaps worth fixing (confirmation toggle, clipboard clobber, kAXValue fallback, timeout). Never claim the app is tested/fixed on his behalf; his verdict is ground truth over any green suite. Output prompt in English.

Update this file when: a new release lands, requirements change, the prompt is built, or the app ships v2. The canonical twin lives in the Personal Knowledge topic "spellcheck-app" — keep both in sync.
