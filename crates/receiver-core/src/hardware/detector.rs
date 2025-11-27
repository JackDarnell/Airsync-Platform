use airsync_shared_protocol::{AudioOutput, HardwareCapabilities};
use anyhow::Result;
use std::fs;
use std::process::Command;

pub trait SystemReaders: Send + Sync {
    fn read_cpu_info(&self) -> Result<String>;
    fn read_mem_info(&self) -> Result<String>;
    fn read_device_tree(&self) -> Result<Option<String>>;
    fn list_alsa_devices(&self) -> Result<String>;
}

pub struct DefaultSystemReaders;

impl SystemReaders for DefaultSystemReaders {
    fn read_cpu_info(&self) -> Result<String> {
        Ok(fs::read_to_string("/proc/cpuinfo")?)
    }

    fn read_mem_info(&self) -> Result<String> {
        Ok(fs::read_to_string("/proc/meminfo")?)
    }

    fn read_device_tree(&self) -> Result<Option<String>> {
        match fs::read_to_string("/proc/device-tree/model") {
            Ok(content) => Ok(Some(content)),
            Err(_) => Ok(None),
        }
    }

    fn list_alsa_devices(&self) -> Result<String> {
        let output = Command::new("aplay")
            .arg("-l")
            .output()
            .map_err(|e| anyhow::anyhow!("Failed to execute aplay: {}", e))?;

        Ok(String::from_utf8_lossy(&output.stdout).to_string())
    }
}

pub struct HardwareDetector<R: SystemReaders> {
    readers: R,
}

impl HardwareDetector<DefaultSystemReaders> {
    pub fn from_system() -> Self {
        Self {
            readers: DefaultSystemReaders,
        }
    }
}

impl<R: SystemReaders> HardwareDetector<R> {
    pub fn new(readers: R) -> Self {
        Self { readers }
    }

    pub fn detect(&self) -> Result<HardwareCapabilities> {
        let cpu_cores = self.detect_cpu_cores()?;
        let ram_mb = self.detect_memory()?;
        let board_id = self.detect_board_id()?;
        let audio_outputs = self.detect_audio_outputs()?;
        let preferred_output = self.select_preferred_output(&audio_outputs);

        Ok(HardwareCapabilities {
            cpu_cores,
            ram_mb,
            board_id,
            audio_outputs,
            preferred_output,
        })
    }

    fn detect_cpu_cores(&self) -> Result<usize> {
        let cpu_info = self.readers.read_cpu_info()?;
        let count = cpu_info.lines()
            .filter(|line| line.starts_with("processor"))
            .count();
        Ok(count.max(1))
    }

    fn detect_memory(&self) -> Result<usize> {
        let mem_info = self.readers.read_mem_info()?;

        for line in mem_info.lines() {
            if line.starts_with("MemTotal:") {
                let parts: Vec<&str> = line.split_whitespace().collect();
                if parts.len() >= 2 {
                    if let Ok(kb) = parts[1].parse::<usize>() {
                        return Ok(kb / 1024);
                    }
                }
            }
        }

        Ok(0)
    }

    fn detect_board_id(&self) -> Result<String> {
        let cpu_info = self.readers.read_cpu_info()?;

        for line in cpu_info.lines() {
            if line.starts_with("Model") {
                let model = line.split(':')
                    .nth(1)
                    .unwrap_or("")
                    .trim()
                    .to_lowercase();

                if model.contains("zero 2 w") {
                    return Ok("raspberry-pi-zero-2-w".to_string());
                } else if model.contains("pi 4") {
                    return Ok("raspberry-pi-4-model-b".to_string());
                } else if model.contains("pi 5") {
                    return Ok("raspberry-pi-5-model-b".to_string());
                }
            }
        }

        Ok("unknown".to_string())
    }

    fn detect_audio_outputs(&self) -> Result<Vec<AudioOutput>> {
        let mut outputs = Vec::new();
        let device_tree = self.readers.read_device_tree()?;
        let alsa_devices = self.readers.list_alsa_devices()?;

        if self.has_i2s_dac(&device_tree, &alsa_devices) {
            outputs.push(AudioOutput::I2S);
        }

        if self.has_usb_audio(&alsa_devices) {
            outputs.push(AudioOutput::USB);
        }

        if self.has_hdmi_audio(&alsa_devices) {
            outputs.push(AudioOutput::HDMI);
        }

        if self.has_headphone_jack(&alsa_devices) {
            outputs.push(AudioOutput::Headphone);
        }

        if outputs.is_empty() {
            outputs.push(AudioOutput::Headphone);
        }

        Ok(outputs)
    }

    fn has_i2s_dac(&self, device_tree: &Option<String>, alsa_devices: &str) -> bool {
        if let Some(dt) = device_tree {
            if dt.contains("HiFiBerry") {
                return true;
            }
        }

        let alsa_lower = alsa_devices.to_lowercase();
        alsa_lower.contains("hifiberry") || alsa_lower.contains("i2s")
    }

    fn has_usb_audio(&self, alsa_devices: &str) -> bool {
        alsa_devices.to_lowercase().contains("usb audio")
    }

    fn has_hdmi_audio(&self, alsa_devices: &str) -> bool {
        alsa_devices.to_lowercase().contains("hdmi")
    }

    fn has_headphone_jack(&self, alsa_devices: &str) -> bool {
        alsa_devices.contains("Headphones") || alsa_devices.contains("bcm2835")
    }

    fn select_preferred_output(&self, outputs: &[AudioOutput]) -> AudioOutput {
        const PRIORITY: &[AudioOutput] = &[
            AudioOutput::I2S,
            AudioOutput::USB,
            AudioOutput::HDMI,
            AudioOutput::Headphone,
        ];

        for preferred in PRIORITY {
            if outputs.contains(preferred) {
                return *preferred;
            }
        }

        outputs.first().copied().unwrap_or(AudioOutput::Headphone)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    struct MockSystemReaders {
        cpu_info: String,
        mem_info: String,
        device_tree: Option<String>,
        alsa_devices: String,
    }

    impl SystemReaders for MockSystemReaders {
        fn read_cpu_info(&self) -> Result<String> {
            Ok(self.cpu_info.clone())
        }

        fn read_mem_info(&self) -> Result<String> {
            Ok(self.mem_info.clone())
        }

        fn read_device_tree(&self) -> Result<Option<String>> {
            Ok(self.device_tree.clone())
        }

        fn list_alsa_devices(&self) -> Result<String> {
            Ok(self.alsa_devices.clone())
        }
    }

    fn pi_zero_2_w_mock() -> MockSystemReaders {
        MockSystemReaders {
            cpu_info: "processor	: 0\nprocessor	: 1\nprocessor	: 2\nprocessor	: 3\nHardware	: BCM2835\nModel		: Raspberry Pi Zero 2 W Rev 1.0".to_string(),
            mem_info: "MemTotal:        465920 kB\nMemFree:         123456 kB".to_string(),
            device_tree: None,
            alsa_devices: "card 0: Headphones [bcm2835 Headphones], device 0: bcm2835 Headphones".to_string(),
        }
    }

    fn pi_4_with_i2s_dac_mock() -> MockSystemReaders {
        MockSystemReaders {
            cpu_info: "processor	: 0\nprocessor	: 1\nprocessor	: 2\nprocessor	: 3\nHardware	: BCM2711\nModel		: Raspberry Pi 4 Model B Rev 1.1".to_string(),
            mem_info: "MemTotal:        3964928 kB".to_string(),
            device_tree: Some("simple-audio-card,name = \"HiFiBerry DAC+\"".to_string()),
            alsa_devices: "card 0: sndrpihifiberry [snd_rpi_hifiberry_dac]\ncard 1: Headphones [bcm2835 Headphones]".to_string(),
        }
    }

    fn pi_5_with_usb_audio_mock() -> MockSystemReaders {
        MockSystemReaders {
            cpu_info: "processor	: 0\nprocessor	: 1\nprocessor	: 2\nprocessor	: 3\nHardware	: BCM2712\nModel		: Raspberry Pi 5 Model B Rev 1.0".to_string(),
            mem_info: "MemTotal:        8125440 kB".to_string(),
            device_tree: None,
            alsa_devices: "card 0: Device [USB Audio Device]\ncard 1: Headphones [bcm2835 Headphones]".to_string(),
        }
    }

    #[test]
    fn detects_cpu_cores_correctly() {
        let detector = HardwareDetector::new(pi_zero_2_w_mock());
        let caps = detector.detect().unwrap();
        assert_eq!(caps.cpu_cores, 4);
    }

    #[test]
    fn parses_ram_from_meminfo() {
        let detector = HardwareDetector::new(pi_zero_2_w_mock());
        let caps = detector.detect().unwrap();
        assert!(caps.ram_mb > 400 && caps.ram_mb < 500);
    }

    #[test]
    fn identifies_raspberry_pi_zero_2_w() {
        let detector = HardwareDetector::new(pi_zero_2_w_mock());
        let caps = detector.detect().unwrap();
        assert_eq!(caps.board_id, "raspberry-pi-zero-2-w");
    }

    #[test]
    fn identifies_raspberry_pi_4() {
        let detector = HardwareDetector::new(pi_4_with_i2s_dac_mock());
        let caps = detector.detect().unwrap();
        assert_eq!(caps.board_id, "raspberry-pi-4-model-b");
    }

    #[test]
    fn identifies_raspberry_pi_5() {
        let detector = HardwareDetector::new(pi_5_with_usb_audio_mock());
        let caps = detector.detect().unwrap();
        assert_eq!(caps.board_id, "raspberry-pi-5-model-b");
    }

    #[test]
    fn detects_i2s_dac_when_present() {
        let detector = HardwareDetector::new(pi_4_with_i2s_dac_mock());
        let caps = detector.detect().unwrap();
        assert!(caps.audio_outputs.contains(&AudioOutput::I2S));
        assert_eq!(caps.preferred_output, AudioOutput::I2S);
    }

    #[test]
    fn detects_usb_audio_device() {
        let detector = HardwareDetector::new(pi_5_with_usb_audio_mock());
        let caps = detector.detect().unwrap();
        assert!(caps.audio_outputs.contains(&AudioOutput::USB));
        assert_eq!(caps.preferred_output, AudioOutput::USB);
    }

    #[test]
    fn falls_back_to_headphone_jack() {
        let detector = HardwareDetector::new(pi_zero_2_w_mock());
        let caps = detector.detect().unwrap();
        assert!(caps.audio_outputs.contains(&AudioOutput::Headphone));
        assert_eq!(caps.preferred_output, AudioOutput::Headphone);
    }
}
