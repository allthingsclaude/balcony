# Plan: IOS_POLISH

**Created**: 2026-06-11
**Status**: Draft (from 5-lens UX/UI/performance audit)

Make BalconyiOS award-level: ProMotion-fluid under heavy terminal streaming, signature-quality interactions on the native prompt surfaces, trustworthy connection lifecycle, and systematic design/accessibility quality.

Audit lenses: core terminal experience, native cards/pickers, app shell & navigation, design system & accessibility, rendering performance. Findings below are verified against code with file:line references.

---

## Current Strengths (do not regress)

- Live keystroke streaming with echo cancellation (`ConversationView.swift:468-490`)
- Smart auto-scroll: sentinel-based near-bottom detection, respects reading position (`ConversationView.swift:41-44,147-158`)
- 24 well-placed haptics; full dark/light semantic color theming; dual app icons; custom launch screen
- Sophisticated parser: code-block detection, marker classification, soft-wrap joining (`HeadlessTerminalParser.swift:74-393`)
- Existing 50ms/400ms parse debounce (good starting point)

---

## Phase 1: Fluidity Foundation (highest frame-time payoff) ✅ (2026-06-11)

The app dropped frames during fast output (>10KB/s): every PTY chunk batch triggered a full-array `@Published` replacement on `SessionManager`, re-rendering the entire view tree.

1. [x] **Per-property observation** — implemented via `@Observable` migration of `SessionManager` (cleaner than the child-object split, enabled by the iOS 26 floor): views re-render only for properties they read.
2. [x] **Memoize per-line rendering** — `TerminalLine`/`StyledSegment` content equality (ignoring regenerated UUIDs) + `TerminalLineView: Equatable` with `.equatable()`; unchanged lines skip body re-eval.
3. [x] **Update coalescing** — change-gated publishes (skip when lines/prompt/input unchanged; also fixed a race where hook enrichment was wiped by no-change `nil` re-emissions); `maxDelay` 400ms → 150ms for livelier streaming. CADisplayLink alignment deliberately skipped — debounce already bounds rate; revisit only if on-device profiling shows need.
4. [x] **ANSI color cache** — memoized; theme entries are dynamic UIColors so no invalidation needed.
5. [ ] **Dirty-region line updates (stretch)** — not needed unless profiling shows `groupedBlocks` (O(N) per update) matters after the above.

## Phase 2: Terminal Experience Gaps ✅ (2026-06-11)

1. [x] **Copy / share** — long-press context menu on every line: Copy Line, Copy Message (walks to the containing ❯/⏺ marker block), Share Message; Copy Block on code blocks/tables.
2. [x] **Multiline input** — `TextField(axis: .vertical)` + `.lineLimit(1...5)` + `.submitLabel(.send)` (return still sends; newlines arrive via paste). Multiline content reaching the PTY is wrapped in bracketed-paste sequences so the terminal preserves newlines instead of submitting at each one.
3. [x] **Autocorrect policy** — off by default (autocapitalization too), `input.autocorrect` toggle in Settings ▸ Input. The b506235 revert bundled unrelated text-extraction changes; the toggle de-risks re-enabling.
4. [x] **ESC ergonomics** — 44pt hit target, instant single-tap ESC + medium haptic (no double-tap latency); rewind moved to long-press. Kept in the toolbar.
5. [x] **Slash/@ false positives** — shared `menuQuery(trigger:)` requires start-of-word; `path/to/file` and `user@host` no longer open menus; the "/" button inserts a leading space mid-word so it still triggers.
6. [x] **Stale-reads-as-stale** — conversation dims (opacity 0.8 + desaturation) while disconnected, instead of per-spinner timestamps (which would have broken the Equatable line memoization from Phase 1).
7. [x] **Code block scroll affordance** — `showsIndicators: true` on horizontal code-block scroll.
8. [x] **Dim/ANSI contrast** — dim opacity 0.6 → 0.7; ANSI base colors 1–6 now trait-adaptive (brightened on dark; the classic 0.67-channel values were below readable contrast).
9. [ ] **Paste progress indicator** — deferred: transmission batching already exists Mac-side (v0.1.21–25 backpressure work); a "Pasting…" badge is cosmetic and can ride along with a later phase.

## Phase 3: Signature Moments (prompt surfaces) ✅ (2026-06-11)

1. [x] **Haptic on prompt arrival** — presence-keyed `onChange` in ConversationView fires `hapticMedium()` when a permission prompt or question appears (content changes within an active prompt don't re-fire).
2. [x] **Spring entrance choreography** — root-caused deeper than the audit: the declared `.transition`s had **no animation driver at all** (prompt state is assigned outside `withAnimation`), so cards popped in with zero animation. Added presence-keyed `.animation(BalconyTheme.springStandard, value:)` drivers; unified PromptOverlay on the `.menuPanel` (move+fade+blur) transition. `IdlePromptCard` was dead code (defined, never instantiated) — removed.
3. [x] **Destructive affordance** — destructive fill 0.15 → 0.22 + dedicated red stroke border.
4. [x] **Wizard polish** — animated progress bar, back navigation (chevron when past step 1), 160ms selection flash with double-tap guard, "Other" field gets auto-focus + `.textInputAutocapitalization(.never)` + `.autocorrectionDisabled()`.
5. [x] **Multi-option selection indicator** — accent fill (8%) on the selected row alongside the bar.
6. [x] **`MenuBlurModifier` compatibility** — moot since the iOS 26 floor.

Also seeded the Phase 6 motion vocabulary early: `BalconyTheme.springSnappy/springStandard/springGentle`.

## Phase 4: Pickers & Menus Consistency

1. [ ] **Extract shared picker scaffold** — Model/Session/Rewind pickers duplicate drag handle, gesture, background (~100 LOC drift already: icon 28×28 vs 24×24, hardcoded radius 8, maxHeight 280 vs 320).
2. [ ] **Selection indicators** — Session/Rewind pickers show no current selection (Model picker does); unify on checkmark + subtle fill.
3. [ ] **Empty states for menus** — Slash/File menus return `EmptyView()` on zero matches; show "No matches" row instead.
4. [ ] **Search parity** — only SessionPicker has search; add to Rewind (by preview text), consider Model.
5. [ ] **Unify dimensions** — icons 24×24, row padding 12×10, maxHeight 320 everywhere.

## Phase 5: Connection Lifecycle Trust ✅ (2026-06-11)

Root-caused deeper than the audit: on an unexpected drop the app ejected the user to discovery (`ContentView` flipped on `isConnected`), the transport-level WebSocket auto-reconnect couldn't restore the E2E session anyway (no re-handshake), and its give-up path re-signaled "unexpected" — leaving `isReconnecting` true forever.

1. [x] **Session-level reconnect loop** — `ConnectionManager.startSessionReconnect()`: full reconnect (handshake included) with exponential backoff, 5 attempts; transport-level socket retries are stopped on drop since they can't restore E2E. Gives up cleanly → UI falls back to discovery where Bonjour auto-connect takes over.
2. [x] **Stay in the session during drops** — unexpected disconnects keep the session view mounted (dimmed conversation + banner); only deliberate disconnect or abandoned reconnection returns to discovery. `isReconnecting` is set before any suspension point so the UI never races to discovery.
3. [x] **Retry affordances** — Retry button on the connection banner (`reconnectNow()`, preserves `connectedDevice` on failure), Retry Now added to the now-rare reconnecting overlay, success haptic on restore.
4. [x] **Discovery timeout** — after 20s with no devices, the how-it-works cards swap for a troubleshooting checklist (Mac running, same Wi-Fi, **Local Network permission** — the usual culprit, hotspot/VPN) + QR fallback CTA. Resets when a device appears.
5. [x] **Session restoration** — `lastSelectedSessionId` in `@AppStorage`; restored on launch/reconnect when the session still exists.
6. [x] **Notification toggles wired** — `notify.toolApprovals` gates attention notifications, `notify.sessionComplete` gates done notifications; dead "Session Events" toggle removed; footnote explains the sidebar master switch (auto-arms on away).
7. [x] **Exponential backoff** — already existed at the transport layer (audit miss); the new session-level loop uses its own capped backoff.
8. [x] **Scene phase** — Bonjour/BLE discovery stops in background when disconnected, resumes on active.

Also from this phase's investigation: `TerminalContainerView`, `SessionListView`, `SessionCardView` were dead pre-sidebar code — removed (commit c710245).

## Phase 6: Design System & Accessibility

1. [ ] **Animation vocabulary in theme** — 31 animation blocks with ad-hoc curves; define `BalconyTheme.snappy/standard/gentle` springs and migrate; respect `accessibilityReduceMotion` centrally (currently 2/31).
2. [ ] **Type scale** — 53 ad-hoc `.system(size:)` across 15 sizes; consolidate to theme font functions; user-adjustable mono size for terminal (`@AppStorage`).
3. [ ] **Dynamic Type** — zero support today; adopt relative sizing or cap with `.dynamicTypeSize(...)`; audit fixed frames.
4. [ ] **Hardcoded colors** — 7 violations (`.white` ×6, `.blue` hyperlink in `PromptOverlayView.swift:301`); add overlay/shadow tokens.
5. [ ] **VoiceOver** — label icon-only buttons in menus/pickers; add hints to prompt actions; verify terminal line accessibility text.
6. [ ] **Spacing scale cleanup** — ~15 magic paddings (e.g. `.padding(.bottom, 120)`) → tokens or derived values.

## Phase 7: Award-Level Delights (after foundations)

1. [ ] Per-session Live Activity (named project, not aggregate counts) — pairs with PLAN_01 push
2. [ ] Foreground notification banner (currently suppressed entirely → sound only)
3. [ ] Per-session notification muting (long-press sidebar row)
4. [ ] Swipe actions on session rows; app icon badge count
5. [ ] iPad layout (`NavigationSplitView` / size-class aware sidebar — currently fixed 69% drawer)
6. [ ] `matchedGeometryEffect` session card → terminal transition; `.contentTransition(.numericText())` on counters (iOS 17)
7. [ ] Deep link to session on cold launch from notification

---

## Strategic note: iOS 17 floor

Deployment target is 16.0. Several high-value APIs need 17+ (`scrollPosition(id:)`, `.sensoryFeedback`, `contentTransition` symbol/numeric effects, `ContentUnavailableView`). Worth deciding early whether to raise the floor to 17 (simplifies Phases 1–3) or availability-gate.

## Suggested order

Phase 1 first (fluidity is the multiplier — everything else feels better at 120Hz), then 3 (signature moments) → 2 → 5 → 4 → 6 → 7. Phases 2–6 items are largely independent and parallelizable.

---

**Last Updated**: 2026-06-11
**Generated By**: 5-agent UX/UI/perf audit
