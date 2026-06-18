# State

**Active**: PLAN_03_AUDIT_HARDENING — 8 commits on branch `polish/deep-audit-fixes` (Phases A/B/C/D/E/F-core/J shipped; G/H/I + plan-tier remain)
**Updated**: 2026-06-19

---

## Overview

| # | Plan | File | Status | Progress |
|---|------|------|--------|----------|
| 00 | PROMPT_ROUTING | PLAN_00_PROMPT_ROUTING.md | ✅ Complete | 17/17 tasks (+ Phase 6 implemented despite "future" label) |
| 01 | CLOUD_RELAY | PLAN_01_CLOUD_RELAY.md | 📝 Draft | Needs 4 infrastructure decisions before kickoff |
| 02 | IOS_POLISH | PLAN_02_IOS_POLISH.md | 📝 Draft | 7 phases from 5-lens UX/UI/perf audit (2026-06-11); Phase 1 = fluidity fixes |
| 03 | AUDIT_HARDENING | PLAN_03_AUDIT_HARDENING.md | 🔄 In progress | 128 findings from 15-subsystem deep audit (2026-06-19); fixed critical crypto nonce-reuse + LAN input-injection + 25 more across crypto/CLI/hooks/setup/session-data/models. Branch `polish/deep-audit-fixes`. |

---

## Plans

### PLAN_00_PROMPT_ROUTING ✅ Complete

Shipped between 2026-02-26 and 2026-03-24, polished through v0.1.25 (2026-04-29). Status audit on 2026-06-11 verified every task against code. Summary:

| Phase | Status | Notes |
|-------|--------|-------|
| 1: Hook Listener Infrastructure | ✅ | `HookListener`/`HookEventHandler` (BalconyMac/Sources/Hooks/), `HookEvent`/`HookEventPayload` (BalconyShared), `Scripts/hook-handler`, auto-setup via `SetupManager.patchHooks()` first-launch wizard |
| 2: Mac Prompt Panel UI | ✅ | `PromptPanelController`/`PromptPanelView` + beyond plan: "Always" button, keyboard shortcuts, double-Cmd hotkey, focus-terminal action, sounds, markdown rendering, appearance prefs |
| 3: iOS Prompt Enrichment | ✅ | `SessionManager.pendingHookData`, enriched `PromptOverlayView` (tool icon, command preview, risk badge), wired through `TerminalContainerView`/`ConversationView` |
| 4: Coordination & Lifecycle | ✅ | `PromptLifecycleState` machine, per-session FIFO `SessionPromptQueue`, timing-mismatch buffering, reconnect resync (`resendPendingHookEvent` et al.) |
| 5: PromptDetector Improvements | ✅ | Evaluated as planned: stays iOS-only; Mac dismisses via 200-byte PTY-output heuristic |
| 6: Consult Questions (was "Future") | ✅ | Implemented: idle prompts (Stop+Notification correlation, detected-options parsing), `AskUserQuestionCardView` (iOS) + Mac wizard panel, voice input (Cmd-hold) |

### PLAN_01_CLOUD_RELAY 📝 Draft

Remote access (off-LAN) via zero-knowledge Supabase relay + APNs push, including background Live Activity updates. Blocked on four decisions documented in the plan: push provider (APNs vs FCM), auth model, relay payload scope, hosting/secrets.

---

## Backlog

Resolved in the 2026-06-11 cleanup session (see git history):
- ~~Sparkle appcast~~ — **was a false alarm**: the live feed on the `gh-pages` branch is current through v0.1.25 with EdDSA signatures; `release.yml` updates it on every tag. Removed the stale, empty `docs/appcast.xml` duplicate from main that caused the confusion.
- ~~No README~~ — root `README.md` added (install, pairing, hook setup, build from source, troubleshooting).
- ~~MessageType test coverage~~ — round-trip tests now iterate `MessageType.allCases` (CaseIterable added), so new cases are covered automatically; added `BLERSSIReportPayload` round-trip.
- ~~Hardcoded 0.1.0 in iOS Settings~~ — now reads `CFBundleShortVersionString` from the bundle.
- ~~Dead protocol surface~~ — removed `.awayStatusUpdate` and `.sessionUpdate` cases, the unreachable iOS `handleSessionUpdate`, and both duplicated `SessionUpdatePayload` structs. `.error` kept, documented as reserved.
- ~~hook-handler debug log~~ — now opt-in via `BALCONY_HOOK_DEBUG=1`.

From the 2026-06-19 deep audit (PLAN_03), 2 findings were **rejected** by the verify pass as false positives:
- ~~ISO8601 date drops fractional seconds~~ — the `Date+ISO8601` helpers are dead code (zero non-test callers); transcript timestamps are parsed via `TranscriptParser`, which handles fractional seconds correctly.
- ~~release.sh never bumps CFBundleVersion~~ — the shipped build comes from CI (`release.yml`), which sets `CFBundleVersion` to `git rev-list --count HEAD` (strictly increasing); `release.sh` isn't the authoritative path.

Still open:
- **Cloud relay + Live Activity push** → PLAN_01_CLOUD_RELAY (draft)
- **PLAN_03 remainder** — Phase C1 (hook FD leak), H1–H3 (iOS resize/scroll/scrollback), G2 (panel live-typing), F3, and crypto plan-tier (replay protection, MITM pinning). Most need on-device iteration.
- **No test targets for BalconyMac / BalconyiOS** — only BalconySharedTests exists. The dense hook/PTY-session-mapping logic in `AppDelegate` is the riskiest untested area; would need extracting from AppDelegate into testable types first.
