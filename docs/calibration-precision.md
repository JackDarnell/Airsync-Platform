# Calibration Precision Improvement Plan

## Goal
Increase hardware latency accuracy and confidence by using a structured pre-generated test signal, multi-marker detection, and lightweight clock alignment between iOS and the receiver. Target sub-1 ms resolution with higher confidence and clearer user feedback.

## Current State (concise)
- Receiver plays per-request chirps (configurable freqs/duration/reps) and schedules playback by server time.
- iOS records with a pre/post window, correlates against the chirp sequence, and averages detections. Confidence is correlation-based; can be low (e.g., ~5%) and sometimes misses.
- UI shows a mic pulse indicator (recent change) but confidence can still be low.

## Implemented Signal (structured mode)
- Pre-generated WAV on the receiver at install/startup:
  - Sample rate: 48 kHz, mono, 16-bit; stored at `/usr/local/share/airsync/structured_cal.wav`.
  - Duration: ~5 s with padded silence.
  - Structure:
    1. Warm-up hum (120 Hz, low amp) to keep amps awake.
    2. Click A, then 200 ms silence.
    3. Marker burst: multiple short windowed tones (≈100 ms) across freqs: 0.8–10 kHz spread, spaced ≈280 ms.
    4. Trailing click B plus light warm-down hum.
  - Amplitude: ~0.9 for markers, gentle for hum.
  - Metadata: expected start/duration per marker + total length returned via `GET /api/calibration/spec`.

## Clock Alignment
- Playback scheduled in the future (server time now + ≈3 s) using `/api/calibration/request` + `/api/calibration/ready`.
- Recording window = delay + signal length + extra pad (~2.5 s) so the mic is armed before/after playback.

## Detection Algorithm (iOS)
- Fetch spec → matched filtering over known markers with sub-sample peak fit.
- Outlier rejection + confidence derived from correlation strength + agreement across markers.
- UI shows mic pulse + frequency range of markers; structured detector runs for all calibrations.

## Protocol Changes
- Extend shared protocol to include a “structured” playback mode:
  - New config type or flag referencing the pre-generated WAV and marker metadata (IDs + sample positions).
  - Response includes marker schedule and sample rate so iOS can detect accurately.
- Continue to support amplitude scaling if needed (but prefer fixed amplitude for consistency).

## Receiver Changes
- Structured WAV generation/persistence done at service start/installer.
- `GET /api/calibration/spec` returns marker metadata.
- Playback uses pre-generated file for structured mode (with warm-up hum); scheduled via `/ready`.
- Tests cover generator length/markers and spec endpoint.

## iOS Changes
- Structured mode enforced; fetch spec before every calibration.
- Longer record window; matched-filter detector with sub-sample interpolation and detection counts.
- UI shows mic pulse + frequency range; latest measurement shows detections and confidence.
- Tests cover decoder robustness and detector on synthetic signals.

## TDD / Iteration Plan
1) Add shared protocol structs for structured signal + marker metadata (unit tests for serialization).
2) Receiver: generator + metadata + endpoint/response; tests for positions/length and HTTP payload.
3) iOS: detection utilities (matched filter, peak interp, outlier rejection) with unit tests on synthetic signals.
4) iOS: clock-offset helper tests.
5) iOS: integrate structured mode into calibration flow; UI marker count; integration-style test with synthetic recording.

## Open Questions / Risks
- AGC/noise suppression on some devices may still distort clicks; keep multi-frequency markers to mitigate.
- If sample rates differ, resample recording to 48 kHz before correlation (can be added if needed).
- Make amplitude configurable only if devices clip; default fixed amplitude for determinism.
