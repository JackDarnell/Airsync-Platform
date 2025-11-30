use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ChirpConfig {
    pub start_freq: u32,
    pub end_freq: u32,
    pub duration: u32,
    pub repetitions: u32,
    pub interval_ms: u32,
}

impl Default for ChirpConfig {
    fn default() -> Self {
        Self {
            start_freq: 1000,
            end_freq: 10000,
            duration: 100,
            repetitions: 6,
            interval_ms: 400,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CalibrationSubmission {
    pub timestamp: u64,
    pub latency_ms: f32,
    pub confidence: f32,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum CalibrationMessage {
    CalibrationRequest {
        timestamp: u64,
    },
    CalibrationReady {
        timestamp: u64,
        countdown: u32,
        chirp_config: ChirpConfig,
    },
    CalibrationData {
        timestamp: u64,
        recording_start_time: u64,
        chirp_detection_times: Vec<u64>,
        confidence: f32,
    },
    CalibrationResult {
        timestamp: u64,
        measured_latency_ms: f32,
        applied_offset_ms: f32,
        confidence: f32,
    },
}
