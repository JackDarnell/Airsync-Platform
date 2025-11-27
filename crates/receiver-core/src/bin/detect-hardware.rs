use airsync_receiver_core::HardwareDetector;
use airsync_shared_protocol::{is_capable, MIN_CPU_CORES, MIN_RAM_MB};

fn main() {
    println!("AirSync Hardware Detection\n");
    println!("Detecting hardware capabilities...\n");

    let detector = HardwareDetector::from_system();

    match detector.detect() {
        Ok(capabilities) => {
            println!("Hardware Capabilities:");
            println!("  CPU Cores:        {}", capabilities.cpu_cores);
            println!("  RAM:              {} MB", capabilities.ram_mb);
            println!("  Board ID:         {}", capabilities.board_id);
            println!("  Audio Outputs:    {:?}", capabilities.audio_outputs);
            println!("  Preferred Output: {:?}", capabilities.preferred_output);

            println!("\nMinimum Requirements:");
            println!("  CPU Cores:        {} (required: {})",
                capabilities.cpu_cores, MIN_CPU_CORES);
            println!("  RAM:              {} MB (required: {} MB)",
                capabilities.ram_mb, MIN_RAM_MB);
            println!("  Audio Outputs:    {} (required: at least 1)",
                capabilities.audio_outputs.len());

            if is_capable(&capabilities) {
                println!("\n✓ System is CAPABLE - AirSync will run with high-quality configuration:");
                println!("  - Soxr interpolation (best audio quality)");
                println!("  - Cover art enabled");
                println!("  - 0.1s audio buffer");
                println!("  - Full AirPlay 2 support including multi-room sync");
            } else {
                println!("\n✗ System is NOT CAPABLE - does not meet minimum requirements");
                println!("  Supported hardware: Raspberry Pi 4 (1GB+), Pi 5, Pi 400");
                std::process::exit(1);
            }
        }
        Err(e) => {
            eprintln!("Error detecting hardware: {}", e);
            std::process::exit(1);
        }
    }
}
