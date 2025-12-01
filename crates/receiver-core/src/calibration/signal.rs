use airsync_shared_protocol::{CalibrationSignalSpec, MarkerKind, MarkerSpec};
use anyhow::Result;
use hound::WavWriter;
use std::f32::consts::PI;
use std::path::{Path, PathBuf};

#[derive(Clone)]
pub struct StructuredSignal {
    pub spec: CalibrationSignalSpec,
    pub path: PathBuf,
}

pub fn generate_structured_signal(path: impl AsRef<Path>) -> Result<StructuredSignal> {
    let path = path.as_ref().to_path_buf();
    let sample_rate = 48_000u32;
    let mut samples: Vec<i16> = Vec::new();
    let mut markers: Vec<MarkerSpec> = Vec::new();

    // Helpers
    let mut cursor: usize = 0;

    let push_silence = |ms: u32, samples: &mut Vec<i16>, cursor: &mut usize| {
        let count = (ms as usize * sample_rate as usize) / 1000;
        samples.extend(std::iter::repeat(0i16).take(count));
        *cursor += count;
    };

    let push_click = |id: &str,
                          duration_ms: u32,
                          amp: f32,
                          samples: &mut Vec<i16>,
                          cursor: &mut usize,
                          markers: &mut Vec<MarkerSpec>| {
        let len = (duration_ms as usize * sample_rate as usize) / 1000;
        let start = *cursor;
        for _ in 0..len {
            samples.push((amp * i16::MAX as f32) as i16);
        }
        *cursor += len;
        markers.push(MarkerSpec {
            id: id.to_string(),
            kind: MarkerKind::Click,
            start_sample: start as u32,
            duration_samples: len as u32,
        });
    };

    let push_tone = |id: &str,
                         freq_hz: u32,
                         duration_ms: u32,
                         amp: f32,
                         samples: &mut Vec<i16>,
                         cursor: &mut usize,
                         markers: &mut Vec<MarkerSpec>| {
        let len = (duration_ms as usize * sample_rate as usize) / 1000;
        let start = *cursor;
        let sr = sample_rate as f32;
        let window = len.saturating_sub(1) as f32;
        for n in 0..len {
            let t = n as f32 / sr;
            let phase = 2.0 * PI * freq_hz as f32 * t;
            let w = 0.5 * (1.0 - (2.0 * PI * n as f32 / window).cos());
            let sample = (phase.sin() * amp * w * i16::MAX as f32) as i16;
            samples.push(sample);
        }
        *cursor += len;
        markers.push(MarkerSpec {
            id: id.to_string(),
            kind: MarkerKind::Chirp {
                start_freq: freq_hz,
                end_freq: freq_hz,
                duration_ms,
            },
            start_sample: start as u32,
            duration_samples: len as u32,
        });
    };

    let push_hum = |id: &str,
                        freq_hz: u32,
                        duration_ms: u32,
                        amp: f32,
                        samples: &mut Vec<i16>,
                        cursor: &mut usize,
                        markers: &mut Vec<MarkerSpec>| {
        let len = (duration_ms as usize * sample_rate as usize) / 1000;
        let start = *cursor;
        let sr = sample_rate as f32;
        for n in 0..len {
            let t = n as f32 / sr;
            let phase = 2.0 * PI * freq_hz as f32 * t;
            let sample = (phase.sin() * amp * i16::MAX as f32) as i16;
            samples.push(sample);
        }
        *cursor += len;
        markers.push(MarkerSpec {
            id: id.to_string(),
            kind: MarkerKind::Chirp {
                start_freq: freq_hz,
                end_freq: freq_hz,
                duration_ms,
            },
            start_sample: start as u32,
            duration_samples: len as u32,
        });
    };

    // Build signal
    push_hum("warmup", 120, 400, 0.12, &mut samples, &mut cursor, &mut markers);
    push_silence(80, &mut samples, &mut cursor);
    push_click("click_a", 10, 0.9, &mut samples, &mut cursor, &mut markers);
    push_silence(200, &mut samples, &mut cursor);

    let chirp_duration_ms = 100;
    let gap_ms = 280;
    let freqs = [800, 1_000, 3_000, 6_000, 8_000, 10_000, 4_000];
    for (idx, freq) in freqs.iter().enumerate() {
        push_tone(
            &format!("chirp_{}", idx + 1),
            *freq,
            chirp_duration_ms,
            0.9,
            &mut samples,
            &mut cursor,
            &mut markers,
        );
        push_silence(gap_ms, &mut samples, &mut cursor);
    }

    // trailing silence then final click near end
    push_silence(200, &mut samples, &mut cursor);
    push_click("click_b", 10, 0.4, &mut samples, &mut cursor, &mut markers);

    // trailing hum to keep path alive briefly
    push_silence(60, &mut samples, &mut cursor);
    push_hum("warmdown", 200, 200, 0.05, &mut samples, &mut cursor, &mut markers);

    // Ensure total length ~5s by padding if needed
    let target_len = (5_000u32 as usize * sample_rate as usize) / 1000;
    if cursor < target_len {
        samples.extend(std::iter::repeat(0i16).take(target_len - cursor));
        cursor = target_len;
    }

    let spec = hound::WavSpec {
        channels: 1,
        sample_rate,
        bits_per_sample: 16,
        sample_format: hound::SampleFormat::Int,
    };
    let mut writer = WavWriter::create(&path, spec)?;
    for s in samples.iter() {
        writer.write_sample(*s)?;
    }
    writer.finalize()?;

    let signal_spec = CalibrationSignalSpec {
        sample_rate,
        length_samples: cursor as u32,
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
    use tempfile::tempdir;

    #[test]
    fn generates_markers_and_file() {
        let dir = tempdir().unwrap();
        let path = dir.path().join("structured.wav");
        let signal = generate_structured_signal(&path).unwrap();
        assert!(path.exists());
        assert!(signal.spec.markers.len() >= 6);
        assert!(signal.spec.length_samples > 200_000); // ~>4s
        // Markers are ordered and within length
        let max_start = signal
            .spec
            .markers
            .iter()
            .map(|m| m.start_sample + m.duration_samples)
            .max()
            .unwrap();
        assert!(max_start <= signal.spec.length_samples);
    }
}
