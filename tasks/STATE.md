# State

**Active**: 00_PROMPT_ROUTING
**File**: tasks/plans/PLAN_00_PROMPT_ROUTING.md
**Phase**: 1
**Status**: 🚧 In Progress
**Updated**: 2026-02-26T12:00:00Z

---

## Overview

| # | Plan | File | Status | Progress |
|---|------|------|--------|----------|
| 00 | PROMPT_ROUTING | PLAN_00_PROMPT_ROUTING.md | 🚧 In Progress | 0/17 tasks |

---

## Plans

### PLAN_00_PROMPT_ROUTING

#### Phase 1: Hook Listener Infrastructure 🚧

| Task | Status |
|------|--------|
| Create `HookEvent` model in BalconyShared | ⏳ |
| Add `hookEvent` and `hookDismiss` to `MessageType` | ⏳ |
| Create `HookListener` actor in BalconyMac | ⏳ |
| Create `HookEventHandler` in BalconyMac | ⏳ |
| Wire `HookListener` into `AppDelegate` | ⏳ |
| Create hook handler script | ⏳ |
| Document Claude Code hook configuration | ⏳ |

#### Phase 2: BalconyMac Prompt Panel UI ⏳

| Task | Status |
|------|--------|
| Create `PromptPanelController` | ⏳ |
| Create `PromptPanelView` (SwiftUI) | ⏳ |
| Wire panel to `HookEventHandler` | ⏳ |
| Implement PTY output monitoring for auto-dismiss | ⏳ |
| Register NSPanel as a secondary window | ⏳ |

#### Phase 3: iOS Prompt Enrichment ⏳

| Task | Status |
|------|--------|
| Forward hook events to iOS via WebSocket | ⏳ |
| Handle hook events in iOS `SessionManager` | ⏳ |
| Add hook metadata to `InteractivePrompt` | ⏳ |
| Enhance `PromptOverlayView` with hook data | ⏳ |
| Wire enriched overlay in `TerminalContainerView` | ⏳ |

#### Phase 4: Coordination & Lifecycle ⏳

| Task | Status |
|------|--------|
| Implement prompt lifecycle state machine | ⏳ |
| Multi-prompt queue | ⏳ |
| Handle timing mismatches | ⏳ |
| Connection loss handling | ⏳ |

#### Phase 5: PromptDetector Improvements (Shared) ⏳

| Task | Status |
|------|--------|
| Evaluate moving `PromptDetector` to BalconyShared | ⏳ |
| Add basic prompt-gone detection for Mac PTY monitoring | ⏳ |

#### Phase 6: Consult Questions (Future) ⏳

| Task | Status |
|------|--------|
| Investigate `Stop` and `Notification` hooks | ⏳ |
| Design question detection and response UI | ⏳ |
