//! # Nebula Backend Server Entrypoint
//!
//! This module initializes logging, loads configuration, manages shared application state,
//! sets up background tasks for forwarding media streams, and starts the dual-port
//! web servers (input and output) using Axum.

use std::sync::Arc;
use tracing::info;

use nebula_backend::{addon, agent, config, input, output, state};

/// The main application entrypoint.
///
/// Sets up the subscriber for tracing, loads `config.toml`, initializes the shared application state,
/// runs the media stream forwarding tasks, and serves the input and output routers concurrently.
#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "nebula_backend=info,tower_http=info".into()),
        )
        .init();

    let config = config::Config::load()?;
    info!("Loaded configuration: input_port={}, output_port={}, addon_enabled={}",
        config.input_port, config.output_port, config.addon.enabled);

    let app_state = state::AppState::new(config.clone()).await?;
    let shared_state = Arc::new(app_state);

    // Initialize addon if enabled
    if config.addon.enabled {
        addon::initialize(&config.addon, &shared_state).await?;
        info!("Addon initialized: memory_file={}, session_dir={}",
            config.addon.memory_file, config.addon.session_history_dir);
    }

    // Start background stream forwarders to AI agent
    agent::start_video_forwarder(shared_state.clone()).await?;
    agent::start_audio_forwarder(shared_state.clone()).await?;

    let input_app = input::router(shared_state.clone());
    let output_app = output::router(shared_state.clone());

    let input_addr = format!("0.0.0.0:{}", config.input_port);
    let output_addr = format!("0.0.0.0:{}", config.output_port);

    info!("Input server listening on {}", input_addr);
    info!("Output server listening on {}", output_addr);

    let input_listener = tokio::net::TcpListener::bind(&input_addr).await?;
    let output_listener = tokio::net::TcpListener::bind(&output_addr).await?;

    tokio::select! {
        result = axum::serve(input_listener, input_app) => {
            if let Err(e) = result {
                tracing::error!("Input server error: {}", e);
            }
        }
        result = axum::serve(output_listener, output_app) => {
            if let Err(e) = result {
                tracing::error!("Output server error: {}", e);
            }
        }
        _ = tokio::signal::ctrl_c() => {
            info!("Shutdown signal received, exiting...");
        }
    }

    Ok(())
}
