use airsync_shared_protocol::{AudioOutput, HardwareProfile};

pub struct ShairportConfig {
    pub device_name: String,
    pub output_device: String,
    pub interpolation: InterpolationMethod,
    pub buffer_length: f32,
    pub metadata_enabled: bool,
    pub cover_art_enabled: bool,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum InterpolationMethod {
    Basic,
    Soxr,
}

pub fn generate_config_from_profile(
    profile: &HardwareProfile,
    device_name: Option<&str>,
    preferred_output: AudioOutput,
) -> ShairportConfig {
    let interpolation = match profile.id {
        airsync_shared_protocol::ProfileId::Minimal => InterpolationMethod::Basic,
        _ => InterpolationMethod::Soxr,
    };

    let buffer_length = match profile.id {
        airsync_shared_protocol::ProfileId::Minimal => 0.15,
        _ => 0.1,
    };

    let cover_art_enabled = profile.min_ram_mb > 512;

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
        interpolation,
        buffer_length,
        metadata_enabled: true,
        cover_art_enabled,
    }
}

pub fn render_config_file(config: &ShairportConfig) -> String {
    let interpolation_str = match config.interpolation {
        InterpolationMethod::Basic => "basic",
        InterpolationMethod::Soxr => "soxr",
    };

    format!(
        r#"general = {{
    name = "{name}";
    interpolation = "{interpolation}";
    output_backend = "alsa";
}};

alsa = {{
    output_device = "{output_device}";
    audio_backend_buffer_desired_length_in_seconds = {buffer_length};
}};

metadata = {{
    enabled = "{metadata}";
    include_cover_art = "{cover_art}";
    pipe_name = "/tmp/shairport-sync-metadata";
}};

sessioncontrol = {{
    session_timeout = 20;
}};
"#,
        name = config.device_name,
        interpolation = interpolation_str,
        output_device = config.output_device,
        buffer_length = config.buffer_length,
        metadata = if config.metadata_enabled { "yes" } else { "no" },
        cover_art = if config.cover_art_enabled { "yes" } else { "no" },
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use airsync_shared_protocol::{FeatureSet, ProfileId};

    fn minimal_profile() -> HardwareProfile {
        HardwareProfile {
            id: ProfileId::Minimal,
            min_cores: 4,
            min_ram_mb: 256,
            features: FeatureSet {
                airplay: true,
                web_ui: false,
                local_tts: false,
                calibration: true,
            },
        }
    }

    fn standard_profile() -> HardwareProfile {
        HardwareProfile {
            id: ProfileId::Standard,
            min_cores: 4,
            min_ram_mb: 1024,
            features: FeatureSet {
                airplay: true,
                web_ui: true,
                local_tts: false,
                calibration: true,
            },
        }
    }

    #[test]
    fn generates_basic_interpolation_for_minimal_profile() {
        let config = generate_config_from_profile(
            &minimal_profile(),
            None,
            AudioOutput::Headphone,
        );

        assert_eq!(config.interpolation, InterpolationMethod::Basic);
    }

    #[test]
    fn generates_soxr_interpolation_for_standard_profile() {
        let config = generate_config_from_profile(
            &standard_profile(),
            None,
            AudioOutput::Headphone,
        );

        assert_eq!(config.interpolation, InterpolationMethod::Soxr);
    }

    #[test]
    fn uses_longer_buffer_for_minimal_profile() {
        let config = generate_config_from_profile(
            &minimal_profile(),
            None,
            AudioOutput::Headphone,
        );

        assert_eq!(config.buffer_length, 0.15);
    }

    #[test]
    fn disables_cover_art_for_low_memory() {
        let config = generate_config_from_profile(
            &minimal_profile(),
            None,
            AudioOutput::Headphone,
        );

        assert!(!config.cover_art_enabled);
    }

    #[test]
    fn enables_cover_art_for_sufficient_memory() {
        let config = generate_config_from_profile(
            &standard_profile(),
            None,
            AudioOutput::Headphone,
        );

        assert!(config.cover_art_enabled);
    }

    #[test]
    fn uses_custom_device_name_when_provided() {
        let config = generate_config_from_profile(
            &minimal_profile(),
            Some("Living Room"),
            AudioOutput::Headphone,
        );

        assert_eq!(config.device_name, "Living Room");
    }

    #[test]
    fn selects_correct_output_device_for_i2s() {
        let config = generate_config_from_profile(
            &minimal_profile(),
            None,
            AudioOutput::I2S,
        );

        assert_eq!(config.output_device, "hw:0,0");
    }

    #[test]
    fn selects_correct_output_device_for_usb() {
        let config = generate_config_from_profile(
            &minimal_profile(),
            None,
            AudioOutput::USB,
        );

        assert_eq!(config.output_device, "hw:1,0");
    }

    #[test]
    fn renders_valid_config_file() {
        let config = ShairportConfig {
            device_name: "Test Device".to_string(),
            output_device: "hw:0,0".to_string(),
            interpolation: InterpolationMethod::Soxr,
            buffer_length: 0.1,
            metadata_enabled: true,
            cover_art_enabled: true,
        };

        let rendered = render_config_file(&config);

        assert!(rendered.contains("name = \"Test Device\""));
        assert!(rendered.contains("interpolation = \"soxr\""));
        assert!(rendered.contains("output_device = \"hw:0,0\""));
        assert!(rendered.contains("include_cover_art = \"yes\""));
    }

    #[test]
    fn rendered_config_uses_basic_interpolation_when_specified() {
        let config = ShairportConfig {
            device_name: "Basic".to_string(),
            output_device: "hw:0,0".to_string(),
            interpolation: InterpolationMethod::Basic,
            buffer_length: 0.15,
            metadata_enabled: true,
            cover_art_enabled: false,
        };

        let rendered = render_config_file(&config);

        assert!(rendered.contains("interpolation = \"basic\""));
        assert!(rendered.contains("include_cover_art = \"no\""));
    }
}
