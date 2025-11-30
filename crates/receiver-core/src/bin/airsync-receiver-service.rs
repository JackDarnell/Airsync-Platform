use std::net::SocketAddr;

use airsync_receiver_core::airplay::generate_config;
use airsync_receiver_core::calibration::{CalibrationApplier, FileConfigWriter, SystemdShairportController};
use airsync_receiver_core::http::{
    load_or_create_receiver_id, render_avahi_service, router, serve, ReceiverInfo, ReceiverState,
    ShairportCalibrationSink, ShairportSettingsManager, SystemPlaybackSink,
};
use airsync_shared_protocol::AudioOutput;
use std::path::PathBuf;
use std::sync::Arc;
use tokio::signal;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let receiver_id_path = PathBuf::from("/var/lib/airsync/receiver.json");
    let receiver_id = load_or_create_receiver_id(&receiver_id_path)?;
    let name = hostname();

    let capabilities = vec!["calibration".to_string()];
    let info = ReceiverInfo {
        receiver_id: receiver_id.clone(),
        name: name.clone(),
        capabilities: capabilities.clone(),
    };

    let config = Arc::new(std::sync::Mutex::new(generate_config(Some(&name), AudioOutput::Headphone)));

    let writer = FileConfigWriter::new("/etc/shairport-sync.conf");
    let controller = SystemdShairportController;
    let applier = CalibrationApplier::new(writer, controller);
    let sink = Arc::new(ShairportCalibrationSink::new(applier, config.clone()));
    let settings = Arc::new(ShairportSettingsManager::new(
        FileConfigWriter::new("/etc/shairport-sync.conf"),
        SystemdShairportController,
        config.clone(),
    ));

    let playback = Arc::new(SystemPlaybackSink::new(48_000, config.clone(), 1.0));
    let state = ReceiverState::new(info, sink, settings, playback);
    let app = router(state);

    let addr: SocketAddr = "0.0.0.0:5000".parse()?;
    println!("AirSync receiver HTTP service listening on {}", addr);
    println!(
        "Avahi service example:\n{}",
        render_avahi_service(&name, &receiver_id, 5000, &["calibration"])
    );

    tokio::select! {
        res = serve(app, addr) => res?,
        _ = signal::ctrl_c() => {
            println!("Shutdown requested");
        }
    }

    Ok(())
}

fn hostname() -> String {
    hostname::get()
        .ok()
        .and_then(|h| h.into_string().ok())
        .unwrap_or_else(|| "AirSync".to_string())
}
