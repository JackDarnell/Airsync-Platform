use airsync_shared_protocol::AudioOutput;
use std::fs;
use std::io;
use std::path::Path;

#[derive(Clone, Debug, PartialEq)]
pub struct ShairportConfig {
    pub device_name: String,
    pub output_device: String,
    pub latency_offset_seconds: f32,
}

/// Generate high-quality shairport-sync configuration
/// All capable systems use the same configuration:
/// - Soxr interpolation for best audio quality
/// - Cover art enabled
/// - 0.1s audio buffer
pub fn generate_config(
    device_name: Option<&str>,
    preferred_output: AudioOutput,
) -> ShairportConfig {
    let output_device = match preferred_output {
        AudioOutput::I2S => "hw:0,0".to_string(),
        AudioOutput::USB => "hw:1,0".to_string(),
        AudioOutput::HDMI => "hdmi".to_string(),
        AudioOutput::Headphone => "hw:0,0".to_string(),
    };

    ShairportConfig {
        device_name: device_name
            .map(String::from)
            .unwrap_or_else(|| "AirSync".to_string()),
        output_device,
        latency_offset_seconds: 0.0,
    }
}

pub fn render_config_file(config: &ShairportConfig) -> String {
    format!(
        r#"general = {{
    name = "{name}";
    interpolation = "soxr";
    output_backend = "alsa";
    audio_backend_latency_offset_in_seconds = {latency_offset};
}};

alsa = {{
    output_device = "{output_device}";
    audio_backend_buffer_desired_length_in_seconds = 0.1;
    output_rate = "auto"; // Let ALSA choose optimal rate
    output_format = "S16"; // Standard 16-bit signed integer format
    disable_synchronization = "no"; // Keep synchronization enabled
}};

metadata = {{
    enabled = "yes";
    include_cover_art = "yes";
    pipe_name = "/tmp/shairport-sync-metadata";
}};

sessioncontrol = {{
    session_timeout = 20;
}};
"#,
        name = config.device_name,
        output_device = config.output_device,
        latency_offset = format!("{:.3}", config.latency_offset_seconds),
    )
}

/// Write shairport-sync configuration to a file
/// This is used by the installer to generate /etc/shairport-sync.conf
pub fn write_config_file<P: AsRef<Path>>(
    config: &ShairportConfig,
    path: P,
) -> io::Result<()> {
    let rendered = render_config_file(config);
    fs::write(path, rendered)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn generates_high_quality_config() {
        let config = generate_config(None, AudioOutput::Headphone);

        assert_eq!(config.device_name, "AirSync");
        assert_eq!(config.output_device, "hw:0,0");
    }

    #[test]
    fn uses_custom_device_name_when_provided() {
        let config = generate_config(Some("Living Room"), AudioOutput::Headphone);

        assert_eq!(config.device_name, "Living Room");
    }

    #[test]
    fn selects_correct_output_device_for_i2s() {
        let config = generate_config(None, AudioOutput::I2S);
        assert_eq!(config.output_device, "hw:0,0");
    }

    #[test]
    fn selects_correct_output_device_for_usb() {
        let config = generate_config(None, AudioOutput::USB);
        assert_eq!(config.output_device, "hw:1,0");
    }

    #[test]
    fn selects_correct_output_device_for_hdmi() {
        let config = generate_config(None, AudioOutput::HDMI);
        assert_eq!(config.output_device, "hdmi");
    }

    #[test]
    fn renders_valid_config_file() {
        let config = generate_config(Some("Test Device"), AudioOutput::Headphone);
        let rendered = render_config_file(&config);

        assert!(rendered.contains("name = \"Test Device\""));
        assert!(rendered.contains("interpolation = \"soxr\""));
        assert!(rendered.contains("output_device = \"hw:0,0\""));
        assert!(rendered.contains("audio_backend_buffer_desired_length_in_seconds = 0.1"));
        assert!(rendered.contains("include_cover_art = \"yes\""));
        assert!(rendered.contains("enabled = \"yes\""));
        assert!(rendered.contains("audio_backend_latency_offset_in_seconds = 0.000"));
    }

    #[test]
    fn always_uses_soxr_interpolation() {
        let config = generate_config(None, AudioOutput::Headphone);
        let rendered = render_config_file(&config);

        assert!(rendered.contains("interpolation = \"soxr\""));
    }

    #[test]
    fn always_enables_cover_art() {
        let config = generate_config(None, AudioOutput::Headphone);
        let rendered = render_config_file(&config);

        assert!(rendered.contains("include_cover_art = \"yes\""));
    }

    #[test]
    fn uses_optimal_buffer_length() {
        let config = generate_config(None, AudioOutput::Headphone);
        let rendered = render_config_file(&config);

        assert!(rendered.contains("audio_backend_buffer_desired_length_in_seconds = 0.1"));
    }

    #[test]
    fn renders_latency_offset_when_present() {
        let mut config = generate_config(None, AudioOutput::USB);
        config.latency_offset_seconds = -0.055;

        let rendered = render_config_file(&config);

        assert!(rendered.contains("audio_backend_latency_offset_in_seconds = -0.055"));
    }

    #[test]
    fn config_prevents_soxr_crash_with_proper_alsa_settings() {
        // This test ensures the generated config includes all necessary ALSA settings
        // to prevent the soxr segfault crash that occurred during playback.
        // The crash happened because channel layout was not properly initialized.

        let config = generate_config(Some("Test Device"), AudioOutput::Headphone);
        let rendered = render_config_file(&config);

        // Must have ALSA section with output device
        assert!(rendered.contains("alsa = {"), "Config must have alsa section");
        assert!(rendered.contains("output_device = \"hw:0,0\""), "Must specify ALSA output device");

        // Must have buffer size to ensure proper initialization
        assert!(rendered.contains("audio_backend_buffer_desired_length_in_seconds"),
                "Must specify audio buffer size");

        // Must use soxr interpolation
        assert!(rendered.contains("interpolation = \"soxr\""),
                "Must use soxr interpolation for quality");
    }

    #[test]
    fn write_config_file_creates_valid_file() {
        use std::fs;

        let temp_dir = std::env::temp_dir();
        let config_path = temp_dir.join("test-shairport-sync.conf");

        // Clean up any existing file
        let _ = fs::remove_file(&config_path);

        let config = generate_config(Some("TestDevice"), AudioOutput::I2S);

        // This function doesn't exist yet - we'll create it
        let result = write_config_file(&config, &config_path);

        assert!(result.is_ok(), "Should successfully write config file");
        assert!(config_path.exists(), "Config file should exist");

        // Verify contents
        let contents = fs::read_to_string(&config_path).unwrap();
        assert!(contents.contains("name = \"TestDevice\""));
        assert!(contents.contains("output_device = \"hw:0,0\""));

        // Clean up
        let _ = fs::remove_file(&config_path);
    }

    #[test]
    fn config_includes_explicit_audio_format_to_prevent_channel_layout_error() {
        // This test ensures the config explicitly sets audio format and rate
        // to prevent the ffmpeg/soxr channel layout initialization error.
        // The crash was: "Input channel layout \"\" is invalid or unsupported"
        // Solution: Explicitly configure ALSA audio format parameters

        let config = generate_config(Some("Test"), AudioOutput::Headphone);
        let rendered = render_config_file(&config);

        // Must specify output rate to ensure proper channel initialization
        assert!(rendered.contains("output_rate"),
                "Config must specify output_rate for proper ALSA initialization");

        // Must specify output format for channel layout
        assert!(rendered.contains("output_format"),
                "Config must specify output_format to define channel layout");

        // Should not disable synchronization (needed for proper audio sync)
        assert!(rendered.contains("disable_synchronization"),
                "Config should explicitly set disable_synchronization");
    }
}
