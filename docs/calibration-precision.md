# Calibration Precision Improvement Plan

## Goal
Increase hardware latency accuracy and confidence by using a structured pre-generated test signal, multi-marker detection, and lightweight clock alignment between iOS and the receiver. Target sub-1 ms resolution with higher confidence and clearer user feedback.

## Current State (concise)
- Receiver plays per-request chirps (configurable freqs/duration/reps) and schedules playback by server time.
- iOS records with a pre/post window, correlates against the chirp sequence, and averages detections. Confidence is correlation-based; can be low (e.g., ~5%) and sometimes misses.
- UI shows a mic pulse indicator (recent change) but confidence can still be low.

## Proposed Signal
- Pre-generate a fixed WAV on the receiver at install/startup:
  - Sample rate: 48 kHz, mono, 16-bit.
  - Duration: ~3–5 s.
  - Structure:
    1. Marker A: broadband click at t=0.
    2. Silence: 200 ms.
    3. Marker burst: 6–8 short chirps spaced 250 ms; freqs spread (e.g., 1 kHz, 3 kHz, 6 kHz, 8 kHz, 10 kHz) with Hanning window.
    4. Trailing Marker B: broadband click near end (e.g., t=3 s) to detect truncation.
  - Amplitude: 0.9–0.95 (avoid clipping).
  - Metadata: expected start sample for each marker in a shared struct (length + positions).

## Clock Alignment
- Continue scheduling playback in the future (server time now + 2–3 s).
- iOS performs `/api/time` twice; uses median offset/RTT to estimate server time for windowing only. Latency is computed purely from audio alignment (not wall clock).
- Recording window = expected signal length + generous pad (e.g., +1 s) to absorb residual offset.

## Detection Algorithm (iOS)
- Load the known signal definition (markers list).
- For each marker type:
  - Use matched filtering (cross-correlation) against the recorded audio.
  - Find peak; apply sub-sample interpolation (parabolic fit) for <0.1 ms resolution at 48 kHz.
  - Compute SNR/correlation score.
- Aggregate:
  - Convert peak sample indices to latency: measured_start - expected_start.
  - Reject outliers (e.g., MAD-based).
  - Average remaining offsets; confidence = function of peak SNR, consistency across markers, and count of inliers.

## Protocol Changes
- Extend shared protocol to include a “structured” playback mode:
  - New config type or flag referencing the pre-generated WAV and marker metadata (IDs + sample positions).
  - Response includes marker schedule and sample rate so iOS can detect accurately.
- Continue to support amplitude scaling if needed (but prefer fixed amplitude for consistency).

## Receiver Changes
- Generate and persist structured WAV at install/startup (e.g., `/usr/local/share/airsync/structured_cal.wav`).
- Expose marker metadata via the API (either in calibration request response or a dedicated endpoint).
- Playback uses the pre-generated file for structured mode; still schedules by server time.
- Tests: unit test generator (positions, length, energy), integration test for HTTP response including metadata, and that playback selects pregen file.

## iOS Changes
- Add model for marker metadata and structured signal definition.
- Add detection pipeline with matched filters and sub-sample peak interpolation.
- Add clock-offset helper (two-sample `/api/time`).
- Update calibration flow to:
  1) Fetch marker metadata (or receive via request response).
  2) Schedule playback for future time.
  3) Record with padding.
  4) Run marker detection, compute latency/confidence, and display result.
- UI: keep mic pulse; optionally show “markers detected: N/M”.
- Tests:
  - Unit: peak interpolation, matched-filter correctness on synthetic data with known offsets.
  - Unit: outlier rejection, confidence computation.
  - Integration (offline): generate synthetic recording with inserted markers + noise; ensure detector finds correct latency.

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
