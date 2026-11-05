<!-- VIBE-CONTEXT.md — living project context maintained by Sigurd's Vibe chat. The knowledge twin of HANDOFF.md: what the next phase must change and why. Kept in sync with the Personal Knowledge topic "spellcheck-app". -->

# SpellCheck app — Vibe context

Sigurd's macOS menu-bar app that corrects text in any app: select text (or place the caret in a sentence), press the global hot key, review the correction, and it is typed back over the original. A FixKey clone, built in Swift. Repo: **lyngvaldarnegard/SpellCheck** (private, branch `main`). Old scaffold branch `vibe/spellcheck-scaffold-6a9537` is stale — main is the source of truth.

The app was built by a different chat (Vibe Nuage Agent). The Vibe chat's job: hold the standing context and build the next-phase prompt with the prompt-bygger skill.

## Status (05.11.2026)

- Code reviewed end to end by Vibe. HANDOFF.md from the building chat is published on main (commit `6a941e3`).
- Latest release: **v0.1.4** (embeds Sparkle.framework + rpath — fixed the instant dyld launch crash; bundle verification in CI/release). Release history: v0.1.0 broken (no CFBundleExecutable) → v0.1.1 launch fixed, universal → v0.1.2 icon → v0.1.3 Ω✓ icon + picker → v0.1.4 crash fix.
- Tests: Core 57/57, Engine 29/29 (Linux), App tests + verify-bundle on macos-15 CI. CI uses Swift 6.2 (6.0.3 had an IRGen crash).
- Sigurd's verdict on v0.1.4 so far (05.11.2026): the app launches and runs, but the UX is wrong — offline mode must die, prompts must be editable, the UI must be copied from FixKey. Details below.

## Handoff key facts (HANDOFF.md on main)

- Three SwiftPM packages, path deps by directory name (`package: "Core"`, `package: "Engine"`). Data flow: hot key → engine.run → source.grab → backend → confirm → replace → status event.
- Release: `git tag v0.1.5 main && git push origin v0.1.5` → release.yml (tests, package, verify-bundle, optional notarize secrets NOTARY_API_KEY/NOTARY_API_KEY_ID/NOTARY_ISSUER_ID + SIGNING_IDENTITY, optional Sparkle signing secret SPARKLE_PRIVATE_KEY, regenerates appcast.xml and commits it to main — main must stay unprotected, Actions need Read and write permissions).
- The building chat's gh token cannot mutate GitHub (no PR merge, workflow_dispatch, secrets); it pushes refs directly.
- Not yet done: Gatekeeper (unsigned/not notarized — right-click→Open per download), Sparkle auto-update inactive end-to-end (needs key pair; SUPublicEDKey intentionally absent), FixKey feature parity (voice dictation).
- Linux sandbox: only Core+Engine test on Linux; App sources parse-checked only (`swiftc -parse`); real App compile in CI.

## Sigurd's v2 requirements (05.11.2026, his words — binding)

1. **Remove the offline mode entirely.** "det er dumt. det skal bare være api hele poenget er ki redigering av teksten." API-only: the whole point of the app is AI text editing. The rule-based backend, its Settings entry and the offline code paths go away. API configuration becomes mandatory, not an alternative.
2. **No non-editable preset prompts.** The six BuiltinActions (Fix typos, Make professional, Make casual, Summarize, Expand, Translate) are hardcoded and cannot be edited in-app. Remove them, or at minimum move them into the prompt list as ordinary editable entries. Every prompt must be creatable, editable and deletable inside the app.
3. **Copy FixKey's UI wholesale**, at least the prompt page. Settings must contain: API configuration, hot key, and such settings — and prompts get their own separate tab/window: a FixKey-style Prompt Editor (reference description below).
4. **⌘S saves.** Cmd+S must save the prompts and the settings (standard macOS save shortcut in the Prompt Editor and Settings windows — not just a Save button click).
5. **Save indicator.** There must be a visible indicator when something is saved — both after pressing the Save button and after ⌘S. The user must get confirmation that the save landed.
6. **Global hot key: ⌥L (Option+L) opens the prompt picker** — Sigurd's pick, replacing ⌥⌘K. The primary global entry point is the prompt picker (like FixKey's "Open prompt picker ⌘G"), from which he runs any prompt on the current selection/sentence. ⌘S stays reserved for in-app saving only. Consequence for the build: `HotKey.isUsableAsGlobalHotkey` currently requires Cmd or Ctrl in the modifier mask — that validation must be relaxed so a bare Option+key can register as the global default. A separate global quick-fix hotkey is not specified — assume the picker is the only global shortcut unless Sigurd says otherwise.
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
