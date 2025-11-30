use std::collections::HashMap;
use std::net::SocketAddr;
use std::path::Path;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use crate::calibration::{CalibrationApplier, ConfigWriter, ShairportController};
use crate::airplay::{render_config_file, ShairportConfig};
use airsync_shared_protocol::{CalibrationSubmission, ChirpConfig};
use anyhow::{anyhow, Context, Result};
use axum::extract::State;
use axum::http::StatusCode;
use axum::routing::{get, post};
use axum::{Json, Router};
use rand::Rng;
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
    pub pairing_id: String,
    pub code: String,
    pub receiver_id: String,
    pub ttl_seconds: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PairingConfirmResponse {
    pub receiver_id: String,
    pub capabilities: Vec<String>,
}

#[derive(Debug, Clone, Deserialize)]
#[allow(dead_code)]
struct PairingStartRequest {
    device_name: String,
    app_version: String,
    platform: String,
}

#[derive(Debug, Clone, Deserialize)]
struct PairingConfirmRequest {
    pairing_id: String,
    code: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct CalibrationRequestPayload {
    pub timestamp: u64,
    pub chirp_config: ChirpConfig,
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

struct PairingEntry {
    code: String,
    expires_at: Instant,
}

#[derive(Clone)]
pub struct PairingStore {
    inner: Arc<Mutex<HashMap<String, PairingEntry>>>,
    default_ttl: Duration,
}

impl PairingStore {
    pub fn new(default_ttl: Duration) -> Self {
        Self {
            inner: Arc::new(Mutex::new(HashMap::new())),
            default_ttl,
        }
    }

    pub fn start(&self) -> PairingStartResponse {
        let pairing_id = Uuid::new_v4().to_string();
        let code = Self::generate_code();
        let expires_at = Instant::now() + self.default_ttl;
        self.inner.lock().unwrap().insert(
            pairing_id.clone(),
            PairingEntry { code: code.clone(), expires_at },
        );
        PairingStartResponse {
            pairing_id,
            code,
            receiver_id: String::new(),
            ttl_seconds: self.default_ttl.as_secs(),
        }
    }

    pub fn confirm(&self, pairing_id: &str, code: &str) -> Result<()> {
        let mut inner = self.inner.lock().unwrap();
        let entry = inner.get(pairing_id).ok_or_else(|| anyhow!("not found"))?;
        if Instant::now() > entry.expires_at {
            inner.remove(pairing_id);
            return Err(anyhow!("expired"));
        }
        if entry.code != code {
            return Err(anyhow!("code mismatch"));
        }
        inner.remove(pairing_id);
        Ok(())
    }

    fn generate_code() -> String {
        let mut rng = rand::thread_rng();
        format!("{:06}", rng.gen_range(0..1_000_000))
    }
}

#[derive(Clone)]
pub struct ReceiverState {
    info: ReceiverInfo,
    pairings: PairingStore,
    calibration: Arc<dyn CalibrationSink + Send + Sync>,
    settings: Arc<dyn SettingsManager + Send + Sync>,
}

impl ReceiverState {
    pub fn new(
        info: ReceiverInfo,
        pairings: PairingStore,
        calibration: Arc<dyn CalibrationSink + Send + Sync>,
        settings: Arc<dyn SettingsManager + Send + Sync>,
    ) -> Self {
        Self { info, pairings, calibration, settings }
    }
}

pub trait CalibrationSink {
    fn apply(&self, submission: &CalibrationSubmission) -> Result<CalibrationApplyResponse>;
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
        .route("/api/pairing/confirm", post(pairing_confirm))
        .route("/api/calibration/request", post(calibration_request))
        .route("/api/calibration/result", post(calibration_result))
        .route("/api/settings", get(get_settings).post(update_settings))
        .route("/api/receiver/info", get(receiver_info))
        .with_state(state)
}

async fn pairing_start(State(state): State<ReceiverState>, Json(_): Json<PairingStartRequest>) -> Result<Json<PairingStartResponse>, StatusCode> {
    let mut response = state.pairings.start();
    response.receiver_id = state.info.receiver_id.clone();
    Ok(Json(response))
}

async fn pairing_confirm(
    State(state): State<ReceiverState>,
    Json(req): Json<PairingConfirmRequest>,
) -> Result<Json<PairingConfirmResponse>, StatusCode> {
    state.pairings.confirm(&req.pairing_id, &req.code).map_err(|_| StatusCode::BAD_REQUEST)?;
    Ok(Json(PairingConfirmResponse {
        receiver_id: state.info.receiver_id.clone(),
        capabilities: state.info.capabilities.clone(),
    }))
}

async fn calibration_request(Json(_): Json<CalibrationRequestPayload>) -> StatusCode {
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

#[cfg(test)]
mod tests {
    use super::*;
    use axum::body::Body;
    use axum::body::to_bytes;
    use axum::http::Request;
    use serde_json::json;
    use std::time::Duration;
    use tower::ServiceExt;

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
            PairingStore::new(Duration::from_secs(60)),
            Arc::new(MockCalibrationSink::new()),
            Arc::new(MockSettingsManager::new()),
        )
    }

    #[tokio::test]
    async fn pairing_start_and_confirm() {
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
        assert_eq!(start.ttl_seconds, 60);
        assert_eq!(start.code.len(), 6);

        let confirm_body = json!({
            "pairing_id": start.pairing_id,
            "code": start.code
        });
        let response = app
            .clone()
            .oneshot(
                Request::post("/api/pairing/confirm")
                    .header("content-type", "application/json")
                    .body(Body::from(confirm_body.to_string()))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::OK);
        let body = to_bytes(response.into_body(), usize::MAX).await.unwrap();
        let confirm: PairingConfirmResponse = serde_json::from_slice(&body).unwrap();
        assert_eq!(confirm.receiver_id, "rx-1");
        assert_eq!(confirm.capabilities, vec!["calibration"]);
    }

    #[test]
    fn pairing_store_expires() {
        let store = PairingStore::new(Duration::from_millis(1));
        let start = store.start();
        std::thread::sleep(Duration::from_millis(2));
        let result = store.confirm(&start.pairing_id, &start.code);
        assert!(result.is_err());
    }

    #[tokio::test]
    async fn calibration_result_calls_sink() {
        let sink = Arc::new(MockCalibrationSink::new());
        let settings = Arc::new(MockSettingsManager::new());
        let state = ReceiverState::new(
            ReceiverInfo {
                receiver_id: "rx-1".into(),
                name: "Test".into(),
                capabilities: vec!["calibration".into()],
            },
            PairingStore::new(Duration::from_secs(60)),
            sink.clone(),
            settings,
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
            PairingStore::new(Duration::from_secs(60)),
            Arc::new(MockCalibrationSink::new()),
            settings.clone(),
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
