# AirSync iOS ⇄ Debian Receiver Pairing Design

## Goals
- Allow the iOS app to reliably discover and pair with a Debian-based AirSync receiver on the same LAN.
- Minimize user friction: default to Bonjour discovery with a manual entry fallback; keep prompts clear (Local Network + Microphone).
- Keep the protocol minimal and future-proof (versioned capabilities; backward-compatible additions).

## Non-goals
- Building full remote management; only the pairing + calibration handshake (future remote settings should be easy to add).
- Internet-facing security (assume trusted LAN; keep room for TLS but don’t block local use on self-signed certs).

## Current state
- iOS app browses for `_airsync._tcp` via `NWBrowser` and falls back to manual `http://<host>:5000`.
- Calibration runs in structured mode: fetches `GET /api/calibration/spec`, then `POST /api/calibration/request` + `POST /api/calibration/ready`, then posts results.
- No auth or pairing code (trusted LAN); Bonjour TXT defined (name, ver, api, caps, id).

## Requirements
1. **Discovery**
   - Receiver advertises `_airsync._tcp` on port `5000` with TXT keys:
     - `name=<human readable>` (e.g., “Living Room AirSync”)
     - `ver=1`
     - `api=/api` (root for HTTP)
     - `caps=calibration` (comma list; future: `playback`, `volume`, etc.)
     - `id=<stable-uuid>` (used for trust storage)
2. **Pairing / Trust (non-authenticated)**
   - LAN assumed trusted; API calls do **not** require tokens or authentication.
   - No pairing code; app stores receiver metadata locally (`receiver_id`, name, host) after user selection.
3. **Transport**
   - HTTP on LAN (no auth); optional HTTPS future.
   - All JSON; UTF-8; small bodies.
4. **Resilience**
   - Manual entry path (`http://host:5000`) always available.
   - Clear error surfaces for `NoAuth` (Local Network denied), DNS failures, and pairing failures.
5. **Permissions**
- Local Network (Bonjour); Mic requested during calibration.

## Proposed flow (happy path)
1. Receiver boots, starts HTTP server on `:5000`, publishes `_airsync._tcp` with TXT above.
2. iOS app receives browse result, displays receiver name.
3. User taps receiver → app stores receiver metadata locally.
4. Calibration flow (structured mode):
   - `GET /api/calibration/spec` to fetch marker metadata.
   - `POST /api/calibration/request` (structured: true) then `POST /api/calibration/ready` (target start).
   - Receiver plays pre-generated WAV; iOS records, detects markers, posts `POST /api/calibration/result`.
5. Subsequent sessions:
   - Use cached receiver metadata; skip pairing; manual host entry remains available.

## API surface (receiver)
- `GET /api/calibration/spec`
  - Output: `{ "spec": { sample_rate, length_samples, markers: [...] } }`
- `POST /api/calibration/request`
  - Input: `{ "timestamp": u64, "chirp_config": {...}, "delay_ms": u64, "structured": true }`
  - Output: `200 OK` (queues structured playback)
- `POST /api/calibration/ready`
  - Input: `{ "timestamp": u64, "target_start_ms": u64 }`
  - Output: `200 OK` (schedules playback at target)
- `POST /api/calibration/result`
  - Input: `{ "timestamp": u64, "latency_ms": f32, "confidence": f32 }`
  - Output: `200 OK` (applies latency offset + restarts shairport-sync)
- `GET /api/settings` / `POST /api/settings` (existing)
- `GET /api/receiver/info`
  - Output: `receiver_id`, `name`, `caps`, `version`

## Receiver (Debian) implementation notes
- Dependencies: `avahi-daemon` running; publish service via `/etc/avahi/services/airsync.service` or `avahi-publish-service "AirSync" _airsync._tcp 5000 ver=1 api=/api caps=calibration id=<uuid>`.
- HTTP service on `:5000` (Axum).
- Persist `receiver_id` under `/var/lib/airsync/receiver.json`.
- No tokens; all API calls open on LAN.
- Calibration playback uses pre-generated structured WAV (aplay) and applies latency via shairport-sync config + restart.

## iOS client changes (at a glance)
- Discovery: read TXT for `name`, `id`, `caps`; display name and keep `receiver_id`.
- No pairing code; selecting a receiver stores metadata locally.
- Calibration:
  - Fetch spec, request structured playback, arm recording with pad, detect markers, compute latency/confidence.
  - UI: mic pulse indicator, frequency range, detection counts; “Send to Receiver & Restart” calls `/calibration/result`.
- Networking: Plain HTTP; no Authorization header.

## Failure/edge cases
- Receiver not advertising: show manual entry and suggest checking avahi service (`systemctl status avahi-daemon`).
- Multiple receivers with same name: disambiguate by host or last octet of `id`.
- Self-signed TLS (future): allow user to trust once per receiver.

## Open questions
- Do we need PIN entry when receiver is headless? (If no UI, code from logs is acceptable? If not, fallback to trust-on-first-use without code.)
- How much of the future remote settings API should be discoverable via `caps` (e.g., `caps=calibration,settings`)?
- Should we add optional TLS + pinned cert for users who want more assurance on LAN?

## Rollout plan
1. Maintain Bonjour publish + open calibration/settings endpoints.
2. Iteratively improve structured calibration (detector robustness, confidence).
3. Add optional TLS and access control only if LAN threat model changes.
4. Continue UX refinements (manual entry, clearer errors).
