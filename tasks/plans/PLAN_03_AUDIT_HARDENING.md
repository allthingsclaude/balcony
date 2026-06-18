# Plan: AUDIT_HARDENING

**Created**: 2026-06-19
**Status**: In progress (branch `polish/deep-audit-fixes`)
**Source**: 15-subsystem deep-analysis workflow (30 agents: analyze + adversarial verify). 128 findings verified against code (2 rejected). Cross-agent duplication collapsed below.

Fix correctness/security/robustness defects and ship small high-value UX/perf wins surfaced by a full-codebase audit. The headline is a **catastrophic E2E crypto break** (nonce reuse) plus an **unauthenticated-input-injection** hole; the long tail is session-resolution correctness, CLI terminal-restore safety, settings-file safety, and a batch of contained UX fixes.

Severity tally (deduped): 5 critical (all one crypto issue + one auth issue), 24 high, 42 medium, 57 low.

## Scope & ground rules
- **In scope**: everything below.
- **Out of scope**: cloud relay / APNs / Supabase (PLAN_01, blocked on infra decisions); Dynamic Type / terminal font scaling / iPad / matchedGeometry (deliberately deferred in PLAN_02, need on-device iteration).
- **Verify-as-you-go**: `cd BalconyShared && swift test` for shared changes; `xcodebuild -scheme BalconyMac` / `-scheme BalconyiOS` for app changes. Local toolchain builds (Xcode 26.5).
- **Wire compatibility**: the crypto fix is intentionally wire-compatible (random nonce, same key derivation, nonce still prepended) so Mac and iOS can ship independently and interop with already-deployed clients.

---

## Phase A — Crypto & connection security (CRITICAL/HIGH) 🔄

- [x] **A1. Random per-message nonce** (CRITICAL) — `CryptoManager.generateNonce` was a per-instance counter from 0; both peers share one key via `box.beforenm`, so both directions reused `(key,nonce)`. Replaced with `sodium.randomBytes.buf` (24-byte nonce ⇒ collision-safe, no role negotiation, wire-compatible). *Findings D1/D2/D3/D5.*
- [x] **A2. Nonce-uniqueness regression tests** — `testNoncesAreUniqueAcrossDirections` (100 distinct across both peers) + `testNoncesAreUniqueWithinDirection`; both fail on the old counter. *Findings D15/D29/D51.*
- [x] **A3. Cipher doc correction** — docs/CLAUDE.md said XChaCha20-Poly1305; it's actually XSalsa20-Poly1305 (`crypto_secretbox`). Corrected. *Finding D74.*
- [x] **A4. Real SHA-256 fingerprint** — `KeyPair.fingerprint` was a 64-bit rolling hash doc'd as SHA256; now CryptoKit SHA256 (first 8 bytes). Precondition for future key-pinning. *Finding D50.*
- [x] **A5. `Data(hexString:)` odd-length guard** — returns nil instead of truncating. *Finding D75.*
- [ ] **A6. Auth gate before input** (CRITICAL) — `WebSocketServer.processMessage` only gates `.sessionSubscribe`; `.userInput`/`.terminalResize`/picker selections from an un-handshaked client are forwarded straight to the PTY ⇒ any LAN device can inject keystrokes. Allow only `.handshake` (and `.ping`) when `!isAuthenticated`; require `cryptoManager != nil` for `isAuthenticated`. *Finding D4.*
- [ ] **A7. `.authenticating` intermediate state** (HIGH) — client is marked `.authenticated` synchronously before crypto is set up, so a send racing setup goes plaintext. Only set `.authenticated` after `setupCrypto`. *Finding D14.*
- [ ] **A8. iOS: drop undecryptable frames** (MEDIUM sec) — `WebSocketClient` falls back to treating a decrypt failure as plaintext once crypto is set; hard-drop instead. *Findings D28/D49 + T24.*
- [ ] **A9. Inbound `maxFrameSize` 16KB → 1MB** (HIGH bug) — NIO convenience upgrader hardcodes 16KB; iOS sends up to 16MB single frames, so a >16KB paste/input tears down the connection. Use the designated initializer. *Finding D13.*
- [ ] **A10. Surface `.error` on iOS handshake** (MEDIUM) — Mac emits `.error` on auth failure; iOS ignores it, so failures surface only as a 10s timeout. *Finding D27.*
- [ ] **A11. Auth-gate test** — assert unauthenticated `.userInput` is dropped. *Finding D15 (second half).*

**Plan-tier crypto follow-ups (larger, sequence after A1):** replay protection (T3 — needs a counter/seen-window scheme since random nonces preclude simple ordering), MITM identity-key pinning over QR + Bonjour (T4/D12 — pin `ack.publicKey` against scanned QR key; advertise a stable Keychain identity key), protocol version field (T48).

---

## Phase B — CLI / PTY robustness (HIGH) ⏳

- [ ] **B1. Crash-path terminal restore** (HIGH) — raw mode only restored on the clean `stop()` path; a trap/SIGSEGV/SIGQUIT/SIGHUP leaves the user's tty in raw mode. Add `atexit` + async-signal-safe `tcsetattr` handlers for SIGSEGV/SIGABRT/SIGQUIT/SIGHUP/SIGBUS that restore then re-raise. *Finding D6.*
- [ ] **B2. stdin EOF busy-loop** (HIGH/MED) — stdin read source has no `n<=0` branch; piped/redirected stdin at EOF spins a core. Cancel the source on EOF. *Finding D7.*
- [ ] **B3. `FD_CLOEXEC` on PTY master** (LOW) — master fd leaks into claude + grandchildren. *Finding D53.*

**Plan-tier:** SocketClient fd/`connected` data race (T5), legacy `signal()` → `DispatchSource` for SIGWINCH/INT/TERM (T6), `sessionEnded` frame flush on exit (T20), `stdinActivity` throttle (T21), CLI framer tests (T22).

---

## Phase C — Mac hooks & session orchestration (HIGH/MEDIUM) ⏳

- [ ] **C1. Permission-prompt FD leak / Claude blocked forever** (HIGH) — when a permission prompt is dismissed by anything other than an explicit panel/AskUserQuestion response (auto-dismiss heuristic, session end), the held hook FD is never closed and Claude stays blocked on the hook's stdout. Add `HookListener.cancelPendingResponse(sessionId:)` and call it from `onPromptDismissed`/`.sessionEnded`; bound the hook-handler `recv()` with a finite timeout as defense-in-depth. *Finding D16 (+ T14, T39 sequence after).*
- [ ] **C2. Unix-socket perms + peer-UID check** (HIGH/MED sec) — `~/.balcony` + sockets created world-traversable, no `LOCAL_PEERCRED` check; same-uid local injection. `0o700` dir, `0o600` socket, reject `peer UID != geteuid()`. *Finding D17.*
- [ ] **C3. FrameParser max-length cap** (MED sec) — 32-bit frame length trusted unbounded ⇒ multi-GB buffer growth. Cap at 16MB, drop connection over. *Finding D41.*
- [ ] **C4. `sun_path` bound** (LOW) — socket path copied into 104-byte `sun_path` with no clamp ⇒ overflow for long `$HOME`. Guard. *Finding D68.*
- [ ] **C5. accept() errno handling** (LOW) — accept loops `break` silently on any `<0`; inspect errno (continue on EINTR, log EMFILE). *Finding D69.*
- [ ] **C6. findSessionIdByCwd aliasing** (MED) — the "fall back to any match" loop can route two same-cwd Claude sessions onto one PTY. Return nil when all cwd matches are already mapped. *Finding D38.*
- [ ] **C7. lastStopData TTL** (LOW) — Stop/Notification correlation buffer can leak; add 5s cleanup like `pendingIdleNotifications`. *Finding D67.*

**Plan-tier:** cached PTY fd reuse-after-close (T13), buffered-Notification-before-Stop replay (T14), empty-Stop idle detection (T36), AskUserQuestion parse diagnostics (T37), `AnyCodable` Sendable soundness (T38), FrameParser tests (T40), PTY-resolution tests (T11).

---

## Phase D — Mac session-data correctness & perf (HIGH) ⏳

- [ ] **D1. Shared project-path hash helper** (HIGH) — hashing only replaces `/`; Claude Code also maps `.` and `_` to `-`. Dirs for `my_app`/dotfile projects never resolve ⇒ empty `/resume` list, 0 message count, nil transcript. Centralize `/._ → -` helper, use in `SessionFileReader` + `ConnectionManager`. *Finding D20.*
- [ ] **D2. `currentModelForProject` targeted scan** (HIGH) — ignores `projectPath`, scans *all* projects and returns the globally-newest model ⇒ wrong pre-selection + O(all-projects) walk per `/model`. Hash to one dir. *Finding D19.*
- [ ] **D3. `countMessages` caching** (HIGH perf) — re-streams every session's full JSONL each refresh. Cache by (size,mtime); scan only appended range on growth. *Finding D21.*
- [ ] **D4. Scanners off main actor** (HIGH perf) — `ProjectFileScanner.scan`/`SlashCommandScanner.scan` run synchronously on `@MainActor`. Hop to `Task.detached`. *Finding D22.*
- [ ] **D5. `extractModelFromTail` UTF-8 boundary** (MED) — byte-offset tail decoded with `String(data:.utf8)` returns nil on mid-codepoint slice. Start on a newline boundary / lossy decode. *Finding D43.*
- [ ] **D6. `matchesGitignore` component match** (MED) — substring `contains` over-excludes unrelated files; match per path component, ignore `!` lines. *Finding D44.*

**Plan-tier:** TranscriptTailer debounce (T16), reopen()-on-missing-path robustness (T17), tail/hash tests (T18).

---

## Phase E — Mac setup safety (HIGH) ⏳

- [ ] **E1. Atomic settings write + backup** (HIGH) — `patchHooks` writes `~/.claude/settings.json` non-atomically, no backup; a crash mid-write corrupts the user's Claude config. `.atomic` write + one-time `.balcony-backup`. *Finding D23.*
- [ ] **E2. Unparseable-settings guard** (HIGH) — on parse failure `patchHooks` silently discards the entire file. Throw `SetupError.settingsUnparseable` instead. *Finding D24.*
- [ ] **E3. migrateOldSoundPreference ordering** (MED) — runs after `registerDefaults`, so the guard is always false and old prefs are lost. Swap order. *Finding D45.*
- [ ] **E4. Fish-alias detection** (MED) — alias written in a form the detector never matches ⇒ checklist stuck incomplete. Make `isAliasInstalled` shell-aware. *Finding D46.*
- [ ] **E5. AppleScript path quoting** (MED sec) — admin CLI install breaks/injects on a `'` in the path. Add `shellQuoted`. *Finding D47.*

**Plan-tier:** wire `wsPort` pref (D48 — currently inert), integer-pref `!= 0` masking (T46), onboarding-close-marks-complete (T47).

---

## Phase F — Mac connection robustness (MEDIUM) ⏳

- [ ] **F1. Outbound send ordering** (HIGH bug) — per-message detached `Task` before encrypt can reorder the wire stream ⇒ corrupted terminal/history. Serialize encrypt+send per client. *Finding D8 (+ T2 inbound).*
- [ ] **F2. Heartbeat snapshot-before-mutate** (MED) — mutates `clients` while iterating + double-fires disconnect. Snapshot, let `channelInactive` drive cleanup. *Finding D39.*
- [ ] **F3. Per-connection device tracking** (MED) — authenticated clients appended without dedup; disconnect removes ALL clients sharing a device id. Key by `client.id`. *Finding D40.*

**Plan-tier:** NWPathMonitor re-advertise on network/wake/name change (T12), BLE service re-add guard (T34), `shouldUpgrade` path/origin check (T35).

---

## Phase G — Mac prompt panel (MEDIUM) ⏳

- [ ] **G1. Double-send during fade-out** (MED) — key events in the 250ms fade can fire callbacks twice. Null handlers + `resignKey` before fade. *Finding D42.*
- [ ] **G2. Live-typing diff corruption** (HIGH) — keystroke diff assumes append-only; mid-string edits/paste-replace corrupt PTY input. Make submit authoritative (Ctrl-U + full text + Enter; use the discarded `text` param). *Finding D18.*
- [ ] **G3. Markdown memoization** (LOW perf) — idle-prompt markdown re-parsed every keystroke. Cache by text. *Finding D70.*

**Plan-tier:** multiSelect AskUserQuestion (T15), scroll-idle timer leak (T41), previousApp focus-restore stacking (T42), fenced-code parser trailing-prose drop (T43), ESC-in-textfield blur (T44), nav-sequence tests (T45), "Other" keyboard shortcut (D71).

---

## Phase H — iOS correctness (HIGH/MEDIUM) ⏳

- [ ] **H1. iOS sends `terminalResize`** (HIGH) — iOS never sends resize, so the PTY stays at the Mac terminal width ⇒ wrapping artifacts on iPhone. Send `TerminalResizePayload` on subscribe/rotation; re-init the local parser. *Finding D9 (+ T30).*
- [ ] **H2. First-reply auto-scroll** (HIGH) — `displayCount` unchanged when the loader is replaced by the event ⇒ first assistant chunk not scrolled. Add a content-identity follow trigger. *Finding D10.*
- [ ] **H3. Transcript stops past 2000 rows** (HIGH) — `getTopVisibleRow` vs `getScrollInvariantLine` index mismatch freezes the transcript once scrollback fills. Anchor at the true scroll-invariant top. *Finding D11.* (Risky — add regression test, verify carefully.)
- [ ] **H4. `handleSessionList` early `break`** (MED) — breaks after the first transitioning session, suppressing notifications for others. `continue`. *Finding D30.*
- [ ] **H5. `awaitingReply` uses filtered list** (MED) — loader keyed on unfiltered last event but transcript hides sidechain turns. *Finding D31.*
- [ ] **H6. Chrome cursor heuristic** (MED) — any styled cell treated as cursor, truncating styled in-progress input. Detect `.inverse`. *Finding D32.*
- [ ] **H7. Input-seq reset on resubscribe** (MED) — Mac `lastInputSeq` never resets, iOS resets to 0 ⇒ sync breaks after first resubscribe. *Finding D26 (+ T8).*

**Plan-tier:** dead PTY-line rendering block removal (T9, ~mechanical), incremental parser extraction (T10), transcript de-dup O(n²) (D56), optimistic-bubble FIFO prune (D57), TranscriptBlock stable ids (T27), picker-query seeding (T25), submit line-kill for wide chars (T26).

---

## Phase I — iOS shell correctness (MEDIUM/LOW) ⏳

- [ ] **I1. Proximity auto-arm overwrites manual toggle** (MED) — every away transition stomps the user's notifications switch. Track a manual-override flag. *Finding D33.*
- [ ] **I2. Deleted device auto-reconnects** (MED) — removing a paired device leaves `lastConnectedDeviceId` ⇒ silent reconnect to the "removed" Mac. Clear it + disconnect. *Finding D34.*
- [ ] **I3. "Reset Encryption Keys" bypasses ConnectionManager** (MED) — stale in-memory list, misleading title. Add `unpairAll()`, rename "Forget All Devices". *Finding D35.*
- [ ] **I4. SoundManager AVAudioSession** (MED) — alert sounds silenced by the mute switch (no category set). Configure `.playback`. *Finding D36.*
- [ ] **I5. Notification-permission awareness** (MED) — toggle has no idea perms are denied ⇒ silent no-op. Surface status + Open-Settings. *Finding D37.*
- [ ] **I6. Notification grouping/clearing** (LOW ux) — set `threadIdentifier`, clear delivered on open. *Finding D61.*
- [ ] **I7. BLECentral main-thread publish** (LOW) — `isScanning` mutated off-main. *Finding D55.*
- [ ] **I8. QR scanner stop off-main** (LOW) — `stopRunning()` on main inside metadata callback. *Finding D62.*

**Plan-tier:** handshake-timeout continuation leak (D54/T?), Live Activity `staleDate` (T31), notification-permission deeper UX.

---

## Phase J — Shared models & low-risk cleanups (MIXED) ⏳

- [ ] **J1. Enum unknown-fallback** (HIGH robustness) — one unknown raw value fails the whole payload decode, wiping the list to empty. Add `.unknown` to wire-crossing enums (`SessionStatus`, `ModelTier`, `ToolRiskLevel`, `SlashCommandInfo.Source`) + sort handling. *Finding D25.*
- [ ] **J2. Destructive-command tokenization** (MED) — naked substring match flags `git add .`/`terraform apply`/`add files` as destructive; misses uppercase. Tokenize on shell separators, match first token against a set. *Finding D52.*
- [ ] **J3. Hex odd-length test** — covered by A5; add explicit test.
- [ ] **J4. detectedOptions / AskUserQuestion.from tests** (LOW) — genuinely untested heuristics. *Finding D76.*
- [ ] **J5. SessionInfo.displayName doc** (LOW) — describes a format it no longer produces. *Finding D77.*
- [ ] **J6. Dead-code/trivial sweep** — ToolResultRow dead ternary (D58), `isDestructiveLabel` word-boundary (D59), truecolor cache bound (D60), duplicate `statusPriority` (D63), build-phase output deps (build warning).
- [ ] **J7. Voice ordering/routing** (LOW) — concatenate transcript+Enter into one Task (D65); capture target session at record start (D66).
- [ ] **J8. applicationShouldTerminate** (LOW) — graceful socket teardown before exit (D64).

**Plan-tier:** move duplicated protocol payloads into Shared (T7), TranscriptParser non-object element (T49), `parse(_:)` blob entry doc (T50), away/RSSI threshold semantics (T19 — needs a product call), ping/pong dead cases (T23).

---

## Suggested order
A (security, highest stakes) → E (don't corrupt user's settings.json) → B (CLI tty safety) → D (session-data correctness) → C (hooks) → F → H → G → I → J. A/E/B/D first because they're correctness/safety with the clearest user impact and the cleanest verification.

## Notes
- 2 rejected findings (false positives caught by the verify pass): see `tasks/STATE.md`.
- One analysis unit (`ios-terminal-surfaces`) died mid-run; re-run separately, fold results in.

**Last Updated**: 2026-06-19
**Generated By**: 15-subsystem analyze+verify workflow + synthesis
