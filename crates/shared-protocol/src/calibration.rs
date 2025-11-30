use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ChirpConfig {
    pub start_freq: u32,
    pub end_freq: u32,
    pub duration: u32,
    pub repetitions: u32,
    pub interval_ms: u32,
    #[serde(default)]
    pub amplitude: Option<f32>,
}

impl Default for ChirpConfig {
    fn default() -> Self {
        Self {
            start_freq: 1000,
            end_freq: 10000,
            duration: 100,
            repetitions: 6,
            interval_ms: 400,
            amplitude: None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn marker_spec_serializes() {
        let spec = CalibrationSignalSpec {
            sample_rate: 48_000,
            length_samples: 240_000,
            markers: vec![
                MarkerSpec {
                    id: "a".into(),
                    kind: MarkerKind::Click,
                    start_sample: 0,
                    duration_samples: 480,
                },
                MarkerSpec {
                    id: "chirp1".into(),
                    kind: MarkerKind::Chirp {
                        start_freq: 1_000,
                        end_freq: 8_000,
                        duration_ms: 100,
                    },
                    start_sample: 10_000,
                    duration_samples: 4_800,
                },
            ],
        };

        let json = serde_json::to_string(&spec).unwrap();
        assert!(json.contains("\"sample_rate\":48000"));
        assert!(json.contains("\"kind\":{\"click\":[]}") || json.contains("\"kind\":\"click\""));
        let round_trip: CalibrationSignalSpec = serde_json::from_str(&json).unwrap();
        assert_eq!(round_trip.sample_rate, 48_000);
        assert_eq!(round_trip.markers.len(), 2);
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CalibrationSubmission {
    pub timestamp: u64,
    pub latency_ms: f32,
    pub confidence: f32,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum MarkerKind {
    Click,
    Chirp { start_freq: u32, end_freq: u32, duration_ms: u32 },
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct MarkerSpec {
    pub id: String,
    pub kind: MarkerKind,
    pub start_sample: u32,
    pub duration_samples: u32,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CalibrationSignalSpec {
    pub sample_rate: u32,
    pub length_samples: u32,
    pub markers: Vec<MarkerSpec>,
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
