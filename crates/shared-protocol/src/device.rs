use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct HardwareCapabilities {
    pub cpu_cores: usize,
    pub ram_mb: usize,
    pub board_id: String,
    pub audio_outputs: Vec<AudioOutput>,
    pub preferred_output: AudioOutput,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum AudioOutput {
    I2S,
    USB,
    HDMI,
    Headphone,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct FeatureSet {
    pub airplay: bool,
    pub web_ui: bool,
    pub local_tts: bool,
    pub calibration: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct HardwareProfile {
    pub id: ProfileId,
    pub min_cores: usize,
    pub min_ram_mb: usize,
    pub features: FeatureSet,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ProfileId {
    Minimal,
    Standard,
    Enhanced,
}

pub const HARDWARE_PROFILES: &[HardwareProfile] = &[
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
    },
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
    },
    HardwareProfile {
        id: ProfileId::Enhanced,
        min_cores: 4,
        min_ram_mb: 4096,
        features: FeatureSet {
            airplay: true,
            web_ui: true,
            local_tts: true,
            calibration: true,
        },
    },
];

pub fn select_hardware_profile(capabilities: &HardwareCapabilities) -> &'static HardwareProfile {
    let mut profiles: Vec<_> = HARDWARE_PROFILES.iter().collect();
    profiles.sort_by(|a, b| b.min_ram_mb.cmp(&a.min_ram_mb));

    for profile in profiles {
        if capabilities.cpu_cores >= profile.min_cores
            && capabilities.ram_mb >= profile.min_ram_mb
        {
            return profile;
        }
    }

    &HARDWARE_PROFILES[0]
}

#[cfg(test)]
mod tests {
    use super::*;

    fn create_capabilities(ram_mb: usize, cpu_cores: usize) -> HardwareCapabilities {
        HardwareCapabilities {
            cpu_cores,
            ram_mb,
            board_id: "test".to_string(),
            audio_outputs: vec![AudioOutput::Headphone],
            preferred_output: AudioOutput::Headphone,
        }
    }

    #[test]
    fn selects_minimal_profile_for_low_ram() {
        let caps = create_capabilities(256, 4);
        let profile = select_hardware_profile(&caps);
        assert_eq!(profile.id, ProfileId::Minimal);
        assert!(!profile.features.web_ui);
    }

    #[test]
    fn selects_standard_profile_for_1gb_ram() {
        let caps = create_capabilities(1024, 4);
        let profile = select_hardware_profile(&caps);
        assert_eq!(profile.id, ProfileId::Standard);
        assert!(profile.features.web_ui);
        assert!(!profile.features.local_tts);
    }

    #[test]
    fn selects_enhanced_profile_for_4gb_ram() {
        let caps = create_capabilities(4096, 4);
        let profile = select_hardware_profile(&caps);
        assert_eq!(profile.id, ProfileId::Enhanced);
        assert!(profile.features.web_ui);
        assert!(profile.features.local_tts);
    }

    #[test]
    fn falls_back_to_minimal_for_insufficient_resources() {
        let caps = create_capabilities(128, 4);
        let profile = select_hardware_profile(&caps);
        assert_eq!(profile.id, ProfileId::Minimal);
    }

    #[test]
    fn selects_highest_profile_that_fits() {
        let caps = create_capabilities(2048, 4);
        let profile = select_hardware_profile(&caps);
        assert_eq!(profile.id, ProfileId::Standard);
    }
}
