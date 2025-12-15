# Calibration Iteration Plan (Structured Mode, Target ≤5 ms)

Scope: Improve playback reliability, timing accuracy, and UX clarity for the iOS calibration flow. No code changes yet—this is the plan to execute with TDD.

## Objectives
- Accurate latency within ~5 ms; eliminate negative/early results.
- Confidence >60% on real-world runs with typical room noise.
- Clear, truthful UI steps tied to real events (playback → record → analyze → send).
- Remove end-of-signal pops and ALSA contention surprises.

## Receiver (Rust)
1) Signal shape and amplitude
   - Add fade-in/out to all markers and clicks; trailing click with soft envelope.
   - Add one sweep anchor (short log sweep) plus existing multi-tone markers.
   - Keep total length ~4–5 s, consistent spacing; low-level pre-roll that overlaps first marker.
   - Tests: generator length, marker ordering, envelope derivative bounded, peak < 0 dBFS, sweep marker present.

2) Playback reliability
   - Option A: briefly pause/duck shairport during calibration playback; resume after.
   - Option B: dedicated ALSA device (`-D`) with busy detection and retry.
   - Log device/busy errors; ensure playback returns status.
   - Tests: mock PlaybackSink busy case; ensures retry/backoff logs; spec endpoint unchanged.

3) API/logging
   - Keep `/api/calibration/spec/request/ready/result`.
   - Add structured playback log line with target_ts, start_ts, device, file path.

## Timing / Clock Alignment
1) Two-sample `/api/time` RTT helper to estimate server offset; use median.
2) Target start = server_now + 2–3 s + offset; clamp minimum lead time.
3) Record window = delay + signal length + ~1.0 s pad (shorter than current 10 s).
4) Detector search window: start after delay+small slack; end at delay+len+pad.
5) Tests (iOS unit): RTT helper; detector on synthetic with known offset ± jitter (<1 ms error).

## Detector & Confidence (iOS)
1) Per-marker correlation/SNR threshold; drop weak markers before averaging.
2) Confidence = f(inlier count, correlation strength, offset spread); low confidence if few inliers.
3) Debug log per marker: peak idx, corr, accepted/rejected.
4) Clamp negative latency near zero unless high-confidence early detection; surface “early audio” warning.
5) Tests: synthetic noisy signals; missing first marker; truncated tail; ensure inliers/latency/confidence match expectations.

## UI/UX (iOS)
1) Stepper tied to actual events:
   - Scheduling (after `/request`), Playing (after `/ready`), Listening (recording active), Analyzing (detector start), Sending (POST result), Completed.
2) Inline run summary: markers detected, top correlation, measured latency, confidence.
3) Clear subtext for current step (“Playing calibration signal…”, “Detecting markers…”).
4) Fix nav/button constraint warning (use NavigationStack defaults or layout fix).
5) Tests: view-model stage transitions drive stepper; snapshot/preview to ensure no layout conflicts.

## Measurement Sanity
- Require minimum inliers; show “low confidence” otherwise.
- Reject/flag latency if only late/early tails are found (consistency check across markers).

## Sound Design Tweaks
- Multi-tone markers (120 Hz hum + 0.8/1/3/6/8/10 kHz tones with envelopes).
- One short sweep anchor for robust correlation.
- Keep amplitude < 1.0, avoid clipping; ensure hum is quiet but continuous through first marker.

## Test Execution Plan
- Rust: `cargo test -p airsync-receiver-core` (generator/envelope/playback tests).
- iOS: unit tests for RTT helper, detector, view-model stepper; build on simulator.
- Manual: once code lands, single-device run to confirm no pops, accurate steps, and reasonable latency/confidence.

## Iteration Order (small, mergeable steps)
1) Receiver signal polish
   - Add fade/envelope + sweep marker; keep length/spacing predictable.
   - Tests for peak level, envelope derivative, marker ordering, sweep presence.
2) Playback resilience/logging
   - Implement busy/ALSA handling (pause shairport or dedicated device) with retries and clear logs.
   - Return playback status + structured log line (target_ts/start_ts/device/path).
3) Timing helper (iOS)
   - `/api/time` RTT median helper with min lead-time clamp; unit tests for jitter bounds.
4) Detector upgrades
   - Per-marker correlation with inlier filter, confidence formula, negative-latency clamp + warning; marker debug logs.
   - Unit tests for noisy/missing/truncated markers and spread-based confidence.
5) UI flow
   - Stepper tied to events, inline run summary, subtext copy; fix nav/button constraints.
   - Tests: view-model stage transitions + snapshot to catch layout warnings.
6) Validation pass
   - End-to-end run on device; capture logs (playback start, per-marker debug), measured latency/confidence, and note any pops/busy errors for follow-up.
