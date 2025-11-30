use std::fs;
use std::path::PathBuf;

use airsync_receiver_core::chirp::generate_chirp_samples;
use airsync_shared_protocol::ChirpConfig;
use hound;

fn main() -> anyhow::Result<()> {
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 2 {
        eprintln!("Usage: generate-chirp-wav <output_path> [sample_rate] [gain]");
        std::process::exit(1);
    }
    let path = PathBuf::from(&args[1]);
    let sample_rate: u32 = args.get(2).and_then(|s| s.parse().ok()).unwrap_or(48_000);
    let gain: f32 = args.get(3).and_then(|s| s.parse().ok()).unwrap_or(1.0);

    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }

    let spec = hound::WavSpec {
        channels: 1,
        sample_rate,
        bits_per_sample: 16,
        sample_format: hound::SampleFormat::Int,
    };
    let mut writer = hound::WavWriter::create(&path, spec)?;
    let samples = generate_chirp_samples(&ChirpConfig::default(), sample_rate, gain);
    for s in samples {
        writer.write_sample(s)?;
    }
    writer.finalize()?;
    println!("Wrote chirp WAV to {}", path.display());
    Ok(())
}
