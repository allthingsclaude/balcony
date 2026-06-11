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

## Phase 1: Fluidity Foundation (highest frame-time payoff)

The app currently drops frames during fast output (>10KB/s): every PTY chunk batch triggers a full-array `@Published` replacement on `SessionManager`, re-rendering the entire view tree (~30 full re-evals/sec at burst; ~150k uncached ANSI color lookups/sec).

1. [ ] **Isolate hot terminal state into a child ObservableObject** — move `conversationLines`, `activePrompt`, `pendingInputText` out of `SessionManager` into a `TerminalContentManager`; only `ConversationView` observes it. Single biggest win — restores 120Hz during streaming. (`SessionManager.swift:16,118-120`, `TerminalContainerView.swift:26`)
2. [ ] **Memoize per-line text construction** — make `StyledSegment` Equatable (text+style, ignore UUID), cache built `Text` per line; skip rebuild when segments unchanged. (`ConversationView.swift:999-1012`, `TerminalLine.swift`)
3. [ ] **Display-link-aligned update coalescing** — align `extractLines()` firing to CADisplayLink instead of wall-clock `asyncAfter`; keep the 50ms quiet window. (`HeadlessTerminalParser.swift:54-70`)
4. [ ] **ANSI color cache** — static `[ANSIColor: Color]` dict, cleared on theme change. (`ANSIColorMapper.swift:6-33`)
5. [ ] **Dirty-region line updates (stretch)** — mark "last N lines changed" so `groupedBlocks` (O(N) per update, `ConversationView.swift:674-705`) invalidates only affected blocks.

## Phase 2: Terminal Experience Gaps

1. [ ] **Text selection / copy** — terminal output is currently uncopyable (0 `.textSelection` in app). Add long-press context menu (Copy line / Copy block / Share) on `TerminalLineView`; `.textSelection(.enabled)` where feasible. (`ConversationView.swift:764-815`)
2. [ ] **Multiline input** — `TextField` never grows; pasted/long prompts unreadable. Use iOS 16 `TextField(axis: .vertical)` with `.lineLimit(1...6)`. (`ConversationView.swift:355-375`)
3. [ ] **Autocorrect policy** — currently default-on (a disable was tried and reverted in b506235). Decide deliberately: `.autocorrectionDisabled()` + `.textInputAutocapitalization(.never)` with a Settings toggle.
4. [ ] **ESC ergonomics** — `EscButton` is 30×30 (below 44pt target) in top-right with double-tap latency. Make hit target ≥44pt, consider input-bar placement, instant single-tap + medium haptic. (`EscButton.swift:33`, `TerminalContainerView.swift:125-133`)
5. [ ] **Paste feedback + batching** — large pastes stream as raw keystrokes with no feedback; show transient "Pasting…" indicator and chunk transmission. (`ConversationView.swift:469-490`)
6. [ ] **Slash/@ false positives** — typing `path/to/file` opens the slash menu; require start-of-line or preceding whitespace. (`ConversationView.swift:368-372`)
7. [ ] **Stale spinner handling** — frozen status lines after disconnect look like hangs; dim + badge spinner rows not updated for >30s. (`ConversationView.swift:819-834`)
8. [ ] **Code block scroll affordance** — horizontal scroll is invisible; add `.scrollIndicators(.visible)` / edge hint. (`ConversationView.swift:127-139`)
9. [ ] **Dim/ANSI contrast** — dim opacity 0.6 too low; some ANSI colors (red 0.67/0/0) illegible on dark; theme-aware palette + `BalconyTheme.dimOpacity`. (`ANSIColorMapper.swift:25-77`)

## Phase 3: Signature Moments (prompt surfaces)

1. [ ] **Haptic on prompt arrival** — THE attention moment currently has no haptic; fire `hapticMedium()` when `activePrompt`/`pendingHookData`/question becomes non-nil (guard against re-fire).
2. [ ] **Spring entrance choreography** — cards use linear `.move+.opacity`; add spring animation to PromptOverlay, AskUserQuestion card, and `.menuPanel` transition; add missing entrance transition to IdlePromptCard (`PromptOverlayView.swift:293-332`).
3. [ ] **Destructive affordance** — Deny/destructive buttons at `statusRed.opacity(0.15)` are under-emphasized at the riskiest moment; strengthen bg, consider warning glyph for `destructive` risk level. (`PromptOverlayView.swift:38-65,167-168`)
4. [ ] **Wizard polish** — AskUserQuestion: add progress bar, back navigation between steps, selection flash before advancing, `.textInputAutocapitalization(.never)` on "Other" field. (`AskUserQuestionCardView.swift`)
5. [ ] **Multi-option selection indicator** — 3pt bar too subtle; use accent background fill on selected row. (`PromptOverlayView.swift:239-241`)
6. [ ] **Verify `MenuBlurModifier` iOS 16 compatibility** (`ConversationView.swift:1017-1033`).

## Phase 4: Pickers & Menus Consistency

1. [ ] **Extract shared picker scaffold** — Model/Session/Rewind pickers duplicate drag handle, gesture, background (~100 LOC drift already: icon 28×28 vs 24×24, hardcoded radius 8, maxHeight 280 vs 320).
2. [ ] **Selection indicators** — Session/Rewind pickers show no current selection (Model picker does); unify on checkmark + subtle fill.
3. [ ] **Empty states for menus** — Slash/File menus return `EmptyView()` on zero matches; show "No matches" row instead.
4. [ ] **Search parity** — only SessionPicker has search; add to Rewind (by preview text), consider Model.
5. [ ] **Unify dimensions** — icons 24×24, row padding 12×10, maxHeight 320 everywhere.

## Phase 5: Connection Lifecycle Trust

1. [ ] **Reconnect button on the connection-lost banner** + success haptic on restore. (`SidebarContainerView.swift:314-339`)
2. [ ] **Non-blocking reconnect overlay** — full-screen "Reconnecting…" currently traps the user (only Disconnect). Make dismissible / inline. (`BalconyiOSApp.swift:141-192`)
3. [ ] **Discovery timeout state** — discovery spins forever on isolated networks; after ~20s show troubleshooting card (Mac running? same Wi-Fi? firewall?) + QR fallback CTA. (`DiscoveryView.swift`)
4. [ ] **Session restoration** — `@AppStorage` last selected session; auto-reopen on launch when still present. (`SidebarContainerView.swift:119-125`)
5. [ ] **Fix orphaned notification toggles** — Settings defines `notify.sessionEvents/toolApprovals/sessionComplete` but `SessionManager` never reads them. Wire or remove. (`SettingsView.swift:6-8`, `SessionManager.swift:432`)
6. [ ] **Exponential backoff** for reconnect attempts (battery).
7. [ ] **Scene phase handling** — no `\.scenePhase` usage anywhere; pause discovery/BLE appropriately in background.

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
