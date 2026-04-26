---
name: remodex-connection-strategy
description: Use when working on Remodex iPhone/Mac connection, relay pairing, trusted reconnect, websocket reachability, or A/B Mac switching. This skill covers full-chain diagnosis and implementation for local-only LAN relays, persistent/public relays, Tailscale/VPN reachability, saved-session vs trusted-session reconnect, and thread/workspace consistency when switching between multiple Macs.
---

# Remodex Connection Strategy

Use this skill for Remodex connection work before changing reconnect code or explaining pairing behavior.

## User scenario to preserve

- One iPhone switches repeatedly between multiple Macs such as home Mac A and company Mac B.
- Home relay may be `192.168.x.x`; company relay may be `10.x.x.x`; both are private networks.
- Private-network relays are only reachable when the iPhone is on the same LAN or the same VPN/private overlay such as Tailscale.
- Do not explain private relays as if they were globally reachable over normal cellular data or ordinary outbound proxy apps.

## Required mental model

- Separate `active session relay` from `long-term reconnect relay`.
- Treat each `macDeviceId` as its own reconnect domain with isolated thread/workspace state.
- Preserve a stable long-term relay for a Mac when a later QR scan uses a LAN-only relay.
- Local-only relays are valid for same-LAN use, but must not overwrite a better persistent relay for future cross-network reconnect.
- Reconnect preference order should be:
  1. Non-local persistent relay for the selected trusted Mac
  2. Current non-local saved session relay for that same Mac
  3. Local-only relay only when no non-local candidate exists
- If all known candidates for a Mac are local-only and unreachable, fail early with a clear message instead of timing out through multiple reconnect branches.

## Guardrails

- Do not claim that ordinary Shadowsocks/Shadowrocket-style proxying makes `10.x.x.x` or `192.168.x.x` directly reachable.
- Do not treat Tailscale `100.64.0.0/10` or `.ts.net` as generic LAN-only; they are private-overlay addresses and can be valid long-term reconnect paths.
- Do not collapse multi-Mac state into one global relay decision.
- When fixing one symptom, inspect:
  - trusted-session resolve path
  - saved-session fallback path
  - thread/workspace reset and selection
  - wake/handoff reconnect path
  - user-facing error copy

## Implementation checklist

- Inspect trusted Mac storage model first.
- Check whether relay persistence distinguishes local-only vs persistent candidates.
- Check reconnect URL selection order in `ContentViewModel`.
- Check secure trusted-session resolve code in `CodexService+SecureTransport`.
- Check socket error mapping in `CodexService+Connection`.
- Check workspace/thread reset behavior when `macDeviceId` changes.
- Add or update focused tests for:
  - public relay remains preferred after scanning a LAN QR for the same Mac
  - local-only candidates stop early when no non-local route exists
  - public relay fallback still works when trusted resolve fails

## User communication

- Be explicit about network reality:
  - `192.168.x.x` and `10.x.x.x` are private
  - cellular alone cannot reach them
  - same LAN, VPN, Tailscale, or public relay is required
- Distinguish “product behavior bug” from “network topology limitation”.
- Prefer end-to-end fixes over point patches.

## Related skills

- If the user wants to force macOS global `remodex up/restart` onto one LAN relay, use `skills/remodex-global-local-relay/SKILL.md`.
- If the user wants to clear stale state and return one Mac to fresh local pairing, use `skills/remodex-local-recovery/SKILL.md`.
