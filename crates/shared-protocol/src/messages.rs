use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum WebSocketMessage {
    PairingRequest {
        timestamp: u64,
        device_name: String,
        code: String,
    },
    PairingResponse {
        timestamp: u64,
        success: bool,
        device_id: Option<String>,
        error: Option<String>,
    },
    StatusUpdate {
        timestamp: u64,
        status: PlaybackStatus,
        metadata: Option<Metadata>,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum PlaybackStatus {
    Idle,
    Playing,
    Calibrating,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Metadata {
    pub artist: Option<String>,
    pub title: Option<String>,
    pub album: Option<String>,
}
