use airsync_shared_protocol::{CalibrationSignalSpec, MarkerKind, MarkerSpec};
use anyhow::Result;
use hound::WavWriter;
use std::f32::consts::PI;
use std::path::{Path, PathBuf};

const SAMPLE_RATE: u32 = 48_000;
const TARGET_LENGTH_MS: u32 = 4_700;

#[derive(Clone)]
pub struct StructuredSignal {
    pub spec: CalibrationSignalSpec,
    pub path: PathBuf,
}

fn ms_to_samples(ms: u32) -> usize {
    ((ms as u64 * SAMPLE_RATE as u64) / 1000) as usize
}

fn raised_cosine_window(n: usize, len: usize, fade_samples: usize) -> f32 {
    if len <= 1 {
        return 1.0;
    }
    let fade = fade_samples.max(1).min(len / 2);
    if n < fade {
        0.5 - 0.5 * (PI * n as f32 / fade as f32).cos()
    } else if n >= len - fade {
        let k = len - 1 - n;
        0.5 - 0.5 * (PI * k as f32 / fade as f32).cos()
    } else {
        1.0
    }
}

struct SignalBuilder {
    sample_rate: u32,
    samples: Vec<f32>,
}

impl SignalBuilder {
    fn new(sample_rate: u32) -> Self {
        Self {
            sample_rate,
            samples: Vec::new(),
        }
    }

    fn len(&self) -> usize {
        self.samples.len()
    }

    fn ensure_len(&mut self, len: usize) {
        if self.samples.len() < len {
            self.samples.resize(len, 0.0);
        }
    }

    fn mix_wave<F>(&mut self, start: usize, duration: usize, amp: f32, fade_samples: usize, mut f: F)
    where
        F: FnMut(usize, f32) -> f32,
    {
        if duration == 0 {
            return;
        }
        let end = start + duration;
        self.ensure_len(end);
        let sr = self.sample_rate as f32;
        for n in 0..duration {
            let env = raised_cosine_window(n, duration, fade_samples);
            let t = n as f32 / sr;
            self.samples[start + n] += f(n, t) * amp * env;
        }
    }

    fn mix_sine(&mut self, start: usize, duration: usize, freq_hz: f32, amp: f32, fade_samples: usize) {
        self.mix_wave(start, duration, amp, fade_samples, |_, t| (2.0 * PI * freq_hz * t).sin());
    }

    fn mix_constant(&mut self, start: usize, duration: usize, amp: f32, fade_samples: usize) {
        self.mix_wave(start, duration, amp, fade_samples, |_, _| 1.0);
    }

    fn mix_sweep(
        &mut self,
        start: usize,
        duration: usize,
        start_freq: f32,
        end_freq: f32,
        amp: f32,
        fade_samples: usize,
    ) {
        let total_seconds = duration as f32 / self.sample_rate as f32;
        let k = (end_freq - start_freq) / total_seconds;
        self.mix_wave(start, duration, amp, fade_samples, |_, t| {
            (2.0 * PI * (start_freq * t + 0.5 * k * t * t)).sin()
        });
    }
}

pub fn generate_structured_signal(path: impl AsRef<Path>) -> Result<StructuredSignal> {
    let path = path.as_ref().to_path_buf();
    let mut markers: Vec<MarkerSpec> = Vec::new();
    let mut builder = SignalBuilder::new(SAMPLE_RATE);

    // Low-level pre-roll hum that overlaps the first marker.
    let preroll_ms = 520;
    let preroll_len = ms_to_samples(preroll_ms);
    let preroll_fade = preroll_len / 8;
    builder.mix_sine(0, preroll_len, 120.0, 0.09, preroll_fade);
    markers.push(MarkerSpec {
        id: "warmup".into(),
        kind: MarkerKind::Chirp {
            start_freq: 120,
            end_freq: 120,
            duration_ms: preroll_ms,
        },
        start_sample: 0,
        duration_samples: preroll_len as u32,
    });

    let mut cursor: usize = ms_to_samples(320);

    // Leading click with soft envelope.
    let click_a_len = ms_to_samples(12);
    builder.mix_constant(cursor, click_a_len, 0.72, click_a_len / 2);
    markers.push(MarkerSpec {
        id: "click_a".into(),
        kind: MarkerKind::Click,
        start_sample: cursor as u32,
        duration_samples: click_a_len as u32,
    });
    cursor += click_a_len;
    cursor += ms_to_samples(20);

    // Sweep anchor for robust detection.
    let sweep_ms = 150;
    let sweep_len = ms_to_samples(sweep_ms);
    let sweep_start = cursor;
    builder.mix_sweep(sweep_start, sweep_len, 400.0, 9_000.0, 0.65, sweep_len / 10);
    markers.push(MarkerSpec {
        id: "sweep_anchor".into(),
        kind: MarkerKind::Chirp {
            start_freq: 400,
            end_freq: 9_000,
            duration_ms: sweep_ms,
        },
        start_sample: sweep_start as u32,
        duration_samples: sweep_len as u32,
    });
    cursor += sweep_len;
    cursor += ms_to_samples(200);

    // Multi-tone markers.
    let chirp_duration_ms = 120;
    let chirp_len = ms_to_samples(chirp_duration_ms);
    let gap_ms = 260;
    let freqs = [800, 1_000, 3_000, 6_000, 8_000, 10_000, 4_000];
    for (idx, freq) in freqs.iter().enumerate() {
        let start = cursor;
        builder.mix_sine(start, chirp_len, *freq as f32, 0.85, chirp_len / 12);
        markers.push(MarkerSpec {
            id: format!("chirp_{}", idx + 1),
            kind: MarkerKind::Chirp {
                start_freq: *freq,
                end_freq: *freq,
                duration_ms: chirp_duration_ms,
            },
            start_sample: start as u32,
            duration_samples: chirp_len as u32,
        });
        cursor += chirp_len;
        cursor += ms_to_samples(gap_ms);
    }

    // Trailing click and warm-down hum to avoid pops at the end.
    cursor += ms_to_samples(200);
    let click_b_len = ms_to_samples(14);
    let click_b_start = cursor;
    builder.mix_constant(click_b_start, click_b_len, 0.45, (click_b_len * 3) / 4);
    markers.push(MarkerSpec {
        id: "click_b".into(),
        kind: MarkerKind::Click,
        start_sample: click_b_start as u32,
        duration_samples: click_b_len as u32,
    });
    cursor += click_b_len;
    cursor += ms_to_samples(60);

    let warmdown_ms = 220;
    let warmdown_len = ms_to_samples(warmdown_ms);
    let warmdown_start = cursor;
    builder.mix_sine(warmdown_start, warmdown_len, 200.0, 0.035, warmdown_len / 8);
    markers.push(MarkerSpec {
        id: "warmdown".into(),
        kind: MarkerKind::Chirp {
            start_freq: 200,
            end_freq: 200,
            duration_ms: warmdown_ms,
        },
        start_sample: warmdown_start as u32,
        duration_samples: warmdown_len as u32,
    });
    cursor += warmdown_len;

    let target_len = ms_to_samples(TARGET_LENGTH_MS).max(cursor);
    builder.ensure_len(target_len);
    let length_samples = builder.len() as u32;

    let pcm: Vec<i16> = builder
        .samples
        .iter()
        .map(|s| (s.clamp(-0.97, 0.97) * i16::MAX as f32) as i16)
        .collect();

    let spec = hound::WavSpec {
        channels: 1,
        sample_rate: SAMPLE_RATE,
        bits_per_sample: 16,
        sample_format: hound::SampleFormat::Int,
    };
    let mut writer = WavWriter::create(&path, spec)?;
    for s in pcm.iter() {
        writer.write_sample(*s)?;
    }
    writer.finalize()?;

    let signal_spec = CalibrationSignalSpec {
        sample_rate: SAMPLE_RATE,
        length_samples,
        markers,
    };

    Ok(StructuredSignal {
        spec: signal_spec,
        path,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use hound::WavReader;
    use tempfile::tempdir;

    #[test]
    fn generates_markers_and_file() {
        let dir = tempdir().unwrap();
        let path = dir.path().join("structured.wav");
        let signal = generate_structured_signal(&path).unwrap();
        assert!(path.exists());
        assert_eq!(signal.spec.sample_rate, SAMPLE_RATE);
        assert!(signal.spec.length_samples >= ms_to_samples(4_000) as u32);
        assert!(signal.spec.length_samples <= ms_to_samples(5_000) as u32);
        assert!(signal.spec.markers.len() >= 10);
        assert!(signal
            .spec
            .markers
            .windows(2)
            .all(|w| w[0].start_sample < w[1].start_sample));
        let max_start = signal
            .spec
            .markers
            .iter()
            .map(|m| m.start_sample + m.duration_samples)
            .max()
            .unwrap();
        assert!(max_start <= signal.spec.length_samples);
    }

    #[test]
    fn envelope_has_headroom_and_bounded_derivative() {
        let dir = tempdir().unwrap();
        let path = dir.path().join("structured.wav");
        let signal = generate_structured_signal(&path).unwrap();
        let mut reader = WavReader::open(&path).unwrap();
        let samples: Vec<i16> = reader.samples::<i16>().map(|s| s.unwrap()).collect();
        assert_eq!(samples.len() as u32, signal.spec.length_samples);

        let max_abs = samples.iter().map(|s| (*s as i32).abs()).max().unwrap();
        let max_delta = samples
            .windows(2)
            .map(|w| ((w[1] as f32 - w[0] as f32) / i16::MAX as f32).abs())
            .fold(0.0f32, f32::max);

        assert!(max_abs as f32 <= 0.95 * i16::MAX as f32);
        assert!(max_delta <= 1.25);
    }

    #[test]
    fn includes_sweep_marker() {
        let dir = tempdir().unwrap();
        let path = dir.path().join("structured.wav");
        let signal = generate_structured_signal(&path).unwrap();
        let sweep = signal
            .spec
            .markers
            .iter()
            .find(|m| m.id == "sweep_anchor")
            .expect("sweep marker present");
        match sweep.kind {
            MarkerKind::Chirp {
                start_freq,
                end_freq,
                ..
            } => {
                assert!(start_freq < end_freq);
            }
            _ => panic!("sweep marker should be chirp"),
        }
    }
}
