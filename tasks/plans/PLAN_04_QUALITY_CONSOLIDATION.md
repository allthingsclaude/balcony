# Plan: QUALITY_CONSOLIDATION

**Created**: 2026-07-09
**Status**: Draft — not started.
**Source**: Full-repo quality audit (2026-07-09), 4 parallel subsystem agents (BalconyMac, BalconyiOS, BalconyShared+CLI, infra/CI/docs) + direct verification of the headline security finding. Supersedes the open tail of PLAN_03 (C1, G2, H1–H3 folded in below) and reconciles the stale plan/branch tracking.

## Headline

The system is well-built (overall ~6.5/10; BalconyShared 8, iOS 7, CLI 6.5, Mac 6, CI 6, docs 5) but held down by **one critical security hole** — the WebSocket server does not authenticate clients, so any LAN device can inject keystrokes into the live Claude Code PTY (≈ LAN RCE) — plus **no test target for either app or the CLI**, and **a README that advertises a crypto stack deleted in the TLS refactor**. This plan closes those and the correctness/robustness/dead-code/product tail behind them.

Severity tally: **1 critical, 12 high, ~18 medium, ~15 low** (deduped across the 4 audits).

## Scope & ground rules

- **In scope**: everything below (Phases A–I).
- **Out of scope for now**: shipping the cloud-relay feature end-to-end (Phase G scopes only the redesign + stub cleanup, not APNs infra); building out full iPad/Dynamic-Type (Phase I is a scoped subset, the rest stays deferred as in PLAN_02).
- **Verify-as-you-go**: `cd BalconyShared && swift test --disable-sandbox` for shared changes; `xcodebuild -project Balcony.xcodeproj -scheme BalconyMac` and `-scheme BalconyiOS -destination 'generic/platform=iOS Simulator'` for app changes. Local toolchain builds (Xcode 26.5); CI on `main` is authoritative.
- **Wire compatibility**: the auth change (A1) and protocol-version change (B1) are breaking. Gate both behind a `minCompatVersion` in the handshake so an updated Mac can still reject/deprecate old clients cleanly rather than silently mis-handshaking. Ship Mac + iOS together for these two.
- **Branch**: suggest `polish/quality-consolidation`. Land phase-by-phase; A ships first and alone.

---

## Phase A — Security (CRITICAL / HIGH) — ship first, ship together

- [ ] **A1. Authenticate the client to the server** (CRITICAL) — `handleHandshake` sets `client.state = .authenticated` unconditionally after decoding `DeviceInfo`; the auth gate at `WebSocketServer.swift:254` is satisfied by an empty handshake. Combined with `0.0.0.0` bind (`:115`) + Bonjour advertisement (`BonjourAdvertiser.swift:28-47`), any LAN device can connect, read transcripts, and inject `userInput` into the live PTY (`ConnectionManager.swift:528-556`) — approving Claude permissions by injecting `"y\r"` and driving Bash. **Fix**: pairing establishes a shared secret (generate on Mac, carry in the QR alongside `fp`, persist on the phone). Handshake must present a proof of that secret (e.g. HMAC over a server-sent nonce, or the secret itself over the already-pinned TLS channel); Mac verifies against a **persisted allowlist of paired devices** and only then flips `.authenticated`. Reject + log unknown devices. *(Mac audit #1; verified against `WebSocketServer.swift:213-232`, `WebSocketClientHandler.swift:52-54`.)*
- [ ] **A2. Device pairing store on the Mac** (HIGH, precondition for A1) — there is currently no record of paired devices on the Mac (trust is one-directional). Add a Keychain-backed store of `{deviceId, secret, name, pairedAt}`; wire pairing (QR generation) to write it and Settings→device-management to revoke. *(Mac audit #6/§6.)*
- [ ] **A3. Fix multi-option prompt confirmation race** (HIGH, safety) — `PromptOverlayView.swift:285-302` navigates by sending `option.index - selectedIndex` arrow keys then `\r` after a fixed 50ms; a stale parse or slow PTY confirms whichever option the cursor actually sits on — possibly a destructive Deny/delete. **Fix**: send the literal option token like the permission path already does (`onSendInput(option.inputToSend)`, `:39-42`) instead of arrow-count + timed Enter. *(iOS audit #1.)*
- [ ] **A4. Auth-gate regression test** — assert an unauthenticated `.userInput` is dropped and that a bad/missing pairing proof is rejected. (Was PLAN_03 A11, still open.) Requires Phase D test target.
- [ ] **A5. Rate-limit the input path** (MEDIUM) — no rate limiting on WebSocket/hook/PTY input. Add a simple token bucket per client on `userInput`/picker messages as defense-in-depth. *(Mac audit §4.)*

---

## Phase B — Protocol hardening (HIGH)

- [ ] **B1. Add a protocol version field** — `BalconyMessage`/`DeviceInfo` carry no version anywhere; skew is handled only by optional-field tolerance + enum `.unknown`. Add `protocolVersion` (and `minCompatVersion`) to the handshake; refuse or warn on incompatible peers instead of silently mis-behaving. *(Shared audit #2.)*
- [ ] **B2. `MessageType.unknown` fallback** — `MessageType` is the one wire enum with no `.unknown` case, so an unrecognized `type` throws in `MessageDecoder.decode` (`MessageDecoder.swift:14`) and drops the **whole envelope** — fail-hard where every payload enum is fail-soft. Add a custom `init(from:)` → `.unknown`, and have the router skip unknown types gracefully. *(Shared audit #1.)*
- [ ] **B3. SPKI-based cert pinning + rotation story** (MEDIUM) — pin is `SHA-256(whole cert DER)` (`TLSIdentity.swift:82-96`) with a 10-year cert (`:41`); any re-issue breaks every pairing, and there is no overlap/rotation path. Move to SPKI pinning so the key can outlive the cert, and document a rotation procedure. *(Shared audit #5.)*
- [ ] **B4. Prove pinning fails closed** — no test asserts a *wrong* cert is rejected (`TLSIdentityTests` only proves stability/agreement). Add a rejection test. *(Shared audit §6.)*
- [ ] **B5. Cap payload size in the shared decoder** (LOW) — `SocketClient.readAvailable` trusts a 4-byte length prefix with no cap (`SocketClient.swift:293-297`); use `loadUnaligned` and bound the allocation. *(Shared audit #10.)*

---

## Phase C — Concurrency & resource correctness (HIGH / MEDIUM)

- [ ] **C1. Mac: stop direct cached-fd writes bypassing the actor** (HIGH) — `AppDelegate` caches raw PTY fds (`:29`) and writes via `sendInputDirect` (`PTYSessionManager.swift:355-371`) from voice/typing/response paths while the actor closes the fd on disconnect (`:298,328`); writes can land on a recycled descriptor or interleave with `sendFramed` and corrupt framing. Route all writes through the owning actor (or guard with the actor's serial context). *(Mac audit #2.)*
- [ ] **C2. Partial-write / EAGAIN truncation** (HIGH) — `sendInputDirect`/`sendFramed` (`PTYSessionManager.swift:362-370,461-469`) and `HookListener.sendPermissionResponse` (`:171-179`) `break` on `n<=0`, silently dropping the rest of a length-prefixed frame → CLI `FrameParser` desync. Loop/poll until fully written (or `poll()` on EAGAIN). *(Mac audit #3.)*
- [ ] **C3. CLI: data races on `socketFD`/`connected`** (HIGH) — mutated from main/read/write queues unsynchronized (`SocketClient.swift:140-145,187,237-252,282`); worst case a stale queued frame writes into a freshly reconnected socket. Serialize on one owning queue or add a lock. *(Shared/CLI audit #3.)*
- [ ] **C4. CLI: `readSource` leaked/duplicated on write-side disconnect** (MEDIUM-HIGH) — write-side teardown (`SocketClient.swift:237-253`) closes the fd but never cancels `readSource`; reconnect stacks a second `DispatchSourceRead` (`:263-273`). Cancel + nil before reconnect. *(Shared/CLI audit #4.)*
- [ ] **C5. Mac: `BLEPeripheral` data race** (MEDIUM) — plain `NSObject`/`ObservableObject` with `.global()`-queue delegate callbacks mutating state also written from `@MainActor` (`BLEPeripheral.swift:6,22-34`). Make it an actor or confine to a serial queue. *(Mac audit #7.)*
- [ ] **C6. Mac: hook listener blocking reads with no timeout** (MEDIUM) — hook client fds never set `O_NONBLOCK`; `readHookEvent` blocks in `while true { read(fd) }` on a shared GCD pool (`HookListener.swift:187-223,245-261`) → a hung local peer pins a worker; enough of them exhaust the pool (local DoS). Add a read timeout / non-blocking + poll. *(Mac audit #4.)*
- [ ] **C7. Mac: permission-prompt FD leak → Claude blocked forever** (HIGH) — when a permission prompt is dismissed by anything other than an explicit response, the held hook FD is never closed and Claude stays blocked on the hook's stdout. Add `HookListener.cancelPendingResponse(sessionId:)` and call from `onPromptDismissed`/`.sessionEnded`; bound the hook-handler `recv()` with a finite timeout. (Was PLAN_03 C1, still open.) *(Mac audit §4 / STATE.md.)*
- [ ] **C8. Smaller leaks/crashes** (LOW) — `MacDeviceID` `takeUnretainedValue()` → `takeRetainedValue()` (`MacDeviceID.swift:17-26`, CF leak); `SessionFileReader.messageCountCache` unbounded, add LRU eviction (`:281-283`); `AwayDetector` `CGEventType(rawValue: ~0)!` force-unwrap (`:141`); CLI `sendSessionEnded` almost always dropped on exit — flush before closing fd (`main.swift:52`). *(Mac audit #10; Shared/CLI audit #6.)*

---

## Phase D — Test infrastructure (HIGH) — unblocks A4/B4 and future regressions

- [ ] **D1. Create `BalconyMacTests` + `BalconyiOSTests` targets** — add to `project.yml`, wire into CI (`ci.yml` currently only runs `BalconyShared` tests; apps are compiled, never tested). *(Infra audit #2; STATE.md:57.)*
- [ ] **D2. Add a `Package.swift` + tests for BalconyCLI** — it has no build manifest and zero tests today, yet holds the riskiest systems code. Start with `SocketClient` frame parser (partial frames, length prefixing, `:288-303`). *(Shared/CLI audit #9.)*
- [ ] **D3. Cover the highest-risk Mac logic** — `FrameParser.drain` (`PTYSessionManager.swift:499-552`, near-pure), `HookEventHandler` idle-prompt/Stop↔Notification state machine (`:252-368`), `SetupManager.patchHooks` (mutates the user's real `settings.json`, `:202-288`). *(Mac audit #6.)*
- [ ] **D4. Cover the highest-risk iOS logic** — `PromptDetector` (pure, gates safety-relevant confirmations) and golden-file tests for `HeadlessTerminalParser` fed recorded PTY byte streams. *(iOS audit #4.)*
- [ ] **D5. Fill BalconyShared gaps** — `IdlePromptInfo.detectedOptions` (`HookEvent.swift:262-329`), `AskUserQuestionInfo.from` (`:399-433`), `AwayStatus.computeStatus` — the last also has a **logic bug**: the `awayThreshold` idle branch is dead so high idle can never yield `.away` (`AwayStatus.swift:53-56`); fix + test. *(Shared/CLI audit #7/#8.)*

---

## Phase E — iOS correctness, reconnection & UX (HIGH / MEDIUM)

- [ ] **E1. Collapse the dual reconnect paths** (HIGH) — `WebSocketClient.scheduleReconnect` reconnects the socket *without re-handshaking* (`:207-251`) while `ConnectionManager.handleUnexpectedDisconnect` runs its own full loop (`:334-405`) and suppresses the former on a later MainActor hop; a lost race yields a socket the Mac treats as unauthenticated → flapping. Keep one authenticated reconnect path. *(iOS audit #2.)*
- [ ] **E2. Surface cert-pin failure as a security error, not a 10s timeout** (MEDIUM) — pinning fails closed correctly, but `establishConnection` sets `isConnected = true` before TLS validates (`WebSocketClient.swift:159`), so a mismatch surfaces ~10s later as a generic "make sure BalconyMac is running" (`ConnectionManager.swift:198,618`). Report the rejection distinctly. *(iOS audit #3.)*
- [ ] **E3. Don't let sends fail silently while disconnected** (MEDIUM) — `SessionManager.sendInput` (`:262-278`) swallows the throw and the optimistic bubble (`:672-679`) never resolves. Surface an error + mark the bubble failed/retryable. *(iOS audit #7.)*
- [ ] **E4. Proactive reconnect on foreground + network changes** (MEDIUM) — no foreground auto-reconnect and no `NWPathMonitor` (`BalconyiOSApp.swift:40-56`); a QR-paired device is pinned to a fixed `host:port` (`ConnectionManager.swift:396-399`) invalid after a network change. Reconnect on `.active` and on path change; re-resolve via Bonjour. *(iOS audit #9.)*
- [ ] **E5. Fix Live Activity classification + freeze** (MEDIUM) — `syncLiveActivity` buckets `.completed`/`.error` as "Working" (`SessionManager.swift:461-484`); `pushType: nil` freezes counts when suspended (`LiveActivityManager.swift:66`). Fix bucketing now; the push side depends on Phase G. *(iOS audit #8.)*
- [ ] **E6. QR / camera failure states** (MEDIUM) — malformed/expired QR, bad `balcony://pair` URL, and capture-setup failure all no-op silently (`QRScannerView.swift:194-199,159-163`; `DiscoveryView.swift:296-304`) → black screen / dead scanner. Add user-visible failure feedback; move `captureSession.stopRunning()` off the `.main` metadata queue (`:203`). *(iOS audit #6.)*
- [ ] **E7. iOS terminal surfaces (PLAN_03 H, still open)** — H1 iOS never sends `terminalResize`; H2 first-reply auto-scroll; H3 transcript freezes past ~2000 rows. Needs on-device iteration. *(iOS audit §6; STATE.md.)*
- [ ] **E8. Locale/version-proof the heuristics** (MEDIUM) — parser/prompt detection keys on exact English strings + glyphs (`HeadlessTerminalParser.swift:607-626`, `ConversationView.swift:763-808`); breaks on Claude Code wording changes or non-English. Centralize the markers and add a fallback. *(iOS audit #6.)*

---

## Phase F — Dead code & god-object decomposition (MEDIUM)

- [ ] **F1. Delete iOS dead rendering pipeline** (~500 LOC) — `TerminalLineView` and the whole PTY-grouping path in `ConversationView.swift:649-1159` (`computeGroupedBlocks`, `stripAskUserQuestionTUI`, `buildStyledText`, etc.) are unused; the view renders from `transcriptEvents`. Remove, plus the orphaned `TranscriptMessageList` view and `BLECentral.connectedPeripheral`. *(iOS audit #5.)*
- [ ] **F2. Remove Mac dead/half-built code** — `StatusItemManager` (empty), unreferenced `QRCodePairingView`, unused `import UserNotifications`, and finish or delete the stubbed connect/disconnect desktop notification (`ConnectionManager.swift:136-138`). *(Mac audit #9.)*
- [ ] **F3. Decompose the god objects** (MEDIUM, enables testing) — Mac `AppDelegate` (941 LOC) and `ConnectionManager` (875 LOC); iOS `ConversationView` (1319 LOC) and `SessionManager` (887 LOC). Extract keystroke-diff/bracketed-paste and reconnect logic into testable types. Do opportunistically alongside Phase D. *(Mac audit #5; iOS audit #5.)*
- [ ] **F4. Convention cleanup** (LOW) — migrate remaining `ObservableObject` → `@Observable`; fix the `assign(to:on:)` retain cycles (`SessionManager.swift:203-217`); one-type-per-file where cheap; no-op ternary `TranscriptMessageList.swift:190`; `sending` never reset (`PromptOverlayView.swift:198,287`).

---

## Phase G — Cloud relay redesign (was PLAN_01, now invalidated)

- [ ] **G1. Redesign the relay premise** — PLAN_01's "zero-knowledge relay reusing the X25519/XChaCha20 layer" no longer holds; app-layer ciphertext was removed in the TLS refactor. Decide the new trust model (relay sees TLS-terminated traffic, or re-introduce an app-layer envelope for off-LAN). Resolve the 4 open infra decisions (push provider, auth, payload scope, hosting). *(Infra audit #5.)*
- [ ] **G2. Implement or clearly park the Supabase backend** — all three edge functions (`relay-message`, `send-push`, `cleanup`) are `501` stubs; `relay_messages` has RLS enabled with **no policy** (denies all access). Either implement behind G1 or mark the directory explicitly experimental. *(Infra audit #4.)*
- [ ] **G3. Live Activity push** — replace `pushType: nil` once a push provider exists (unblocks E5's freeze).

---

## Phase H — Docs, tracking & repo hygiene (MEDIUM)

- [ ] **H1. Fix the README security claim** (MEDIUM, misleading) — README:32 advertises libsodium X25519 + XChaCha20-Poly1305 E2E; that stack was deleted 2026-06-22. Rewrite to TLS (`wss`) + SHA-256 cert pinning to match CLAUDE.md/`TLSIdentity.swift`. *(Infra audit #1.)*
- [ ] **H2. Add LICENSE + SECURITY.md + CONTRIBUTING.md** — none exist; a publicly distributed repo (Homebrew tap + App Store) defaults to all-rights-reserved with no contributor grant. *(Infra audit #7.)*
- [ ] **H3. Add an architecture + wire-protocol spec** — the pairing flow, message schema, framing, and hook socket protocol live only in code/plan docs. *(Infra audit #7.)*
- [ ] **H4. Correct platform/toolchain docs** — README says iOS 16+/Xcode 15+, CLAUDE.md/`project.yml xcodeVersion` say 15.0, but the iOS target is **26.0 / needs Xcode 26**. *(Infra audit #8.)*
- [ ] **H5. Refresh STATE.md + prune branches** — STATE.md (2026-06-19) says PLAN_03 is unmerged on `polish/deep-audit-fixes` with "clean main"; that branch is **fully merged** (verified by patch-id) and main is 12 releases ahead. Mark PLAN_03 done, PLAN_01 as needing redesign, add this plan, and delete the ~6 merged local/remote branches. *(Infra audit #4.)*
- [ ] **H6. Commit `Package.resolved`, add lint** — `Package.resolved` is git-ignored while all SPM deps use `from:` ranges → non-reproducible CI/release builds; commit it. Add SwiftLint/SwiftFormat + a CI step. Remove dead `exportOptions-*.plist`; stop committing the xcodegen-generated `project.pbxproj`. *(Infra audit #3/#9/#10.)*

---

## Phase I — iOS product gaps (LOW, scoped subset of PLAN_02)

- [ ] **I1. Dynamic Type** — all fonts are fixed point sizes (`BalconyTheme.monoFont(15)`), no scaling. *(iOS audit #10.)*
- [ ] **I2. Reduce Motion on the remaining pulses** — several `repeatForever` animations ignore it (`SidebarActivityDot:611-628`, `statusDot:350-367`, `ReconnectingOverlay:183-186`). *(iOS audit #10.)*
- [ ] **I3. Fix misleading "Reset Encryption Keys" copy** (`SettingsView.swift:84,102`) — there are no app-managed keys; it clears paired devices/pins. *(iOS audit #3.)*
- [ ] **I4. iPad layout** — remains deferred (hand-rolled overlay sidebar, no size-class/split-view); track but don't schedule.

---

## Suggested sequencing

1. **Phase A** (security) — alone, first, ship Mac + iOS together.
2. **Phase D** (test targets) — unblocks A4/B4 and guards everything after.
3. **Phase B + C** (protocol + concurrency) — the correctness core.
4. **Phase E + F** (iOS UX + dead code) — user-facing polish + shrink the god objects.
5. **Phase H** (docs/hygiene) — cheap, do continuously.
6. **Phase G** (relay) and **Phase I** (product gaps) — larger/optional, schedule after the above.

## Severity index (quick reference)

- **Critical**: A1.
- **High**: A2, A3, B1, B2, C1, C2, C3, C7, D1, D3, D4, E1.
- **Medium**: A5, B3, B4, C4, C5, C6, D2, D5, E2–E8, F3, G1, G2, H1–H4.
- **Low**: B5, C8, F1, F2, F4, H5, H6, I1–I4.
