//! # Output Server Router & Handlers
//!
//! This module sets up the Axum router and request handlers for the Output Server (Port `3002` by default).
//! It handles real-time response WebSocket streams, live video and audio broadcasts, and endpoints for 
//! querying session detail listings, chat logs, and long-term memory contents.

use axum::{
    Router,
    extract::{Path, State, WebSocketUpgrade},
    response::IntoResponse,
    routing::get,
    Json,
};
use futures::StreamExt;
use std::sync::Arc;
use tracing::info;

use crate::media;
use crate::state::AppState;

/// Build and return the Router for the Output Server.
pub fn router(state: Arc<AppState>) -> Router {
    Router::new()
        .route("/output/stream", get(handle_response_stream))
        .route("/output/stream/video", get(handle_video_output))
        .route("/output/stream/audio", get(handle_audio_output))
        .route("/output/session/{id}", get(get_session_detail))
        .route("/output/sessions", get(list_sessions))
        .route("/output/memory", get(get_memory))
        .route("/health", get(health_check))
        .with_state(state)
}

/// Basic health check endpoint for the output service.
async fn health_check() -> impl IntoResponse {
    Json(serde_json::json!({
        "status": "ok",
        "service": "nebula-backend-output",
        "timestamp": chrono::Utc::now().to_rfc3339(),
    }))
}

/// WebSocket endpoint that streams agent responses in real-time.
///
/// Subscribes to the broadcast channel of the application state and sends
/// serialized JSON response messages to connected clients.
async fn handle_response_stream(
    State(state): State<Arc<AppState>>,
    ws: WebSocketUpgrade,
) -> impl IntoResponse {
    ws.on_upgrade(move |socket| async move {
        let (mut sink, mut _stream) = socket.split();
        let mut rx = state.response_tx.subscribe();
        info!("Response stream client connected");

        loop {
            match rx.recv().await {
                Ok(msg) => {
                    let json = serde_json::to_string(&msg).unwrap_or_default();
                    if let Err(e) = futures::SinkExt::send(
                        &mut sink,
                        axum::extract::ws::Message::Text(json.into()),
                    ).await {
                        tracing::error!("Failed to send response: {}", e);
                        break;
                    }
                }
                Err(tokio::sync::broadcast::error::RecvError::Lagged(n)) => {
                    tracing::warn!("Response stream lagged by {} messages", n);
                }
                Err(_) => break,
            }
        }
    })
}

/// Stream live video output to subscribed clients.
async fn handle_video_output(
    State(state): State<Arc<AppState>>,
    ws: WebSocketUpgrade,
) -> impl IntoResponse {
    ws.on_upgrade(move |socket| {
        media::handle_video_output(socket, state.video_tx.clone())
    })
}

/// Stream live audio output to subscribed clients.
async fn handle_audio_output(
    State(state): State<Arc<AppState>>,
    ws: WebSocketUpgrade,
) -> impl IntoResponse {
    ws.on_upgrade(move |socket| {
        media::handle_audio_output(socket, state.audio_tx.clone())
    })
}

/// Get details for a specific session by ID.
///
/// Returns metadata, full markdown chat transcripts, and a list of asset filenames.
async fn get_session_detail(
    State(state): State<Arc<AppState>>,
    Path(id): Path<String>,
) -> impl IntoResponse {
    let mgr = state.session_manager.read().await;
    match mgr.get_session(&id) {
        Some(session) => {
            // Read chat log
            let chat_content = std::fs::read_to_string(
                session.folder_path.join("chat.md")
            ).unwrap_or_else(|_| "No chat log found.".to_string());

            // List assets
            let assets: Vec<String> = std::fs::read_dir(
                session.folder_path.join("assets")
            )
            .map(|entries| {
                entries
                    .filter_map(|e| e.ok())
                    .map(|e| e.file_name().to_string_lossy().to_string())
                    .collect()
            })
            .unwrap_or_default();

            Json(serde_json::json!({
                "session": session,
                "chat_log": chat_content,
                "assets": assets,
            }))
        }
        None => Json(serde_json::json!({
            "error": format!("Session not found: {}", id),
        })),
    }
}

/// List all sessions with their summaries.
async fn list_sessions(
    State(state): State<Arc<AppState>>,
) -> impl IntoResponse {
    let mgr = state.session_manager.read().await;
    let sessions: Vec<_> = mgr.list_sessions().into_iter().cloned().collect();
    Json(serde_json::json!({
        "sessions": sessions,
    }))
}

/// Get the contents of the long-term memory markdown file.
async fn get_memory(
    State(state): State<Arc<AppState>>,
) -> impl IntoResponse {
    match crate::addon::read_memory(&state.config.addon.memory_file).await {
        Ok(content) => Json(serde_json::json!({
            "memory": content,
        })),
        Err(e) => Json(serde_json::json!({
            "error": format!("Failed to read memory: {}", e),
        })),
    }
}
