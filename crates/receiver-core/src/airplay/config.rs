use airsync_shared_protocol::AudioOutput;

pub struct ShairportConfig {
    pub device_name: String,
    pub output_device: String,
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
    }
}

pub fn render_config_file(config: &ShairportConfig) -> String {
    format!(
        r#"general = {{
    name = "{name}";
    interpolation = "soxr";
    output_backend = "alsa";
}};

alsa = {{
    output_device = "{output_device}";
    audio_backend_buffer_desired_length_in_seconds = 0.1;
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
    )
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
}
