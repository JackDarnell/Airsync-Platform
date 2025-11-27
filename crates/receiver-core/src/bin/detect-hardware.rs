use airsync_receiver_core::HardwareDetector;
use airsync_shared_protocol::select_hardware_profile;

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

            let profile = select_hardware_profile(&capabilities);
            println!("\nSelected Profile: {:?}", profile.id);
            println!("  Features:");
            println!("    AirPlay:        {}", profile.features.airplay);
            println!("    Web UI:         {}", profile.features.web_ui);
            println!("    Local TTS:      {}", profile.features.local_tts);
            println!("    Calibration:    {}", profile.features.calibration);
        }
        Err(e) => {
            eprintln!("Error detecting hardware: {}", e);
            std::process::exit(1);
        }
    }
}
