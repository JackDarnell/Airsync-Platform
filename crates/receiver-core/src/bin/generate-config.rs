use airsync_receiver_core::HardwareDetector;
use airsync_receiver_core::airplay::{generate_config, write_config_file};
use std::env;
use std::path::PathBuf;
use std::process;

fn main() {
    let args: Vec<String> = env::args().collect();

    if args.len() < 2 {
        eprintln!("Usage: generate-config <output-path> [device-name]");
        eprintln!("\nExample:");
        eprintln!("  generate-config /etc/shairport-sync.conf");
        eprintln!("  generate-config /etc/shairport-sync.conf \"Living Room\"");
        process::exit(1);
    }

    let output_path = PathBuf::from(&args[1]);
    let device_name = args.get(2).map(|s| s.as_str());

    println!("AirSync Config Generator\n");
    println!("Detecting hardware...");

    // Detect hardware to determine preferred audio output
    let detector = HardwareDetector::from_system();
    let capabilities = match detector.detect() {
        Ok(caps) => caps,
        Err(e) => {
            eprintln!("Error detecting hardware: {}", e);
            eprintln!("Using default configuration with headphone output");

            // Fallback config
            let fallback_config = generate_config(
                device_name,
                airsync_shared_protocol::AudioOutput::Headphone
            );

            if let Err(e) = write_config_file(&fallback_config, &output_path) {
                eprintln!("Failed to write config file: {}", e);
                process::exit(1);
            }

            println!("✓ Config file written to: {}", output_path.display());
            return;
        }
    };

    println!("  Preferred audio output: {:?}", capabilities.preferred_output);
    println!("  Device name: {}", device_name.unwrap_or("AirSync"));

    // Generate configuration based on detected hardware
    let config = generate_config(device_name, capabilities.preferred_output);

    // Write configuration file
    match write_config_file(&config, &output_path) {
        Ok(()) => {
            println!("\n✓ Config file written to: {}", output_path.display());
            println!("\nGenerated configuration:");
            println!("  - Audio output: {}", config.output_device);
            println!("  - Interpolation: soxr (high quality)");
            println!("  - Cover art: enabled");
            println!("  - Buffer: 0.1s");
            println!("  - Latency offset: {:.3}s", config.latency_offset_seconds);
            println!("\nThis configuration prevents the soxr crash by ensuring proper ALSA initialization.");
        }
        Err(e) => {
            eprintln!("Failed to write config file: {}", e);
            process::exit(1);
        }
    }
}
