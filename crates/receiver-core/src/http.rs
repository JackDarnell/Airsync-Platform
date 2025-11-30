use std::net::SocketAddr;
use std::path::Path;
use std::process::Command;
use std::sync::{Arc, Mutex};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use crate::calibration::{CalibrationApplier, ConfigWriter, ShairportController};
use crate::airplay::{render_config_file, ShairportConfig};
use airsync_shared_protocol::{CalibrationSubmission, ChirpConfig};
use crate::generate_chirp_samples;
use anyhow::{anyhow, Context, Result};
use axum::extract::State;
use axum::http::StatusCode;
use axum::routing::{get, post};
use axum::{Json, Router};
use serde::{Deserialize, Serialize};
use tokio::net::TcpListener;
use uuid::Uuid;

#[derive(Clone, Serialize, Deserialize)]
pub struct ReceiverInfo {
    pub receiver_id: String,
    pub name: String,
    pub capabilities: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PairingStartResponse {
    pub receiver_id: String,
    pub capabilities: Vec<String>,
    pub output_device: String,
}

#[derive(Debug, Clone, Deserialize)]
#[allow(dead_code)]
struct PairingStartRequest {
    device_name: String,
    app_version: String,
    platform: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct CalibrationRequestPayload {
    pub timestamp: u64,
    pub chirp_config: ChirpConfig,
    #[serde(default)]
    pub delay_ms: Option<u64>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct CalibrationReadyPayload {
    pub timestamp: Option<u64>,
    #[serde(default)]
    pub target_start_ms: Option<u64>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct CalibrationResultPayload {
    pub timestamp: u64,
    pub latency_ms: f32,
    pub confidence: f32,
}

#[derive(Debug, Clone, Serialize)]
pub struct CalibrationApplyResponse {
    pub measured_latency_ms: f32,
    pub applied_offset_ms: f32,
    pub was_clamped: bool,
}

#[derive(Clone)]
pub struct ReceiverState {
    info: ReceiverInfo,
    calibration: Arc<dyn CalibrationSink + Send + Sync>,
    settings: Arc<dyn SettingsManager + Send + Sync>,
    playback: Arc<dyn PlaybackSink + Send + Sync>,
    pending_playback: Arc<Mutex<Option<PendingPlayback>>>,
}

#[derive(Clone)]
struct PendingPlayback {
    chirp: ChirpConfig,
    delay_ms: u64,
    requested_at: u64,
}

impl ReceiverState {
    pub fn new(
        info: ReceiverInfo,
        calibration: Arc<dyn CalibrationSink + Send + Sync>,
        settings: Arc<dyn SettingsManager + Send + Sync>,
        playback: Arc<dyn PlaybackSink + Send + Sync>,
    ) -> Self {
        Self { info, calibration, settings, playback, pending_playback: Arc::new(Mutex::new(None)) }
    }
}

pub trait CalibrationSink {
    fn apply(&self, submission: &CalibrationSubmission) -> Result<CalibrationApplyResponse>;
}

pub trait PlaybackSink {
    fn play(&self, chirp: &ChirpConfig) -> Result<()>;
}

pub trait SettingsManager {
    fn current(&self) -> ShairportConfig;
    fn update(&self, update: SettingsUpdatePayload) -> Result<ShairportConfig>;
}

pub struct ShairportCalibrationSink<W: ConfigWriter + Send + Sync + 'static, C: ShairportController + Send + Sync + 'static> {
    applier: CalibrationApplier<W, C>,
    config: Arc<Mutex<ShairportConfig>>,
}

impl<W: ConfigWriter + Send + Sync + 'static, C: ShairportController + Send + Sync + 'static>
    ShairportCalibrationSink<W, C>
{
    pub fn new(applier: CalibrationApplier<W, C>, config: Arc<Mutex<ShairportConfig>>) -> Self {
        Self { applier, config }
    }
}

impl<W: ConfigWriter + Send + Sync + 'static, C: ShairportController + Send + Sync + 'static>
    CalibrationSink for ShairportCalibrationSink<W, C>
{
    fn apply(&self, submission: &CalibrationSubmission) -> Result<CalibrationApplyResponse> {
        let config = self.config.lock().unwrap().clone();
        let outcome = self.applier.apply_submission(config, submission)?;
        Ok(CalibrationApplyResponse {
            measured_latency_ms: submission.latency_ms,
            applied_offset_ms: outcome.applied_offset_ms,
            was_clamped: outcome.was_clamped,
        })
    }
}

pub fn router(state: ReceiverState) -> Router {
    Router::new()
        .route("/api/pairing/start", post(pairing_start))
        .route("/api/calibration/request", post(calibration_request))
        .route("/api/calibration/ready", post(calibration_ready))
        .route("/api/calibration/result", post(calibration_result))
        .route("/api/settings", get(get_settings).post(update_settings))
        .route("/api/receiver/info", get(receiver_info))
        .route("/api/time", get(time_sync))
        .with_state(state)
}

async fn pairing_start(State(state): State<ReceiverState>, Json(_): Json<PairingStartRequest>) -> Result<Json<PairingStartResponse>, StatusCode> {
    let cfg = state.settings.current();
    Ok(Json(PairingStartResponse {
        receiver_id: state.info.receiver_id.clone(),
        capabilities: state.info.capabilities.clone(),
        output_device: cfg.output_device,
    }))
}

async fn calibration_request(State(state): State<ReceiverState>, Json(req): Json<CalibrationRequestPayload>) -> StatusCode {
    let delay = req.delay_ms.unwrap_or(2_000);
    let mut slot = state.pending_playback.lock().unwrap();
    *slot = Some(PendingPlayback {
        chirp: req.chirp_config.clone(),
        delay_ms: delay,
        requested_at: now_millis(),
    });
    println!(
        "[calibration] received request timestamp={} delay_ms={}",
        req.timestamp, delay
    );
    StatusCode::OK
}

async fn calibration_ready(
    State(state): State<ReceiverState>,
    Json(req): Json<CalibrationReadyPayload>,
) -> StatusCode {
    let received_at = req.timestamp.unwrap_or_else(now_millis);
    let pending = state.pending_playback.lock().unwrap().take();
    let Some(pending) = pending else {
        eprintln!("[calibration] ready called with no pending request");
        return StatusCode::BAD_REQUEST;
    };

    let playback = state.playback.clone();
    tokio::spawn(async move {
        let now = now_millis();
        let target = req.target_start_ms.unwrap_or_else(|| now + pending.delay_ms);
        let wait_ms = target.saturating_sub(now);
        if wait_ms > 0 {
            tokio::time::sleep(Duration::from_millis(wait_ms)).await;
        }
        let start_at = now_millis();
        println!(
            "[calibration] scheduling playback - ready_rx_ts={}ms req_ts={}ms target_ts={}ms start_ts={}ms delay_ms={}",
            received_at, pending.requested_at, target, start_at, pending.delay_ms
        );
        if let Err(err) = playback.play(&pending.chirp) {
            eprintln!("[calibration] playback failed: {err:?}");
        }
    });

    StatusCode::OK
}

async fn calibration_result(
    State(state): State<ReceiverState>,
    Json(req): Json<CalibrationResultPayload>,
) -> Result<Json<CalibrationApplyResponse>, StatusCode> {
    let submission = CalibrationSubmission {
        timestamp: req.timestamp,
        latency_ms: req.latency_ms,
        confidence: req.confidence,
    };
    let applied = state.calibration.apply(&submission).map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    Ok(Json(applied))
}

async fn receiver_info(State(state): State<ReceiverState>) -> Json<ReceiverInfo> {
    Json(state.info.clone())
}

#[derive(Debug, Serialize, Deserialize)]
struct TimeSyncResponse {
    server_time_ms: u64,
}

async fn time_sync() -> Json<TimeSyncResponse> {
    let now = now_millis();
    println!("[time] /api/time called server_time_ms={}", now);
    Json(TimeSyncResponse { server_time_ms: now })
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SettingsResponse {
    pub device_name: String,
    pub output_device: String,
    pub latency_offset_seconds: f32,
}

#[derive(Debug, Clone, Deserialize)]
pub struct SettingsUpdatePayload {
    pub device_name: Option<String>,
    pub output_device: Option<String>,
    pub latency_offset_seconds: Option<f32>,
}

async fn get_settings(State(state): State<ReceiverState>) -> Json<SettingsResponse> {
    let cfg = state.settings.current();
    Json(SettingsResponse {
        device_name: cfg.device_name,
        output_device: cfg.output_device,
        latency_offset_seconds: cfg.latency_offset_seconds,
    })
}

async fn update_settings(
    State(state): State<ReceiverState>,
    Json(req): Json<SettingsUpdatePayload>,
) -> Result<Json<SettingsResponse>, StatusCode> {
    let cfg = state.settings.update(req).map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    Ok(Json(SettingsResponse {
        device_name: cfg.device_name,
        output_device: cfg.output_device,
        latency_offset_seconds: cfg.latency_offset_seconds,
    }))
}

pub struct ShairportSettingsManager<W: ConfigWriter + Send + Sync + 'static, C: ShairportController + Send + Sync + 'static> {
    writer: W,
    controller: C,
    config: Arc<Mutex<ShairportConfig>>,
}

pub struct NoopPlaybackSink;

impl PlaybackSink for NoopPlaybackSink {
    fn play(&self, _chirp: &ChirpConfig) -> Result<()> {
        Ok(())
    }
}

pub struct SystemPlaybackSink {
    sample_rate: u32,
    gain: f32,
    config: Arc<Mutex<ShairportConfig>>,
    pregen_path: Option<std::path::PathBuf>,
}

impl SystemPlaybackSink {
    pub fn new(sample_rate: u32, config: Arc<Mutex<ShairportConfig>>, gain: f32, pregen_path: Option<std::path::PathBuf>) -> Self {
        Self { sample_rate, gain, config, pregen_path }
    }

    fn write_wave(&self, chirp: &ChirpConfig) -> Result<tempfile::NamedTempFile> {
        let file = tempfile::NamedTempFile::new()?;
        let spec = hound::WavSpec {
            channels: 1,
            sample_rate: self.sample_rate,
            bits_per_sample: 16,
            sample_format: hound::SampleFormat::Int,
        };
        let mut writer = hound::WavWriter::create(file.path(), spec)?;
        let samples = generate_chirp_samples(chirp, self.sample_rate, self.gain);
        for s in samples {
            writer.write_sample(s)?;
        }
        writer.finalize()?;
        Ok(file)
    }
}

impl PlaybackSink for SystemPlaybackSink {
    fn play(&self, chirp: &ChirpConfig) -> Result<()> {
        let wav_path = if let Some(path) = &self.pregen_path {
            path.clone()
        } else {
            let file = self.write_wave(chirp)?;
            file.into_temp_path().keep()?
        };
        let mut cmd = Command::new("aplay");
        let dev = { self.config.lock().unwrap().output_device.clone() };
        if !dev.is_empty() {
            cmd.args(["-D", dev.as_str()]);
        }
        cmd.args(["-q", wav_path.to_str().unwrap_or("")]);
        println!(
            "[calibration] invoking aplay device={} file={}",
            if dev.is_empty() { "<default>" } else { dev.as_str() },
            wav_path.to_string_lossy()
        );
        let status = cmd.status();
        match status {
            Ok(s) if s.success() => Ok(()),
            Ok(s) => Err(anyhow!("aplay failed with status {}", s)),
            Err(e) => Err(anyhow!("failed to run aplay: {}", e)),
        }
    }
}

impl<W: ConfigWriter + Send + Sync + 'static, C: ShairportController + Send + Sync + 'static>
    ShairportSettingsManager<W, C>
{
    pub fn new(writer: W, controller: C, config: Arc<Mutex<ShairportConfig>>) -> Self {
        Self { writer, controller, config }
    }
}

impl<W: ConfigWriter + Send + Sync + 'static, C: ShairportController + Send + Sync + 'static>
    SettingsManager for ShairportSettingsManager<W, C>
{
    fn current(&self) -> ShairportConfig {
        self.config.lock().unwrap().clone()
    }

    fn update(&self, update: SettingsUpdatePayload) -> Result<ShairportConfig> {
        let mut cfg = self.config.lock().unwrap();
        if let Some(name) = update.device_name {
            cfg.device_name = name;
        }
        if let Some(output) = update.output_device {
            cfg.output_device = output;
        }
        if let Some(latency) = update.latency_offset_seconds {
            cfg.latency_offset_seconds = latency;
        }
        let rendered = render_config_file(&cfg);
        self.writer.write(&rendered)?;
        self.controller.restart()?;
        Ok(cfg.clone())
    }
}

pub async fn serve(router: Router, addr: SocketAddr) -> Result<()> {
    let listener = TcpListener::bind(addr).await.context("bind")?;
    axum::serve(listener, router).await.context("serve")?;
    Ok(())
}

pub fn load_or_create_receiver_id(path: &Path) -> Result<String> {
    if path.exists() {
        let bytes = std::fs::read(path)?;
        let existing: StoredReceiver = serde_json::from_slice(&bytes)?;
        Ok(existing.receiver_id)
    } else {
        let id = Uuid::new_v4().to_string();
        let stored = StoredReceiver { receiver_id: id.clone() };
        let parent = path.parent().unwrap_or_else(|| Path::new("."));
        std::fs::create_dir_all(parent)?;
        std::fs::write(path, serde_json::to_vec_pretty(&stored)?)?;
        Ok(id)
    }
}

#[derive(Serialize, Deserialize)]
struct StoredReceiver {
    receiver_id: String,
}

pub fn render_avahi_service(name: &str, receiver_id: &str, port: u16, caps: &[&str]) -> String {
    let caps_str = caps.join(",");
    format!(
        r#"<service-group>
  <name replace-wildcards="yes">{name}</name>
  <service>
    <type>_airsync._tcp</type>
    <port>{port}</port>
    <txt-record>name={name}</txt-record>
    <txt-record>ver=1</txt-record>
    <txt-record>api=/api</txt-record>
    <txt-record>caps={caps}</txt-record>
    <txt-record>id={id}</txt-record>
  </service>
</service-group>
"#,
        name = name,
        port = port,
        caps = caps_str,
        id = receiver_id
    )
}

fn now_millis() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_else(|_| Duration::from_secs(0))
        .as_millis() as u64
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::body::Body;
    use axum::body::to_bytes;
    use axum::http::Request;
    use serde_json::json;
    use tower::ServiceExt;
    use crate::generate_chirp_samples;

    #[derive(Clone)]
    struct MockCalibrationSink {
        last: Arc<Mutex<Option<CalibrationSubmission>>>,
    }

    impl MockCalibrationSink {
        fn new() -> Self {
            Self {
                last: Arc::new(Mutex::new(None)),
            }
        }

        fn last(&self) -> Option<CalibrationSubmission> {
            self.last.lock().unwrap().clone()
        }
    }

    impl CalibrationSink for MockCalibrationSink {
        fn apply(&self, submission: &CalibrationSubmission) -> Result<CalibrationApplyResponse> {
            *self.last.lock().unwrap() = Some(submission.clone());
            Ok(CalibrationApplyResponse {
                measured_latency_ms: submission.latency_ms,
                applied_offset_ms: submission.latency_ms,
                was_clamped: false,
            })
        }
    }

    #[derive(Clone)]
    struct MockPlaybackSink {
        last: Arc<Mutex<Option<ChirpConfig>>>,
        calls: Arc<Mutex<u32>>,
        fail: bool,
    }

    impl MockPlaybackSink {
        fn new() -> Self {
            Self {
                last: Arc::new(Mutex::new(None)),
                calls: Arc::new(Mutex::new(0)),
                fail: false,
            }
        }

        fn last(&self) -> Option<ChirpConfig> {
            self.last.lock().unwrap().clone()
        }

    fn call_count(&self) -> u32 {
        *self.calls.lock().unwrap()
    }
}

impl PlaybackSink for MockPlaybackSink {
        fn play(&self, chirp: &ChirpConfig) -> Result<()> {
            *self.calls.lock().unwrap() += 1;
            *self.last.lock().unwrap() = Some(chirp.clone());
            if self.fail {
                return Err(anyhow!("fail"));
            }
            Ok(())
        }
    }

    #[derive(Clone)]
    struct MockSettingsManager {
        cfg: Arc<Mutex<ShairportConfig>>,
        restarts: Arc<Mutex<u32>>,
    }

    impl MockSettingsManager {
        fn new() -> Self {
            Self {
                cfg: Arc::new(Mutex::new(ShairportConfig {
                    device_name: "AirSync".into(),
                    output_device: "hw:0,0".into(),
                    latency_offset_seconds: 0.0,
                })),
                restarts: Arc::new(Mutex::new(0)),
            }
        }

        fn restart_calls(&self) -> u32 {
            *self.restarts.lock().unwrap()
        }
    }

    impl SettingsManager for MockSettingsManager {
        fn current(&self) -> ShairportConfig {
            self.cfg.lock().unwrap().clone()
        }

        fn update(&self, update: SettingsUpdatePayload) -> Result<ShairportConfig> {
            let mut cfg = self.cfg.lock().unwrap();
            if let Some(name) = update.device_name {
                cfg.device_name = name;
            }
            if let Some(out) = update.output_device {
                cfg.output_device = out;
            }
            if let Some(lat) = update.latency_offset_seconds {
                cfg.latency_offset_seconds = lat;
            }
            *self.restarts.lock().unwrap() += 1;
            Ok(cfg.clone())
        }
    }

    fn test_state() -> ReceiverState {
        ReceiverState::new(
            ReceiverInfo {
                receiver_id: "rx-1".into(),
                name: "Test".into(),
                capabilities: vec!["calibration".into()],
            },
            Arc::new(MockCalibrationSink::new()),
            Arc::new(MockSettingsManager::new()),
            Arc::new(MockPlaybackSink::new()),
        )
    }

    #[tokio::test]
    async fn pairing_start_returns_receiver_info() {
        let state = test_state();
        let app = router(state.clone());

        let req_body = json!({
            "device_name": "iPhone",
            "app_version": "1.0",
            "platform": "ios"
        });
        let response = app
            .clone()
            .oneshot(
                Request::post("/api/pairing/start")
                    .header("content-type", "application/json")
                    .body(Body::from(req_body.to_string()))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::OK);
        let body = to_bytes(response.into_body(), usize::MAX).await.unwrap();
        let start: PairingStartResponse = serde_json::from_slice(&body).unwrap();
        assert_eq!(start.receiver_id, "rx-1");
        assert_eq!(start.capabilities, vec!["calibration"]);
        assert_eq!(start.output_device, "hw:0,0");
    }

    #[tokio::test]
    async fn calibration_result_calls_sink() {
        let sink = Arc::new(MockCalibrationSink::new());
        let playback = Arc::new(MockPlaybackSink::new());
        let settings = Arc::new(MockSettingsManager::new());
        let state = ReceiverState::new(
            ReceiverInfo {
                receiver_id: "rx-1".into(),
                name: "Test".into(),
                capabilities: vec!["calibration".into()],
            },
            sink.clone(),
            settings,
            playback,
        );
        let app = router(state);
        let req_body = json!({
            "timestamp": 1,
            "latency_ms": 42.0,
            "confidence": 0.9
        });
        let response = app
            .oneshot(
                Request::post("/api/calibration/result")
                    .header("content-type", "application/json")
                    .body(Body::from(req_body.to_string()))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::OK);
        let recorded = sink.last().unwrap();
        assert_eq!(recorded.latency_ms, 42.0);
        assert_eq!(recorded.confidence, 0.9);
    }

    #[tokio::test]
    async fn settings_update_changes_config_and_tracks_restart() {
        let settings = Arc::new(MockSettingsManager::new());
        let state = ReceiverState::new(
            ReceiverInfo {
                receiver_id: "rx-1".into(),
                name: "Test".into(),
                capabilities: vec!["calibration".into()],
            },
            Arc::new(MockCalibrationSink::new()),
            settings.clone(),
            Arc::new(MockPlaybackSink::new()),
        );
        let app = router(state);

        let update = json!({
            "device_name": "Living Room",
            "output_device": "hw:1,0",
            "latency_offset_seconds": 0.05
        });
        let response = app
            .oneshot(
                Request::post("/api/settings")
                    .header("content-type", "application/json")
                    .body(Body::from(update.to_string()))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::OK);

        let cfg = settings.current();
        assert_eq!(cfg.device_name, "Living Room");
        assert_eq!(cfg.output_device, "hw:1,0");
        assert_eq!(cfg.latency_offset_seconds, 0.05);
        assert_eq!(settings.restart_calls(), 1);
    }

    #[tokio::test]
    async fn calibration_request_triggers_playback() {
        let playback = Arc::new(MockPlaybackSink::new());
        let state = ReceiverState::new(
            ReceiverInfo {
                receiver_id: "rx-1".into(),
                name: "Test".into(),
                capabilities: vec!["calibration".into()],
            },
            Arc::new(MockCalibrationSink::new()),
            Arc::new(MockSettingsManager::new()),
            playback.clone(),
        );
        let app = router(state);
        let req_body = json!({
            "timestamp": 1,
            "chirp_config": {
                "start_freq": 2000,
                "end_freq": 8000,
                "duration": 50,
                "repetitions": 5,
                "interval_ms": 500
            },
            "delay_ms": 1
        });
        let response = app.clone()
            .oneshot(
                Request::post("/api/calibration/request")
                    .header("content-type", "application/json")
                    .body(Body::from(req_body.to_string()))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::OK);
        tokio::time::sleep(Duration::from_millis(10)).await;
        assert_eq!(playback.call_count(), 0);

        let response = app.clone()
            .oneshot(
                Request::post("/api/calibration/ready")
                    .header("content-type", "application/json")
                    .body(Body::from(json!({"timestamp": 5}).to_string()))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::OK);
        tokio::time::sleep(Duration::from_millis(20)).await;
        assert_eq!(playback.call_count(), 1);
        let last = playback.last().unwrap();
        assert_eq!(last.start_freq, 2000);
        assert_eq!(last.end_freq, 8000);
    }

    #[tokio::test]
    async fn calibration_request_failure_logs_and_returns_ok() {
        let playback = Arc::new(MockPlaybackSink { last: Arc::new(Mutex::new(None)), calls: Arc::new(Mutex::new(0)), fail: true });
        let state = ReceiverState::new(
            ReceiverInfo {
                receiver_id: "rx-1".into(),
                name: "Test".into(),
                capabilities: vec!["calibration".into()],
            },
            Arc::new(MockCalibrationSink::new()),
            Arc::new(MockSettingsManager::new()),
            playback.clone(),
        );
        let app = router(state);
        let req_body = json!({
            "timestamp": 1,
            "chirp_config": {
                "start_freq": 2000,
                "end_freq": 8000,
                "duration": 50,
                "repetitions": 5,
                "interval_ms": 500
            },
            "delay_ms": 1
        });
        let response = app.clone()
            .oneshot(
                Request::post("/api/calibration/request")
                    .header("content-type", "application/json")
                    .body(Body::from(req_body.to_string()))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::OK);
        let response = app.clone()
            .oneshot(
                Request::post("/api/calibration/ready")
                    .header("content-type", "application/json")
                    .body(Body::from(json!({"timestamp": 5, "target_start_ms": 25}).to_string()))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::OK);
        tokio::time::sleep(Duration::from_millis(20)).await;
        assert_eq!(playback.call_count(), 1);
    }

    #[tokio::test]
    async fn calibration_ready_without_request_fails() {
        let app = router(test_state());
        let response = app
            .oneshot(
                Request::post("/api/calibration/ready")
                    .header("content-type", "application/json")
                    .body(Body::from(json!({}).to_string()))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::BAD_REQUEST);
    }

    #[tokio::test]
    async fn time_sync_returns_server_time() {
        let app = router(test_state());
        let response = app
            .oneshot(Request::get("/api/time").body(Body::empty()).unwrap())
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::OK);
        let body = to_bytes(response.into_body(), usize::MAX).await.unwrap();
        let payload: super::TimeSyncResponse = serde_json::from_slice(&body).unwrap();
        assert!(payload.server_time_ms > 0);
    }

    #[test]
    fn chirp_samples_have_energy() {
        let cfg = ChirpConfig {
            start_freq: 1000,
            end_freq: 10000,
            duration: 100,
            repetitions: 2,
            interval_ms: 100,
        };
        let samples = generate_chirp_samples(&cfg, 48_000, 1.0);
        assert!(samples.iter().any(|&s| s != 0));
        // Ensure spacing for interval
        let expected_min = (cfg.duration as f32 / 1000.0 * 48000.0) as usize * 2;
        assert!(samples.len() >= expected_min);
    }

    #[test]
    fn load_or_create_receiver_id_persists() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("receiver.json");
        let first = load_or_create_receiver_id(&path).unwrap();
        let second = load_or_create_receiver_id(&path).unwrap();
        assert_eq!(first, second);
    }

    #[test]
    fn avahi_service_contains_fields() {
        let rendered = render_avahi_service("Living Room", "rx-1", 5000, &["calibration"]);
        assert!(rendered.contains("_airsync._tcp"));
        assert!(rendered.contains("rx-1"));
        assert!(rendered.contains("caps=calibration"));
        assert!(rendered.contains("<port>5000</port>"));
    }
}
