use airsync_shared_protocol::ChirpConfig;
use std::f32::consts::PI;

pub fn generate_chirp_samples(cfg: &ChirpConfig, sample_rate: u32, gain: f32) -> Vec<i16> {
    let sr = sample_rate as f32;
    let duration_s = cfg.duration as f32 / 1000.0;
    let interval_s = cfg.interval_ms as f32 / 1000.0;
    let sweep_k = (cfg.end_freq as f32 - cfg.start_freq as f32) / duration_s;
    let single = (0..(duration_s * sr) as usize)
        .map(|n| {
            let t = n as f32 / sr;
            let phase = 2.0 * PI * (cfg.start_freq as f32 * t + 0.5 * sweep_k * t * t / duration_s);
            let sample = (phase.sin() * gain.clamp(0.0, 1.0) * i16::MAX as f32).round();
            sample as i16
        })
        .collect::<Vec<_>>();
    let silence = (0..(interval_s * sr) as usize).map(|_| 0i16).collect::<Vec<_>>();
    let mut out = Vec::new();
    for _ in 0..cfg.repetitions.max(1) {
        out.extend_from_slice(&single);
        out.extend_from_slice(&silence);
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn chirp_samples_have_energy() {
        let cfg = ChirpConfig {
            start_freq: 1000,
            end_freq: 10000,
            duration: 100,
            repetitions: 2,
            interval_ms: 100,
        };
        let samples = generate_chirp_samples(&cfg, 48_000, 1.0);
        assert!(samples.iter().any(|&s| s != 0));
        let expected_min = (cfg.duration as f32 / 1000.0 * 48000.0) as usize * 2;
        assert!(samples.len() >= expected_min);
    }
}
