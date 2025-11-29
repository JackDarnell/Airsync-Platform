use airsync_receiver_core::HardwareDetector;
use airsync_receiver_core::airplay::{generate_config, write_config_file};
use airsync_shared_protocol::AudioOutput;
use std::env;
use std::path::PathBuf;
use std::process;

fn parse_audio_output(device: &str) -> AudioOutput {
    // Try to determine audio output type from hw:X,Y format
    // This is a simple heuristic - hw:0,0 is usually headphone/I2S
    // hw:0,1 is usually HDMI, hw:1,0 is usually USB
    match device {
        d if d.starts_with("hdmi") => AudioOutput::HDMI,
        d if d.starts_with("hw:1,") => AudioOutput::USB,
        d if d.starts_with("hw:0,1") => AudioOutput::HDMI,
        _ => AudioOutput::Headphone, // Default for hw:0,0 and others
    }
}

fn main() {
    let args: Vec<String> = env::args().collect();

    if args.len() < 2 {
        eprintln!("Usage: generate-config <output-path> [device-name] [--device hw:X,Y]");
        eprintln!("\nExamples:");
        eprintln!("  generate-config /etc/shairport-sync.conf");
        eprintln!("  generate-config /etc/shairport-sync.conf \"Living Room\"");
        eprintln!("  generate-config /etc/shairport-sync.conf \"Kitchen\" --device hw:1,0");
        process::exit(1);
    }

    let output_path = PathBuf::from(&args[1]);

    // Parse arguments
    let mut device_name = None;
    let mut device_override = None;

    let mut i = 2;
    while i < args.len() {
        match args[i].as_str() {
            "--device" => {
                if i + 1 < args.len() {
                    device_override = Some(args[i + 1].clone());
                    i += 2;
                } else {
                    eprintln!("Error: --device flag requires a value (e.g., hw:0,0)");
                    process::exit(1);
                }
            }
            arg if !arg.starts_with("--") => {
                device_name = Some(arg.to_string());
                i += 1;
            }
            _ => {
                eprintln!("Error: Unknown flag: {}", args[i]);
                process::exit(1);
            }
        }
    }

    println!("AirSync Config Generator\n");

    // Determine audio output
    let audio_output = if let Some(device) = &device_override {
        println!("Using specified device: {}", device);
        parse_audio_output(device)
    } else {
        println!("Detecting hardware...");
        let detector = HardwareDetector::from_system();
        match detector.detect() {
            Ok(caps) => {
                println!("  Preferred audio output: {:?}", caps.preferred_output);
                caps.preferred_output
            }
            Err(e) => {
                eprintln!("Error detecting hardware: {}", e);
                eprintln!("Using default configuration with headphone output");
                AudioOutput::Headphone
            }
        }
    };

    println!("  Device name: {}", device_name.as_deref().unwrap_or("AirSync"));

    // Generate configuration
    let mut config = generate_config(device_name.as_deref(), audio_output);

    // Override output device if specified
    if let Some(device) = device_override {
        config.output_device = device;
    }

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
