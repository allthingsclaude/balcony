# Plan: PROMPT_ROUTING

**Created**: 2026-02-26T12:00:00Z
**Status**: Draft

Route Claude Code's permission prompts and questions to BalconyMac (native floating panel) and BalconyiOS (enriched cards), while keeping the terminal fully functional for responding. The user can respond from any of three places -- terminal, Mac popup, or iOS -- and the first response wins.

---

## Objective

### Problem Statement

When Claude Code needs permission to run a tool (Bash, Edit, Write, Read) or asks the user a question, the only way to respond is by typing in the terminal. If the user is away from their Mac, they see the prompt on iOS via `PromptDetector` + `PromptOverlayView`, but that detection is purely visual (pattern-matching on rendered terminal lines). There is no structured data about what tool is requesting permission, what command it wants to run, or the risk level. On the Mac side, there is no prompt notification at all -- the user must look at the terminal window.

This plan adds a **hook-based pipeline** that delivers structured prompt data alongside the existing PTY-based detection, enabling richer UI on both platforms and allowing response from any device.

### Success Criteria

- [ ] Claude Code `PermissionRequest` hook fires and delivers structured JSON to BalconyMac via a Unix domain socket
- [ ] BalconyMac shows a floating `NSPanel` with tool name, command preview, and action buttons when a permission prompt appears
- [ ] Clicking a button on the Mac panel injects the corresponding keystroke into the PTY and dismisses the panel
- [ ] BalconyiOS `PromptOverlayView` shows enriched information (tool name, command, file path, risk level) when hook data is available
- [ ] Responding from any of the three surfaces (terminal, Mac panel, iOS overlay) dismisses the UI on the other two
- [ ] The system degrades gracefully: if hooks are not configured, existing `PromptDetector`-based behavior works unchanged

---

## Background & Context

### Current State

**PTY data flow**: `BalconyCLI` spawns Claude Code inside a POSIX PTY. Raw PTY output flows through a Unix domain socket (`~/.balcony/pty.sock`) to `BalconyMac`, which forwards it over WebSocket to `BalconyiOS`. iOS uses `HeadlessTerminalParser` (SwiftTerm headless) to parse bytes into `TerminalLine` arrays.

**Prompt detection (iOS only)**: `PromptDetector` scans the tail of parsed terminal lines for two patterns:
1. **Permission prompts** -- inline `(Y)es / (N)o / (A)lways` patterns, producing `PermissionPrompt` with `PermissionOption` items
2. **Multi-option prompts** -- numbered `1. ... / 2. ... / 3. ...` lists with `>` selection indicator, producing `MultiOptionPrompt`

`PromptOverlayView` renders native buttons. Tapping a button sends keystrokes (letter for permission, arrow keys + Enter for multi-option) back through the WebSocket chain to the PTY.

**Mac side**: No prompt UI exists. The menu bar popover is 280pt wide and shows status/devices/sessions. There are no floating windows or panels.

**Existing pattern for native pickers**: `/model`, `/rewind`, `/resume` already use the pattern: iOS detects slash command -> requests data from Mac -> Mac gathers data -> sends structured payload -> iOS shows native picker -> selection injects keystrokes into PTY. This is the proven pattern to extend.

### Why This Matters

1. **Away from keyboard**: The primary Balcony use case is monitoring Claude Code from your phone while away. Permission prompts block progress. Getting structured data makes the iOS UI more trustworthy for approving tools.
2. **Mac desktop notifications**: Even when at the Mac, Claude Code runs in a terminal that may be buried. A floating panel near the menu bar provides immediate awareness and one-click response.
3. **Structured data**: Hook data includes the actual tool name, command text, and parameters -- far more reliable than regex-matching rendered terminal output.
4. **Race-safe**: Because all responses are injected as PTY keystrokes, the terminal is always the single source of truth. No matter where you respond, the behavior is identical.

### Key Findings from Discussion

- Claude Code's `PermissionRequest` hook is **async**, meaning it does not block the terminal prompt. The hook fires alongside the terminal prompt rendering, not before it.
- The hook protocol is simple: Claude Code runs a command, pipes JSON to stdin, and the command runs independently. No stdout response is needed for async hooks.
- The existing Unix domain socket pattern (`pty.sock`) for PTY data can be replicated for hook events (`hooks.sock`), keeping the architecture consistent.
- `PromptDetector` and hook data serve complementary roles: `PromptDetector` tells us WHEN to show the overlay (from PTY output timing), hook data tells us WHAT to show (structured tool/command info).
- Mac's `NSPanel` with `.nonactivatingPanel` style mask is ideal -- it floats above other windows without stealing focus from the terminal.
- All responses flow through `PTYSessionManager.sendInput(sessionId:data:)`, which is already proven and handles multiple concurrent sessions.

---

## Proposed Approach

### High-Level Strategy

Add a second Unix domain socket (`~/.balcony/hooks.sock`) on BalconyMac that listens for hook events from Claude Code. A small hook handler script bridges Claude Code's hook protocol (JSON on stdin) to the socket. When a `PermissionRequest` hook fires, BalconyMac receives structured data about the tool request and can show a native floating panel. The same data is forwarded to iOS via a new `hookEvent` WebSocket message type, enriching the existing `PromptOverlayView`.

Response injection uses the existing PTY keystroke path for all three surfaces. Dismissal uses PTY output monitoring -- when the terminal output changes (prompt disappears), all UIs dismiss automatically.

### Key Technical Decisions

1. **Separate Unix socket for hooks (`hooks.sock`) rather than multiplexing on `pty.sock`**
   - Rationale: Hook events come from a different process (the hook handler script) than PTY data (BalconyCLI). Different lifecycle, different connections. Clean separation.
   - Trade-offs: Two sockets to manage instead of one, but minimal overhead since both use the same `~/.balcony/` directory.

2. **Async hooks (no blocking)**
   - Rationale: Claude Code's `PermissionRequest` hook supports `"async": true`, which means it fires the command but does not wait for it to complete before showing the terminal prompt. This is essential -- we never want to delay the terminal.
   - Trade-offs: Hook data may arrive before or after the PTY prompt renders. Need to handle both orderings.

3. **NSPanel (floating, non-activating) for Mac UI**
   - Rationale: `NSPanel` with `.nonactivatingPanel` style allows the panel to appear without stealing keyboard focus from the terminal. The user can still type in the terminal to respond, and the panel dismisses automatically.
   - Trade-offs: More complex than a simple `NSAlert`, but provides the right UX -- non-intrusive, always visible, one-click action.

4. **PTY output monitoring for dismissal rather than a "response acknowledged" hook**
   - Rationale: There is no reliable hook that fires when the user responds to a permission prompt. But the PTY output changes immediately when the prompt is answered (the prompt text disappears and Claude Code continues). Monitoring PTY output is reliable and platform-agnostic.
   - Trade-offs: Requires some heuristic to detect "prompt has been answered" vs "more output appeared." The simplest approach: run `PromptDetector` on Mac side and dismiss when no prompt is detected.

### Alternative Approaches Considered

- **MCP-based communication**: Would require Claude Code to run an MCP server for prompt data. Overly complex, and hooks already provide the data we need without any protocol overhead.
- **Polling JSONL session files for prompt state**: Session files lag behind real-time terminal state. Hook events are immediate.
- **Single socket with message type multiplexing**: Would require changes to BalconyCLI framing protocol. Hooks come from a separate process anyway.
- **macOS UserNotifications for prompts**: Too passive -- notifications can be missed, don't support inline action buttons well, and can't show command previews.

---

## Implementation Plan

### Phase 1: Hook Listener Infrastructure

**Goal**: BalconyMac can receive and parse hook events from Claude Code via a Unix domain socket.

**Tasks**:
1. [ ] **Create `HookEvent` model in BalconyShared**
   - File(s): `BalconyShared/Sources/BalconyShared/Models/HookEvent.swift`
   - Details: Define `HookEvent` struct matching Claude Code's hook JSON schema. Fields: `hookEventName` (String), `sessionId` (String), `toolName` (String?), `toolInput` (JSON-compatible dict). Add `PermissionPromptInfo` as a parsed convenience: `toolName`, `command` (for Bash), `filePath` (for file ops), `parameters` dictionary, computed `riskLevel` (normal/elevated/destructive based on command content).
   - Estimated effort: Small

2. [ ] **Add `hookEvent` and `hookDismiss` to `MessageType`**
   - File(s): `BalconyShared/Sources/BalconyShared/Protocol/MessageType.swift`
   - Details: Add `.hookEvent` (Mac -> iOS: structured hook data) and `.hookDismiss` (Mac -> iOS: prompt was answered, dismiss UI). These are the WebSocket message types for forwarding hook data to iOS clients.
   - Estimated effort: Small

3. [ ] **Create `HookListener` actor in BalconyMac**
   - File(s): `BalconyMac/Sources/Hooks/HookListener.swift`
   - Details: Actor that opens a Unix domain socket at `~/.balcony/hooks.sock`. Each incoming connection = one hook event. Read JSON until EOF, parse into `HookEvent`, close the connection. Uses the same POSIX socket pattern as `PTYSessionManager` (socket/bind/listen/accept via `DispatchSource`). Expose a callback: `onHookEvent: @Sendable (HookEvent) -> Void`.
   - Estimated effort: Medium

4. [ ] **Create `HookEventHandler` in BalconyMac**
   - File(s): `BalconyMac/Sources/Hooks/HookEventHandler.swift`
   - Details: Receives `HookEvent` from `HookListener`, correlates with active PTY sessions (match by `sessionId`), stores as pending prompt, and notifies the UI layer. Manages a queue of pending prompts per session. Provides `pendingPrompt(for sessionId:) -> PermissionPromptInfo?` for the panel to query.
   - Estimated effort: Medium

5. [ ] **Wire `HookListener` into `AppDelegate`**
   - File(s): `BalconyMac/Sources/App/AppDelegate.swift`
   - Details: Instantiate `HookListener` and `HookEventHandler`. Start `HookListener` in `applicationDidFinishLaunching`. Wire `onHookEvent` to `HookEventHandler`. Wire `HookEventHandler` to `ConnectionManager` for iOS forwarding and to `PromptPanelController` (Phase 2) for Mac UI.
   - Estimated effort: Small

6. [ ] **Create hook handler script**
   - File(s): `Scripts/hook-handler`
   - Details: A shell script (or small Swift CLI) that reads JSON from stdin and writes it to `~/.balcony/hooks.sock` via a Unix domain socket connection. For shell: use `socat` or a simple Python/Swift snippet. For robustness, a compiled Swift helper is preferred. Script should be chmod +x and self-contained. Include installation instructions.
   - Estimated effort: Small

7. [ ] **Document Claude Code hook configuration**
   - File(s): `Scripts/README.md` (or inline in plan)
   - Details: The user needs to add hook config to `~/.claude/settings.json` or project-level `.claude/settings.json`:
     ```json
     {
       "hooks": {
         "PermissionRequest": [{
           "type": "command",
           "command": "~/.balcony/hook-handler",
           "async": true
         }]
       }
     }
     ```
   - Estimated effort: Small

**Validation**:
- [ ] Run Claude Code with hooks configured, verify `HookListener` receives and logs parsed `HookEvent` with correct tool name and input
- [ ] Verify that `pty.sock` and `hooks.sock` coexist without conflict in `~/.balcony/`
- [ ] Verify hook handler script works standalone: `echo '{"hookEventName":"PermissionRequest","sessionId":"test"}' | ./Scripts/hook-handler`

### Phase 2: BalconyMac Prompt Panel UI

**Goal**: A floating panel appears on the Mac desktop showing the permission prompt with action buttons. Clicking a button injects the keystroke and dismisses the panel.

**Tasks**:
1. [ ] **Create `PromptPanelController`**
   - File(s): `BalconyMac/Sources/UI/PromptPanel/PromptPanelController.swift`
   - Details: `@MainActor` class that manages an `NSPanel` instance. Panel configuration: `.nonactivatingPanel` style mask (does not steal focus), `.floating` level, positioned near top-right of screen (offset from menu bar). Methods: `showPrompt(_ info: PermissionPromptInfo, sessionId: String)`, `dismissPrompt()`, `dismissPrompt(for sessionId: String)`. On show, creates/updates the panel content. On button click, calls a response handler closure. On dismiss, fades/slides the panel out.
   - Estimated effort: Medium

2. [ ] **Create `PromptPanelView` (SwiftUI)**
   - File(s): `BalconyMac/Sources/UI/PromptPanel/PromptPanelView.swift`
   - Details: SwiftUI view hosted in the NSPanel via `NSHostingView`. Layout:
     - Header: Tool icon (SF Symbol based on tool name) + tool name + risk badge
     - Body: Command preview (monospaced, truncated to ~3 lines) or file path for file ops
     - Footer: Action buttons matching terminal options (Allow, Deny, Allow Always, etc.)
     - Styling: vibrancy material background, rounded corners, shadow. Width ~320pt, height dynamic.
     - Buttons map to response keystrokes: "Allow" -> "y", "Deny" -> "n", "Allow Always" -> "a", etc.
   - Estimated effort: Medium

3. [ ] **Wire panel to `HookEventHandler`**
   - File(s): `BalconyMac/Sources/Hooks/HookEventHandler.swift`, `BalconyMac/Sources/App/AppDelegate.swift`
   - Details: When `HookEventHandler` receives a `PermissionRequest` hook event, call `PromptPanelController.showPrompt()`. When the user clicks a button, call `PTYSessionManager.sendInput()` with the keystroke data, then call `dismissPrompt()`.
   - Estimated effort: Small

4. [ ] **Implement PTY output monitoring for auto-dismiss**
   - File(s): `BalconyMac/Sources/Hooks/HookEventHandler.swift`
   - Details: After showing a prompt panel, monitor PTY output for the corresponding session. When the prompt is answered (either from terminal, Mac panel, or iOS), the PTY output will change -- the prompt text disappears and Claude Code produces new output. Detection approach: buffer the last N bytes of PTY output for the session. When the panel is showing, check each new PTY output chunk. If the buffered content no longer matches the prompt pattern (e.g., the permission line with `(Y)es / (N)o` is gone), dismiss the panel. Alternatively, use a simpler heuristic: if significant new output arrives (more than ~200 bytes) after the panel was shown, dismiss it.
   - Estimated effort: Medium

5. [ ] **Register NSPanel as a secondary window**
   - File(s): `BalconyMac/Sources/App/BalconyMacApp.swift`
   - Details: Since BalconyMac uses `MenuBarExtra` as its primary scene, the `NSPanel` is created programmatically by `PromptPanelController` (not via a SwiftUI `WindowGroup`). No changes to `BalconyMacApp.swift` may be needed -- verify that `NSPanel` can be created and shown from a menu bar app without a `WindowGroup` scene. If needed, add an invisible `Settings` window or use `NSApp.activate()` carefully.
   - Estimated effort: Small

**Validation**:
- [ ] Hook fires -> panel appears near top-right with correct tool name and command
- [ ] Click "Allow" -> keystroke "y" sent to PTY, panel dismisses
- [ ] Type "y" in terminal directly -> panel auto-dismisses within 1 second
- [ ] Panel does not steal keyboard focus from Terminal.app
- [ ] Multiple prompts in sequence: first is shown, after response, next appears

### Phase 3: iOS Prompt Enrichment

**Goal**: When hook data is available, the iOS `PromptOverlayView` shows enriched information (tool name, command, risk level) instead of just the raw button labels from `PromptDetector`.

**Tasks**:
1. [ ] **Forward hook events to iOS via WebSocket**
   - File(s): `BalconyMac/Sources/Connection/ConnectionManager.swift`
   - Details: Add `forwardHookEvent(_ event: HookEvent)` method. Creates a `BalconyMessage` with type `.hookEvent` and the hook event as payload. Sends to all subscribers of the relevant session ID. Also add `forwardHookDismiss(sessionId: String)` for when the prompt is answered.
   - Estimated effort: Small

2. [ ] **Handle hook events in iOS `SessionManager`**
   - File(s): `BalconyiOS/Sources/Session/SessionManager.swift`
   - Details: Add `handleHookEvent(_ message: BalconyMessage)` to the message handler switch. Parse `HookEvent` payload. Store as `@Published var pendingHookData: PermissionPromptInfo?`. When `hookDismiss` is received, clear `pendingHookData`. When `activePrompt` changes to nil (PromptDetector says prompt is gone), also clear `pendingHookData`.
   - Estimated effort: Small

3. [ ] **Add hook metadata to `InteractivePrompt`**
   - File(s): `BalconyiOS/Sources/Views/Terminal/InteractivePrompt.swift`
   - Details: Add an optional `hookData: PermissionPromptInfo?` field to the `InteractivePrompt` enum cases, or add it as a separate property on `SessionManager` that the view reads alongside `activePrompt`. The second approach (separate property) is cleaner since `InteractivePrompt` is produced by `PromptDetector` which has no knowledge of hooks.
   - Estimated effort: Small

4. [ ] **Enhance `PromptOverlayView` with hook data**
   - File(s): `BalconyiOS/Sources/Views/Terminal/PromptOverlayView.swift`
   - Details: Accept an optional `hookData: PermissionPromptInfo?` parameter. When available, render an enriched header above the existing buttons:
     - Tool icon (SF Symbol) + tool name prominently
     - For Bash: show the full command text in a monospaced code block
     - For file ops (Edit, Write, Read): show the file path
     - Risk indicator: green for Read, yellow for Edit/Write, red for Bash commands with `rm`, `sudo`, `chmod`, etc.
     - When `hookData` is nil, fall back to current behavior (buttons only from PromptDetector).
   - Estimated effort: Medium

5. [ ] **Wire enriched overlay in `TerminalContainerView`**
   - File(s): `BalconyiOS/Sources/Views/Terminal/TerminalContainerView.swift`, `BalconyiOS/Sources/Views/Terminal/ConversationView.swift`
   - Details: Pass `sessionManager.pendingHookData` to `PromptOverlayView` (or through `ConversationView` to the overlay). The overlay now has both `activePrompt` (from PromptDetector) and `hookData` (from hooks).
   - Estimated effort: Small

**Validation**:
- [ ] Hook fires -> iOS receives enriched data -> overlay shows tool name + command
- [ ] Hook data arrives before PromptDetector detects prompt -> data is buffered, shown when prompt appears
- [ ] Hook data not available (hooks not configured) -> existing PromptDetector behavior unchanged
- [ ] Respond from iOS -> keystroke sent -> prompt dismisses on iOS, Mac panel, and terminal

### Phase 4: Coordination & Lifecycle

**Goal**: The three response surfaces (terminal, Mac panel, iOS overlay) are coordinated. Responding from one dismisses the others. Edge cases are handled robustly.

**Tasks**:
1. [ ] **Implement prompt lifecycle state machine**
   - File(s): `BalconyMac/Sources/Hooks/HookEventHandler.swift`
   - Details: Define prompt states: `idle`, `hookReceived(PermissionPromptInfo)`, `displayed(PermissionPromptInfo)`, `answered`. Transitions:
     - `idle` -> `hookReceived`: Hook event arrives
     - `hookReceived` -> `displayed`: Panel is shown (or PTY output confirms prompt is visible)
     - `displayed` -> `answered`: User responds from any surface (detected via PTY output change)
     - `answered` -> `idle`: Panel dismissed, hook data cleared, iOS notified
     - `hookReceived` -> `idle`: PTY output shows prompt was already answered before panel appeared (user typed fast)
   - Estimated effort: Medium

2. [ ] **Multi-prompt queue**
   - File(s): `BalconyMac/Sources/Hooks/HookEventHandler.swift`
   - Details: Multiple permission prompts can arrive in sequence (Claude Code asks for permission for each tool use). Queue prompts per session. Show one at a time. When the current prompt is answered, show the next in the queue. Track by sessionId + timestamp to avoid stale prompts.
   - Estimated effort: Small

3. [ ] **Handle timing mismatches**
   - File(s): `BalconyMac/Sources/Hooks/HookEventHandler.swift`
   - Details:
     - Hook arrives before PTY prompt renders: Buffer the hook data. The panel can show immediately (hook data is sufficient), but mark as "awaiting PTY confirmation." If PTY output never shows a prompt within 5 seconds, discard the hook data (may have been a glitch).
     - PTY prompt detected but no hook data: This is the normal case when hooks are not configured. PromptDetector on iOS handles it. Mac does nothing (no panel).
     - User responds before Mac UI appears: Check if the prompt is still active in PTY output before showing the panel. If not, skip showing it.
   - Estimated effort: Medium

4. [ ] **Connection loss handling**
   - File(s): `BalconyMac/Sources/Hooks/HookEventHandler.swift`, `BalconyiOS/Sources/Session/SessionManager.swift`
   - Details: If Mac-iOS WebSocket disconnects while a prompt is active:
     - Mac: Panel continues to work independently (it sends keystrokes directly to PTY)
     - iOS: PromptDetector continues to work independently (it detects from PTY output)
     - On reconnect: Sync state -- if prompt is still pending, re-send hook data to iOS
   - Estimated effort: Small

**Validation**:
- [ ] Respond from terminal -> Mac panel dismisses within 1s, iOS overlay dismisses within 1s
- [ ] Respond from Mac panel -> terminal shows response, iOS overlay dismisses
- [ ] Respond from iOS -> terminal shows response, Mac panel dismisses
- [ ] Two rapid prompts -> first is shown and answered, second appears immediately after
- [ ] User types "y" in terminal before Mac panel appears -> panel does not appear
- [ ] WiFi disconnected -> Mac panel still works, iOS PromptDetector still works

### Phase 5: PromptDetector Improvements (Shared)

**Goal**: Consider moving core prompt detection logic to BalconyShared so Mac can also detect prompts from PTY output as a fallback.

**Tasks**:
1. [ ] **Evaluate moving `PromptDetector` to BalconyShared**
   - File(s): `BalconyShared/Sources/BalconyShared/Models/PromptDetector.swift` (potential), `BalconyiOS/Sources/Views/Terminal/PromptDetector.swift` (current)
   - Details: `PromptDetector` currently depends on `TerminalLine` and `InteractivePrompt` types which are iOS-only. Moving it to BalconyShared requires also moving these types. Evaluate whether the Mac needs prompt detection from PTY output (it already has hooks for detection) vs. the cost of moving types across packages. Decision: likely keep it iOS-only for now, since Mac uses hooks for detection and PTY monitoring for dismissal.
   - Estimated effort: Small (evaluation only)

2. [ ] **Add basic prompt-gone detection for Mac PTY monitoring**
   - File(s): `BalconyMac/Sources/Hooks/HookEventHandler.swift`
   - Details: Instead of full PromptDetector on Mac, use a simpler heuristic for detecting when a prompt has been answered: monitor PTY output for the session, and if the last chunk of output does not contain the `(Y)es / (N)o` pattern (or similar), consider the prompt answered. This is lighter than running a full terminal parser.
   - Estimated effort: Small

**Validation**:
- [ ] Mac correctly detects when a prompt has been answered via PTY output heuristic
- [ ] iOS PromptDetector continues to work unchanged

### Phase 6: Consult Questions (Future)

**Goal**: Extend the pattern to handle Claude asking free-form questions in the terminal text.

**Tasks**:
1. [ ] **Investigate `Stop` and `Notification` hooks**
   - File(s): N/A (research)
   - Details: Claude Code may support hooks that fire when the model stops and waits for input (not just permission prompts). Research available hook types and their JSON schemas. Determine if there's a reliable hook for "Claude is asking the user a question."
   - Estimated effort: Small (research)

2. [ ] **Design question detection and response UI**
   - File(s): N/A (design)
   - Details: Questions are free-form text. The Mac panel would need a text input field. The iOS overlay would need a text input area. Response injection sends the typed text + Enter to the PTY. This is more complex than permission prompts (which are single-keystroke responses).
   - Estimated effort: Large (future)

**Validation**:
- [ ] Deferred to future implementation

---

## Technical Considerations

### Dependencies

- No new external dependencies required
- Existing: Swift Concurrency, POSIX sockets, SwiftTerm, BalconyShared SPM package
- `socat` or Python for the shell-based hook handler (optional -- a compiled Swift helper avoids this dependency)

### Constraints

- macOS 14+ (Sonoma) for `NSPanel` and SwiftUI hosting -- already the deployment target
- iOS 16+ for `PromptOverlayView` enhancements -- already the deployment target
- `HookListener` must coexist with `PTYSessionManager` using the same `~/.balcony/` directory
- `NSPanel` must not steal focus from Terminal.app or other active windows
- Hook handler script must be cross-compatible with different shell environments (bash, zsh)
- All new models in BalconyShared must be `Codable`, `Sendable`, and use value types

### Risks & Mitigation

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| Hook data arrives out of order with PTY output | Med | High | Buffer hook data, correlate with PTY prompt detection, use timestamps for ordering |
| User responds before Mac panel appears | Low | Med | Check PTY state before showing panel; skip if prompt already answered |
| NSPanel focus stealing on some macOS versions | Med | Low | Use `.nonactivatingPanel` style mask, test on macOS 14 and 15 |
| Hook handler script fails silently | Med | Med | Add error logging to script, verify socket connectivity, provide health check command |
| Multiple Claude Code sessions sending hooks simultaneously | Low | Low | Queue per session ID, handle concurrently |
| Claude Code hook format changes in future versions | Med | Low | Version the hook handler, validate JSON schema gracefully, log unknown fields |

### Open Questions

- How does Claude Code's hook JSON schema look exactly for `PermissionRequest`? Need to verify fields: `sessionId`, `hookEventName`, `toolName`, `toolInput`. Test with a real hook configuration.
- Should the Mac panel show an option to "Always Allow" for a specific tool? This would require understanding Claude Code's permission persistence model.
- Should the hook handler be a compiled Swift binary (part of BalconyCLI) or a standalone script? A Swift binary can share types with BalconyShared but adds a build step. A script is simpler but needs socket client code.
- What is the ideal panel position? Near menu bar icon (follows the Balcony brand), center-top of screen (most visible), or near the active terminal window (contextual)?
- Should hook events be encrypted when forwarded to iOS via WebSocket? The existing WebSocket channel is already encrypted (E2E with XChaCha20-Poly1305), so hook data inherits that protection.

---

## Files Involved

### New Files
- `BalconyShared/Sources/BalconyShared/Models/HookEvent.swift` -- Hook event model and `PermissionPromptInfo`
- `BalconyMac/Sources/Hooks/HookListener.swift` -- Unix socket listener for hook events
- `BalconyMac/Sources/Hooks/HookEventHandler.swift` -- Hook event processing, prompt lifecycle, queue
- `BalconyMac/Sources/UI/PromptPanel/PromptPanelController.swift` -- NSPanel management
- `BalconyMac/Sources/UI/PromptPanel/PromptPanelView.swift` -- SwiftUI view for the floating panel
- `Scripts/hook-handler` -- Hook handler script/binary

### Modified Files
- `BalconyShared/Sources/BalconyShared/Protocol/MessageType.swift` -- Add `.hookEvent`, `.hookDismiss`
  - Specific sections: `MessageType` enum cases
- `BalconyMac/Sources/App/AppDelegate.swift` -- Instantiate and wire `HookListener`, `HookEventHandler`, `PromptPanelController`
  - Specific sections: `applicationDidFinishLaunching`, new properties
- `BalconyMac/Sources/Connection/ConnectionManager.swift` -- Add `forwardHookEvent()` and `forwardHookDismiss()` methods
  - Specific sections: New methods in "PTY Data Forwarding" section
- `BalconyiOS/Sources/Session/SessionManager.swift` -- Handle `.hookEvent` and `.hookDismiss` messages, add `pendingHookData` published property
  - Specific sections: `handleMessage` switch, new handler methods, new `@Published` property
- `BalconyiOS/Sources/Views/Terminal/PromptOverlayView.swift` -- Accept and render `hookData` for enriched display
  - Specific sections: `PermissionPromptView`, add enriched header
- `BalconyiOS/Sources/Views/Terminal/TerminalContainerView.swift` -- Pass `pendingHookData` through to ConversationView/PromptOverlayView
- `BalconyiOS/Sources/Views/Terminal/ConversationView.swift` -- Accept and forward `pendingHookData` to PromptOverlayView
- `project.yml` -- Add `BalconyMac/Sources/Hooks` and `BalconyMac/Sources/UI/PromptPanel` source paths (verify auto-discovery)

### Related Files (for reference)
- `BalconyMac/Sources/Session/PTYSessionManager.swift` -- Existing Unix socket pattern to replicate for `HookListener`; `sendInput()` for response injection
- `BalconyiOS/Sources/Views/Terminal/PromptDetector.swift` -- Existing detection logic (stays unchanged)
- `BalconyiOS/Sources/Views/Terminal/InteractivePrompt.swift` -- Existing prompt model types
- `BalconyiOS/Sources/Views/Terminal/HeadlessTerminalParser.swift` -- Terminal parsing (stays unchanged)
- `BalconyShared/Sources/BalconyShared/Models/BalconyMessage.swift` -- Message envelope for hook events
- `BalconyMac/Sources/MenuBar/` -- Existing menu bar UI (for reference on Mac styling)

---

## Testing Strategy

### Unit Tests
- `HookEvent` JSON decoding: verify parsing of Claude Code's hook JSON format with various tool types (Bash, Edit, Write, Read, Grep, Glob)
- `PermissionPromptInfo` computed properties: `riskLevel` returns correct values for known-dangerous commands (`rm -rf`, `sudo`, etc.)
- `HookEventHandler` state machine: verify transitions from `idle` -> `hookReceived` -> `displayed` -> `answered` -> `idle`
- `HookEventHandler` queue: verify multi-prompt sequencing
- `MessageType` encoding/decoding: verify `.hookEvent` and `.hookDismiss` round-trip

### Integration Tests
- End-to-end: hook handler script -> `HookListener` -> parsed `HookEvent` (use a test JSON payload)
- WebSocket forwarding: `HookEvent` -> `BalconyMessage` -> iOS `SessionManager` receives correct data

### Manual Testing
- [ ] Configure Claude Code hooks, run a session that requires Bash permission
- [ ] Verify Mac panel appears with correct tool name and command
- [ ] Click "Allow" on Mac panel, verify Claude Code proceeds
- [ ] Type "y" in terminal, verify Mac panel dismisses
- [ ] Respond from iOS, verify Mac panel and terminal both reflect the response
- [ ] Run without hooks configured, verify iOS PromptDetector works as before
- [ ] Test with multiple rapid permission requests
- [ ] Test with Mac-iOS WiFi disconnected

### Edge Cases
- Hook JSON with unexpected/missing fields (graceful degradation)
- Very long Bash commands (truncation in panel and overlay)
- Hook arrives for a session that has already ended (discard)
- Two Claude Code sessions running simultaneously, each producing hooks
- Hook handler script exits with error (socket not available) -- should not affect Claude Code
- PTY output arrives in small chunks that split the prompt pattern across chunks

---

## References

### Reference Files
- No external reference files provided for this plan.

### Documentation
- Claude Code hooks documentation: https://docs.anthropic.com/en/docs/claude-code/hooks
- `CLAUDE.md` -- Project conventions, build commands, architecture overview
- `BalconyShared/Sources/BalconyShared/Protocol/` -- Existing protocol definitions

### Related Work
- `/model` picker implementation: `BalconyMac/Sources/Session/ModelListProvider.swift`, `BalconyMac/Sources/Connection/ConnectionManager.swift` (handleModelSelection), `BalconyiOS/Sources/Views/Terminal/ModelPickerView.swift` -- Proves the detect -> native UI -> inject keystrokes pattern
- `/rewind` picker implementation: Same pattern with `RewindPickerView`, `RewindSelectionPayload`
- `/resume` session picker: Same pattern with `SessionPickerView`, `SessionPickerSelectionPayload`

### Code Examples
- `BalconyMac/Sources/Session/PTYSessionManager.swift:39-104` -- Unix domain socket server pattern to replicate for HookListener
- `BalconyMac/Sources/Connection/ConnectionManager.swift:342-364` -- Model selection keystroke injection pattern to replicate for prompt responses
- `BalconyiOS/Sources/Views/Terminal/PromptDetector.swift:32-45` -- Main detection entry point that hook data will complement
- `BalconyiOS/Sources/Views/Terminal/PromptOverlayView.swift:22-59` -- Permission buttons view to enhance with hook data

---

## Deployment & Rollout

### Prerequisites
- [ ] Claude Code hooks feature is available and documented (verify hook JSON schema)
- [ ] BalconyShared package builds with new models
- [ ] Hook handler script is tested standalone
- [ ] NSPanel behavior verified on macOS 14 Sonoma and 15 Sequoia

### Deployment Steps
1. Merge Phase 1 (hook listener infrastructure + shared models) -- enables data flow
2. Merge Phase 2 (Mac panel UI) -- enables Mac-side prompt interaction
3. Merge Phase 3 (iOS enrichment) -- enhances iOS prompt display
4. Merge Phase 4 (coordination) -- handles edge cases and multi-prompt
5. Ship hook handler script as part of Balcony installation

### Rollback Plan
- Hook configuration is user-controlled: removing the hook from `settings.json` disables the entire feature
- Mac panel can be disabled by not starting `HookListener` (feature flag in AppDelegate)
- iOS falls back to `PromptDetector`-only behavior when no hook data is present
- Each phase is independently valuable and can be reverted without breaking other phases

### Monitoring
- `os.Logger` in `HookListener` category: track hook events received, parse failures, socket errors
- `os.Logger` in `HookEventHandler` category: track prompt lifecycle transitions, timing mismatches
- `os.Logger` in `PromptPanelController` category: track panel show/dismiss, response injection
- Success: hook events received within 100ms of Claude Code tool use, panel shown within 200ms

---

## Success Metrics

### Immediate
- Hook handler script successfully bridges Claude Code hook events to BalconyMac
- Mac panel appears for 100% of permission prompts (when hooks are configured)
- Panel dismisses correctly when prompt is answered from any surface

### Short-term (1-2 weeks)
- Users can respond to permission prompts from Mac panel or iOS without touching the terminal
- Response latency (from button press to terminal response) is under 200ms
- Zero false-positive panel appearances (panel only shows when a real prompt is active)

### Long-term
- Reduced time-to-response for permission prompts (user no longer needs to find the terminal window)
- Foundation for extending to consult questions and other interactive prompts
- Pattern can be reused for any future hook types Claude Code adds

---

## Notes & Observations

- The `PermissionRequest` hook being async is crucial. If it were synchronous, showing a Mac panel before the terminal prompt renders would create a confusing state. With async, both happen independently and we coordinate after the fact.
- The existing `/model`, `/rewind`, `/resume` picker pattern is a proven template. Prompt routing follows the same philosophy: detect on one end, show native UI, inject keystrokes back. The main difference is that prompt routing uses hooks for detection (push) while pickers use slash command detection (pull).
- Consider adding a subtle animation/sound when the Mac panel appears, similar to macOS notification banners, to draw attention without being intrusive.
- The hook handler script is the weakest link in reliability. A compiled Swift helper binary that shares types with BalconyShared would be more robust than a shell script, but adds build complexity. Start with a shell script, upgrade later if needed.
- Phase 6 (consult questions) is intentionally deferred. Permission prompts are the highest-value target because they block Claude Code's progress. Questions are lower priority since the user can respond at leisure.

---

**Last Updated**: 2026-02-26T12:00:00Z
**Generated By**: `/plan` command
**Next Steps**: Review and refine the plan, verify Claude Code hook JSON schema with a real test, then use `/kickoff PROMPT_ROUTING` to start implementation
