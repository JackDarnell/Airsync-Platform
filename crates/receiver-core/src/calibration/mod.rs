use crate::airplay::{render_config_file, ShairportConfig};
use airsync_shared_protocol::CalibrationSubmission;
use anyhow::Result;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

pub trait ConfigWriter {
    fn write(&self, contents: &str) -> Result<()>;
}

pub trait ShairportController {
    fn restart(&self) -> Result<()>;
}

pub struct FileConfigWriter {
    path: PathBuf,
}

impl FileConfigWriter {
    pub fn new(path: impl Into<PathBuf>) -> Self {
        Self { path: path.into() }
    }

    pub fn path(&self) -> &Path {
        &self.path
    }
}

impl ConfigWriter for FileConfigWriter {
    fn write(&self, contents: &str) -> Result<()> {
        fs::write(&self.path, contents)?;
        Ok(())
    }
}

pub struct SystemdShairportController;

impl ShairportController for SystemdShairportController {
    fn restart(&self) -> Result<()> {
        if std::env::var("AIRSYNC_SKIP_SHAIRPORT_RESTART")
            .map(|v| v == "1" || v.eq_ignore_ascii_case("true"))
            .unwrap_or(false)
        {
            println!("[calibration] shairport-sync restart skipped (AIRSYNC_SKIP_SHAIRPORT_RESTART set)");
            return Ok(());
        }

        let try_sudo = Command::new("sudo")
            .args(["-n", "/usr/bin/systemctl", "restart", "shairport-sync"])
            .status();

        match try_sudo {
            Ok(status) if status.success() => Ok(()),
            _ => {
                let direct = Command::new("/usr/bin/systemctl")
                    .args(["restart", "shairport-sync"])
                    .status();
                match direct {
                    Ok(status) if status.success() => Ok(()),
                    _ => {
                        // Do not block calibration if restart fails; log and continue
                        eprintln!("shairport-sync restart failed (ignored)");
                        Ok(())
                    }
                }
            }
        }
    }
}

pub struct CalibrationApplier<W: ConfigWriter, C: ShairportController> {
    writer: W,
    controller: C,
}

impl<W: ConfigWriter, C: ShairportController> CalibrationApplier<W, C> {
    pub fn new(writer: W, controller: C) -> Self {
        Self { writer, controller }
    }

    pub fn apply_latency(
        &self,
        mut config: ShairportConfig,
        measured_latency_ms: f32,
    ) -> Result<CalibrationOutcome> {
        #[cfg(not(test))]
        let override_latency = std::env::var("AIRSYNC_FORCE_LATENCY_MS")
            .ok()
            .and_then(|v| v.parse::<f32>().ok());
        #[cfg(test)]
        let override_latency: Option<f32> = None;
        let effective_latency_ms = override_latency.unwrap_or(measured_latency_ms);
        if let Some(val) = override_latency {
            println!("[calibration] applying forced latency from env AIRSYNC_FORCE_LATENCY_MS={}ms", val);
        }

        let clamped_latency_ms = effective_latency_ms.clamp(-250.0, 250.0);
        let offset_seconds = -clamped_latency_ms / 1000.0;
        config.latency_offset_seconds = offset_seconds;

        let rendered = render_config_file(&config);
        self.writer.write(&rendered)?;
        self.controller.restart()?;

        Ok(CalibrationOutcome {
            measured_latency_ms: effective_latency_ms,
            applied_offset_ms: offset_seconds * 1000.0,
            was_clamped: clamped_latency_ms != effective_latency_ms,
        })
    }

    pub fn apply_submission(
        &self,
        config: ShairportConfig,
        submission: &CalibrationSubmission,
    ) -> Result<CalibrationOutcome> {
        self.apply_latency(config, submission.latency_ms)
    }
}

pub struct CalibrationOutcome {
    pub measured_latency_ms: f32,
    pub applied_offset_ms: f32,
    pub was_clamped: bool,
}

pub mod signal;

#[cfg(test)]
mod tests {
    use super::*;
    use airsync_shared_protocol::AudioOutput;
    use crate::airplay::generate_config;
    use std::sync::{Arc, Mutex};

    #[derive(Clone)]
    struct MockWriter {
        contents: Arc<Mutex<Option<String>>>,
    }

    impl MockWriter {
        fn new() -> Self {
            Self {
                contents: Arc::new(Mutex::new(None)),
            }
        }

        fn last_contents(&self) -> Option<String> {
            self.contents.lock().unwrap().clone()
        }
    }

    impl ConfigWriter for MockWriter {
        fn write(&self, contents: &str) -> Result<()> {
            *self.contents.lock().unwrap() = Some(contents.to_string());
            Ok(())
        }
    }

    #[derive(Clone)]
    struct MockController {
        restart_calls: Arc<Mutex<u32>>,
    }

    impl MockController {
        fn new() -> Self {
            Self {
                restart_calls: Arc::new(Mutex::new(0)),
            }
        }

        fn calls(&self) -> u32 {
            *self.restart_calls.lock().unwrap()
        }
    }

    impl ShairportController for MockController {
        fn restart(&self) -> Result<()> {
            *self.restart_calls.lock().unwrap() += 1;
            Ok(())
        }
    }

    #[test]
    fn writes_latency_offset_and_restarts() {
        let writer = MockWriter::new();
        let restarter = MockController::new();
        let applier = CalibrationApplier::new(writer.clone(), restarter.clone());

        let config = generate_config(Some("Living Room"), AudioOutput::I2S);
        let outcome = applier.apply_latency(config, 55.0).unwrap();

        assert_eq!(outcome.measured_latency_ms, 55.0);
        assert_eq!(format!("{:.3}", outcome.applied_offset_ms), "-55.000");
        assert!(!outcome.was_clamped);

        let rendered = writer.last_contents().expect("config should be written");
        assert!(rendered.contains("audio_backend_latency_offset_in_seconds = -0.055"));
        assert_eq!(restarter.calls(), 1);
    }

    #[test]
    fn clamps_excessive_latency_to_supported_range() {
        let writer = MockWriter::new();
        let restarter = MockController::new();
        let applier = CalibrationApplier::new(writer.clone(), restarter.clone());

        let config = generate_config(None, AudioOutput::USB);
        let outcome = applier.apply_latency(config, 800.0).unwrap();

        assert!(outcome.was_clamped);
        assert_eq!(format!("{:.3}", outcome.applied_offset_ms), "-250.000");

        let rendered = writer.last_contents().unwrap();
        assert!(rendered.contains("audio_backend_latency_offset_in_seconds = -0.250"));
    }

    #[test]
    fn delays_playback_when_audio_is_early() {
        let writer = MockWriter::new();
        let restarter = MockController::new();
        let applier = CalibrationApplier::new(writer.clone(), restarter.clone());

        let config = generate_config(None, AudioOutput::Headphone);
        let outcome = applier.apply_latency(config, -20.0).unwrap();

        assert_eq!(format!("{:.3}", outcome.applied_offset_ms), "20.000");
        assert!(!outcome.was_clamped);

        let rendered = writer.last_contents().unwrap();
        assert!(rendered.contains("audio_backend_latency_offset_in_seconds = 0.020"));
    }

    #[test]
    fn applies_submission_payload() {
        let writer = MockWriter::new();
        let restarter = MockController::new();
        let applier = CalibrationApplier::new(writer.clone(), restarter.clone());

        let config = generate_config(Some("Studio"), AudioOutput::HDMI);
        let submission = CalibrationSubmission {
            timestamp: 1_234,
            latency_ms: 30.0,
            confidence: 0.92,
            detections: vec![],
        };

        let outcome = applier.apply_submission(config, &submission).unwrap();
        assert_eq!(format!("{:.3}", outcome.applied_offset_ms), "-30.000");
        assert_eq!(restarter.calls(), 1);

        let rendered = writer.last_contents().unwrap();
        assert!(rendered.contains("audio_backend_latency_offset_in_seconds = -0.030"));
    }
}
