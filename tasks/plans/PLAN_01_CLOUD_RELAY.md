# Plan: CLOUD_RELAY

**Created**: 2026-06-11
**Status**: Draft (needs review — infrastructure decisions required before kickoff)

Enable Balcony to work when the iPhone is not on the same network as the Mac: a zero-knowledge store-and-forward relay (Supabase) plus push notifications, unlocking remote prompt responses and background Live Activity updates.

---

## Objective

### Problem Statement

Balcony is currently LAN-only: BalconyiOS connects to BalconyMac's WebSocket server via Bonjour discovery on the local network. The primary use case — "monitor Claude Code while away" — breaks the moment you leave the house. Additionally, the Live Activity only updates while the app is alive (`pushType: nil` in `LiveActivityManager`); it goes stale in the background because no push tokens are collected.

A scaffold exists in `supabase/` (schema for `devices`, `pairings`, `relay_messages` with RLS and a 1-hour TTL) but all three edge functions (`relay-message`, `send-push`, `cleanup`) are `not_implemented` stubs and nothing in the Swift codebase references the relay.

### Success Criteria

- [ ] iPhone on LTE receives a permission prompt from a session running at home and can answer it
- [ ] Relay is zero-knowledge: it stores only ciphertext (existing X25519 + XChaCha20-Poly1305 layer); keys never leave the devices
- [ ] Live Activity updates via APNs while the app is backgrounded
- [ ] Direct (LAN) transport remains the preferred path; relay engages only when direct is unavailable
- [ ] Relay messages expire (TTL) and cost stays bounded

---

## Key Decisions Needed Before Kickoff

1. **Push provider: APNs direct vs FCM.** The schema has `fcm_token`, but Live Activity updates require APNs (token-based auth, `.p8` key) and the app is Apple-only. Recommendation: drop FCM, rename to `push_token` + `live_activity_token`, send via APNs HTTP/2 from the edge function.
2. **Auth model.** How devices authenticate to Supabase: Sign in with Apple, anonymous auth + pairing proof, or pre-shared pairing secret (the schema already has `shared_secret_hash`). Recommendation: anonymous Supabase auth bound to the existing QR pairing exchange.
3. **What flows over the relay.** Full PTY stream relay would be heavy and laggy. Recommendation: relay only structured events (session list, hook events, idle prompts, questions, responses) — i.e., "notify + respond" mode when remote, full mirror only on LAN. This caps cost and matches the away-from-home use case.
4. **Hosting.** Dedicated Supabase project; needs APNs `.p8` key, key ID, team ID as function secrets.

---

## Implementation Phases (high level)

### Phase 1: Supabase backend
- Implement `relay-message` (authenticated store-and-forward of ciphertext envelopes, per-pairing)
- Implement `send-push` (APNs HTTP/2: alert pushes + Live Activity updates)
- Implement `cleanup` (purge expired `relay_messages`; schedule via pg_cron)
- Migration: `fcm_token` → `push_token` / `live_activity_token`, add APNs environment column
- Local integration tests via `supabase start`

### Phase 2: Shared protocol
- `RelayEnvelope` model in BalconyShared (pairing id, sender, ciphertext, timestamp, kind)
- Reuse the existing `MessageEncoder`/`CryptoManager` pipeline — the relay carries the same encrypted `BalconyMessage` bytes the WebSocket carries today
- Decide + encode the reduced "remote event" subset (decision 3)

### Phase 3: Mac relay client
- `RelayTransport` in BalconyMac: device registration, publish events when no subscriber is connected directly, poll/realtime-subscribe for responses
- Trigger `send-push` for attention events (prompt waiting, session done)

### Phase 4: iOS relay client + transport abstraction
- Transport selection in `ConnectionManager`/`SessionManager`: direct-first, relay fallback, seamless switch on network change
- Respond to prompts via relay (responses flow back to Mac → PTY keystrokes, same as today)

### Phase 5: Push + Live Activity tokens
- iOS: capture APNs token + Live Activity push-to-start/update tokens, register with backend
- Mac→relay→APNs: Live Activity content-state updates (working/done/attention counts) while app is backgrounded
- Notification taps deep-link to the relevant session

### Phase 6: Lifecycle & hardening
- Delivery acks, dedupe, reconnect sync (mirror of the existing `resendPending*` pattern)
- Rate limiting / cost controls, telemetry, kill switch (feature flag — relay off by default until stable)

---

## References

- `supabase/migrations/001_initial_schema.sql` — existing schema (devices, pairings, relay_messages)
- `supabase/functions/{relay-message,send-push,cleanup}/index.ts` — stubs to implement
- `BalconyiOS/Sources/Activity/LiveActivityManager.swift` — `pushType: nil` to replace
- `BalconyShared/Sources/BalconyShared/Crypto/` — E2E layer the relay envelopes reuse
- `BalconyMac/Sources/Connection/ConnectionManager.swift` — `resendPending*` resync pattern to mirror

---

**Last Updated**: 2026-06-11
**Next Steps**: Resolve the four decisions above, then expand phases into tasks and kick off.
