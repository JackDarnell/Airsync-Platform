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

/// Minimum requirements for AirPlay 2 receiver
pub const MIN_CPU_CORES: usize = 4;
pub const MIN_RAM_MB: usize = 1024; // AirPlay 2 requires at least 1GB for reliable performance

/// Check if hardware meets minimum requirements to run AirSync
pub fn is_capable(capabilities: &HardwareCapabilities) -> bool {
    capabilities.cpu_cores >= MIN_CPU_CORES
        && capabilities.ram_mb >= MIN_RAM_MB
        && !capabilities.audio_outputs.is_empty()
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
    fn accepts_raspberry_pi_4_1gb() {
        let caps = create_capabilities(1024, 4);
        assert!(is_capable(&caps));
    }

    #[test]
    fn accepts_raspberry_pi_4_2gb() {
        let caps = create_capabilities(2048, 4);
        assert!(is_capable(&caps));
    }

    #[test]
    fn accepts_raspberry_pi_5_4gb() {
        let caps = create_capabilities(4096, 4);
        assert!(is_capable(&caps));
    }

    #[test]
    fn rejects_raspberry_pi_zero_2w_insufficient_ram() {
        let caps = create_capabilities(512, 4); // Has 4 cores but only 512MB RAM
        assert!(!is_capable(&caps));
    }

    #[test]
    fn rejects_raspberry_pi_zero_w_insufficient_cores_and_ram() {
        let caps = create_capabilities(512, 1); // Only 1 core and 512MB RAM
        assert!(!is_capable(&caps));
    }

    #[test]
    fn rejects_system_without_audio() {
        let caps = HardwareCapabilities {
            cpu_cores: 4,
            ram_mb: 2048,
            board_id: "test".to_string(),
            audio_outputs: vec![], // No audio outputs
            preferred_output: AudioOutput::Headphone,
        };
        assert!(!is_capable(&caps));
    }
}
