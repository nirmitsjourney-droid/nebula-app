//! # Input Server Router & Handlers
//!
//! This module sets up the Axum router and request handlers for the Input Server (Port `3001` by default).
//! It receives user text inputs, HTML inputs, Markdown inputs, files, and live media WebSocket streams
//! and forwards them to the AI agent.

use axum::{
    Router,
    extract::{State, WebSocketUpgrade, Multipart, Path},
    response::IntoResponse,
    routing::{get, post, delete},
    Json,
};
use serde::Deserialize;
use std::sync::Arc;
use tracing::{info, error};

use crate::agent;
use crate::config;
use crate::media;
use crate::state::{AgentMessage, AppState, ContentType};

/// Input structure for text-based messages.
#[derive(Debug, Deserialize)]
pub struct TextInput {
    /// Optional target session ID. A new session is generated if omitted or not found.
    pub session_id: Option<String>,
    /// The text message payload.
    pub content: String,
    /// Optional arbitrary JSON metadata.
    #[serde(default)]
    pub metadata: Option<serde_json::Value>,
}

/// Input structure for HTML snippets.
#[derive(Debug, Deserialize)]
pub struct HtmlInput {
    /// Optional target session ID. A new session is generated if omitted or not found.
    pub session_id: Option<String>,
    /// Raw HTML content.
    pub content: String,
}

/// Input structure for Markdown content.
#[derive(Debug, Deserialize)]
pub struct MarkdownInput {
    /// Optional target session ID. A new session is generated if omitted or not found.
    pub session_id: Option<String>,
    /// Markdown formatted content string.
    pub content: String,
}

/// Build and return the Router for the Input Server.
pub fn router(state: Arc<AppState>) -> Router {
    Router::new()
        .route("/input/text", post(handle_text_input))
        .route("/input/html", post(handle_html_input))
        .route("/input/markdown", post(handle_markdown_input))
        .route("/input/file", post(handle_file_input))
        .route("/input/stream/video", get(handle_video_stream))
        .route("/input/stream/audio", get(handle_audio_stream))
        .route("/health", get(health_check))
        .route("/addon/toggle", post(toggle_addon))
        .route("/addon/status", get(addon_status))
        .route("/sessions", get(list_sessions))
        .route("/sessions/new", post(create_session))
        .route("/sessions/{id}", delete(delete_session))
        .with_state(state)
}

/// Basic health check endpoint.
async fn health_check() -> impl IntoResponse {
    Json(serde_json::json!({
        "status": "ok",
        "service": "nebula-backend",
        "timestamp": chrono::Utc::now().to_rfc3339(),
    }))
}

/// Dynamically toggle the memory and session addon.
async fn toggle_addon(
    State(state): State<Arc<AppState>>,
) -> impl IntoResponse {
    let mut enabled = state.addon_enabled.write().await;
    *enabled = !*enabled;
    let new_state = *enabled;
    info!("Addon toggled: enabled={}", new_state);
    Json(serde_json::json!({
        "addon_enabled": new_state,
    }))
}

/// Retrieve the current status of the addon and configure paths.
async fn addon_status(
    State(state): State<Arc<AppState>>,
) -> impl IntoResponse {
    let enabled = *state.addon_enabled.read().await;
    Json(serde_json::json!({
        "addon_enabled": enabled,
        "memory_file": state.config.addon.memory_file,
        "session_history_dir": state.config.addon.session_history_dir,
        "agent_md_path": state.config.addon.agent_md_path,
    }))
}

/// List all available sessions.
async fn list_sessions(
    State(state): State<Arc<AppState>>,
) -> impl IntoResponse {
    let mgr = state.session_manager.read().await;
    let sessions: Vec<_> = mgr.list_sessions().into_iter().cloned().collect();
    Json(serde_json::json!({ "sessions": sessions }))
}

/// Create a new session and initialize directory paths.
async fn create_session(
    State(state): State<Arc<AppState>>,
) -> impl IntoResponse {
    let mut mgr = state.session_manager.write().await;
    match mgr.create_session() {
        Ok(session) => Json(serde_json::json!({
            "session": session,
        })),
        Err(e) => Json(serde_json::json!({
            "error": format!("Failed to create session: {}", e),
        })),
    }
}

/// Delete a session and its associated conversation history.
async fn delete_session(
    State(state): State<Arc<AppState>>,
    Path(id): Path<String>,
) -> impl IntoResponse {
    // Delete session folder
    {
        let mut mgr = state.session_manager.write().await;
        if let Err(e) = mgr.delete_session(&id) {
            return Json(serde_json::json!({
                "error": format!("Failed to delete session: {}", e),
            }));
        }
    }

    // Delete the wrapper's conversation file for this session
    let conv_path = config::nebula_dir().join("data/conversations").join(format!("{}.txt", id));
    if conv_path.exists() {
        if let Err(e) = std::fs::remove_file(&conv_path) {
            error!("Failed to delete conversation file {}: {}", conv_path.display(), e);
        } else {
            info!("Deleted conversation file: {}", conv_path.display());
        }
    }

    Json(serde_json::json!({
        "status": "deleted",
        "session_id": id,
    }))
}

/// Ensure a session exists by ID, creating a new session if omitted or not found.
async fn ensure_session(
    state: &Arc<AppState>,
    session_id: Option<String>,
) -> Result<String, String> {
    match session_id {
        Some(id) => {
            let mgr = state.session_manager.read().await;
            if mgr.get_session(&id).is_some() {
                Ok(id)
            } else {
                drop(mgr);
                let mut mgr = state.session_manager.write().await;
                match mgr.create_session() {
                    Ok(s) => Ok(s.id),
                    Err(e) => Err(format!("Failed to create session: {}", e)),
                }
            }
        }
        None => {
            let mut mgr = state.session_manager.write().await;
            match mgr.create_session() {
                Ok(s) => Ok(s.id),
                Err(e) => Err(format!("Failed to create session: {}", e)),
            }
        }
    }
}

/// Handle incoming plain text input, logging it in the session and forwarding it to the agent.
async fn handle_text_input(
    State(state): State<Arc<AppState>>,
    Json(input): Json<TextInput>,
) -> impl IntoResponse {
    let session_id = match ensure_session(&state, input.session_id).await {
        Ok(id) => id,
        Err(e) => return Json(serde_json::json!({ "error": e })),
    };

    let message = AgentMessage {
        id: uuid::Uuid::new_v4().to_string(),
        session_id: session_id.clone(),
        content_type: ContentType::Text,
        payload: input.content.clone(),
        timestamp: chrono::Utc::now().to_rfc3339(),
        file_path: None,
        metadata: input.metadata,
    };

    // Record in session history
    {
        let mut mgr = state.session_manager.write().await;
        let _ = mgr.record_message(&session_id, "User", &input.content);
    }

    // Forward to agent
    match agent::forward_to_agent(&state, message).await {
        Ok(response) => {
            // Record agent response
            {
                let mut mgr = state.session_manager.write().await;
                let _ = mgr.record_message(&session_id, "Agent", &response);
            }

            // Broadcast response
            let response_msg = AgentMessage {
                id: uuid::Uuid::new_v4().to_string(),
                session_id: session_id.clone(),
                content_type: ContentType::Text,
                payload: response.clone(),
                timestamp: chrono::Utc::now().to_rfc3339(),
                file_path: None,
                metadata: None,
            };
            let _ = state.response_tx.send(response_msg);

            Json(serde_json::json!({
                "session_id": session_id,
                "response": response,
            }))
        }
        Err(e) => {
            error!("Agent error: {}", e);
            Json(serde_json::json!({
                "session_id": session_id,
                "error": format!("Agent error: {}", e),
            }))
        }
    }
}

/// Handle incoming HTML snippet input, logging it and forwarding it to the agent.
async fn handle_html_input(
    State(state): State<Arc<AppState>>,
    Json(input): Json<HtmlInput>,
) -> impl IntoResponse {
    let session_id = match ensure_session(&state, input.session_id).await {
        Ok(id) => id,
        Err(e) => return Json(serde_json::json!({ "error": e })),
    };

    let message = AgentMessage {
        id: uuid::Uuid::new_v4().to_string(),
        session_id: session_id.clone(),
        content_type: ContentType::Html,
        payload: input.content.clone(),
        timestamp: chrono::Utc::now().to_rfc3339(),
        file_path: None,
        metadata: None,
    };

    {
        let mut mgr = state.session_manager.write().await;
        let _ = mgr.record_message(&session_id, "User", &format!("[HTML Input]\n{}", &input.content));
    }

    match agent::forward_to_agent(&state, message).await {
        Ok(response) => {
            let mut mgr = state.session_manager.write().await;
            let _ = mgr.record_message(&session_id, "Agent", &response);
            let response_msg = AgentMessage {
                id: uuid::Uuid::new_v4().to_string(),
                session_id: session_id.clone(),
                content_type: ContentType::Text,
                payload: response.clone(),
                timestamp: chrono::Utc::now().to_rfc3339(),
                file_path: None,
                metadata: None,
            };
            let _ = state.response_tx.send(response_msg);
            Json(serde_json::json!({ "session_id": session_id, "response": response }))
        }
        Err(e) => {
            error!("Agent error: {}", e);
            Json(serde_json::json!({ "session_id": session_id, "error": format!("Agent error: {}", e) }))
        }
    }
}

/// Handle incoming Markdown input, logging it and forwarding it to the agent.
async fn handle_markdown_input(
    State(state): State<Arc<AppState>>,
    Json(input): Json<MarkdownInput>,
) -> impl IntoResponse {
    let session_id = match ensure_session(&state, input.session_id).await {
        Ok(id) => id,
        Err(e) => return Json(serde_json::json!({ "error": e })),
    };

    let message = AgentMessage {
        id: uuid::Uuid::new_v4().to_string(),
        session_id: session_id.clone(),
        content_type: ContentType::Markdown,
        payload: input.content.clone(),
        timestamp: chrono::Utc::now().to_rfc3339(),
        file_path: None,
        metadata: None,
    };

    {
        let mut mgr = state.session_manager.write().await;
        let _ = mgr.record_message(&session_id, "User", &format!("[Markdown Input]\n{}", &input.content));
    }

    match agent::forward_to_agent(&state, message).await {
        Ok(response) => {
            let mut mgr = state.session_manager.write().await;
            let _ = mgr.record_message(&session_id, "Agent", &response);
            let response_msg = AgentMessage {
                id: uuid::Uuid::new_v4().to_string(),
                session_id: session_id.clone(),
                content_type: ContentType::Text,
                payload: response.clone(),
                timestamp: chrono::Utc::now().to_rfc3339(),
                file_path: None,
                metadata: None,
            };
            let _ = state.response_tx.send(response_msg);
            Json(serde_json::json!({ "session_id": session_id, "response": response }))
        }
        Err(e) => {
            error!("Agent error: {}", e);
            Json(serde_json::json!({ "session_id": session_id, "error": format!("Agent error: {}", e) }))
        }
    }
}

/// Handle multipart form file upload, saving file into session's assets, and notifying the agent.
async fn handle_file_input(
    State(state): State<Arc<AppState>>,
    mut multipart: Multipart,
) -> impl IntoResponse {
    let mut session_id: Option<String> = None;
    let mut files_processed = Vec::new();

    while let Ok(Some(field)) = multipart.next_field().await {
        let name = field.name().unwrap_or("").to_string();

        if name == "session_id" {
            if let Ok(text) = field.text().await {
                session_id = Some(text);
            }
            continue;
        }

        let filename = field.file_name().unwrap_or("unnamed").to_string();
        let content_type_str = field.content_type().unwrap_or("application/octet-stream").to_string();

        match field.bytes().await {
            Ok(data) => {
                let sid = match ensure_session(&state, session_id.clone()).await {
                    Ok(id) => id,
                    Err(e) => return Json(serde_json::json!({ "error": e })),
                };
                session_id = Some(sid.clone());

                // Save file to session
                let file_path = {
                    let mgr = state.session_manager.read().await;
                    match mgr.save_asset(&sid, &filename, &data) {
                        Ok(path) => path.to_string_lossy().to_string(),
                        Err(e) => {
                            error!("Failed to save asset: {}", e);
                            continue;
                        }
                    }
                };

                let message = AgentMessage {
                    id: uuid::Uuid::new_v4().to_string(),
                    session_id: sid.clone(),
                    content_type: ContentType::File,
                    payload: format!("File uploaded: {} ({})", filename, content_type_str),
                    timestamp: chrono::Utc::now().to_rfc3339(),
                    file_path: Some(file_path.clone()),
                    metadata: Some(serde_json::json!({
                        "filename": filename,
                        "content_type": content_type_str,
                        "size_bytes": data.len(),
                    })),
                };

                {
                    let mut mgr = state.session_manager.write().await;
                    let _ = mgr.record_message(&sid, "User", &format!("[File: {} ({} bytes)]", filename, data.len()));
                }

                match agent::forward_to_agent(&state, message).await {
                    Ok(response) => {
                        let mut mgr = state.session_manager.write().await;
                        let _ = mgr.record_message(&sid, "Agent", &response);
                        files_processed.push(serde_json::json!({
                            "filename": filename,
                            "size_bytes": data.len(),
                            "response": response,
                        }));
                    }
                    Err(e) => {
                        files_processed.push(serde_json::json!({
                            "filename": filename,
                            "error": format!("{}", e),
                        }));
                    }
                }
            }
            Err(e) => {
                error!("Failed to read multipart field: {}", e);
            }
        }
    }

    Json(serde_json::json!({
        "session_id": session_id,
        "files": files_processed,
    }))
}

/// Upgrade incoming GET request to a WebSocket connection for streaming live video frames.
async fn handle_video_stream(
    State(state): State<Arc<AppState>>,
    ws: WebSocketUpgrade,
) -> impl IntoResponse {
    ws.on_upgrade(move |socket| {
        media::handle_video_stream(socket, state.video_tx.clone())
    })
}

/// Upgrade incoming GET request to a WebSocket connection for streaming live audio frames.
async fn handle_audio_stream(
    State(state): State<Arc<AppState>>,
    ws: WebSocketUpgrade,
) -> impl IntoResponse {
    ws.on_upgrade(move |socket| {
        media::handle_audio_stream(socket, state.audio_tx.clone())
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::{
        body::Body,
        http::{Request, StatusCode},
    };
    use tower::ServiceExt;
    use crate::config::Config;

    async fn test_state() -> Arc<AppState> {
        let temp_dir = std::env::temp_dir().join(format!("nebula_test_{}", uuid::Uuid::new_v4()));
        let config = Config {
            input_port: 3001,
            output_port: 3002,
            addon: crate::config::AddonConfig { enabled: false, memory_file: String::new(), session_history_dir: temp_dir.to_string_lossy().to_string(), agent_md_path: String::new() },
            agent: crate::config::AgentConfig { command: "echo".into(), args: vec![], mode: "stdio".into(), endpoint_url: String::new() },
        };
        Arc::new(AppState::new(config).await.unwrap())
    }

    #[tokio::test]
    async fn test_health_check() {
        let state = test_state().await;
        let app = router(state);

        let response = app
            .oneshot(Request::get("/health").body(Body::empty()).unwrap())
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);

        let body: serde_json::Value = serde_json::from_slice(
            &axum::body::to_bytes(response.into_body(), usize::MAX).await.unwrap()
        ).unwrap();
        assert_eq!(body["status"], "ok");
        assert_eq!(body["service"], "nebula-backend");
    }

    #[tokio::test]
    async fn test_create_session_endpoint() {
        let state = test_state().await;
        let app = router(state);

        let response = app
            .oneshot(Request::post("/sessions/new").body(Body::empty()).unwrap())
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);

        let body: serde_json::Value = serde_json::from_slice(
            &axum::body::to_bytes(response.into_body(), usize::MAX).await.unwrap()
        ).unwrap();
        assert!(body["session"].is_object());
        assert!(body["session"]["id"].is_string());
    }

    #[tokio::test]
    async fn test_list_sessions_endpoint() {
        let state = test_state().await;
        let app = router(state);

        // Create a session first
        let _ = app
            .clone()
            .oneshot(Request::post("/sessions/new").body(Body::empty()).unwrap())
            .await
            .unwrap();

        let response = app
            .oneshot(Request::get("/sessions").body(Body::empty()).unwrap())
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);

        let body: serde_json::Value = serde_json::from_slice(
            &axum::body::to_bytes(response.into_body(), usize::MAX).await.unwrap()
        ).unwrap();
        assert!(body["sessions"].is_array());
    }

    #[tokio::test]
    async fn test_addon_toggle() {
        let state = test_state().await;
        assert!(!*state.addon_enabled.read().await);

        let app = router(state.clone());
        let response = app
            .oneshot(Request::post("/addon/toggle").body(Body::empty()).unwrap())
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);

        let body: serde_json::Value = serde_json::from_slice(
            &axum::body::to_bytes(response.into_body(), usize::MAX).await.unwrap()
        ).unwrap();
        assert!(body["addon_enabled"].as_bool().unwrap());
    }

    #[tokio::test]
    async fn test_addon_status() {
        let state = test_state().await;
        let app = router(state);

        let response = app
            .oneshot(Request::get("/addon/status").body(Body::empty()).unwrap())
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);

        let body: serde_json::Value = serde_json::from_slice(
            &axum::body::to_bytes(response.into_body(), usize::MAX).await.unwrap()
        ).unwrap();
        assert!(body["addon_enabled"].is_boolean());
        assert!(body["memory_file"].is_string());
    }
}
