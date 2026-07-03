//! # Application State Module
//!
//! This module defines the shared application state (`AppState`) and message definitions
//! used to pass data, responses, and live streams across different services and handlers.

use crate::config::Config;
use crate::session::SessionManager;
use std::sync::Arc;
use tokio::sync::{broadcast, RwLock};

/// Represents a message flowing through the Nebula system.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct AgentMessage {
    /// Unique identifier of the message.
    pub id: String,
    /// ID of the session the message belongs to.
    pub session_id: String,
    /// The type of content (e.g., text, html, file, etc.).
    pub content_type: ContentType,
    /// The raw content string or description.
    pub payload: String,
    /// Timestamp of when the message was created (ISO 8601 / RFC 3339).
    pub timestamp: String,
    /// The path to the file if `content_type` is `ContentType::File`.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub file_path: Option<String>,
    /// Optional arbitrary JSON metadata.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub metadata: Option<serde_json::Value>,
}

/// The classification of the message content or media stream frame.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ContentType {
    /// Plain text message.
    Text,
    /// Rich HTML message.
    Html,
    /// Markdown formatted text.
    Markdown,
    /// Uploaded file.
    File,
    /// Live audio stream frame.
    AudioStream,
    /// Live video stream frame.
    VideoStream,
    /// Uploaded image file.
    Image,
}

/// Shared application state accessible by all request handlers and server loops.
pub struct AppState {
    /// Loaded server configuration.
    pub config: Config,
    /// Thread-safe lock on the session manager which handles chat logs and file assets.
    pub session_manager: Arc<RwLock<SessionManager>>,
    /// Broadcast channel for sending AI responses to output subscribers.
    pub response_tx: broadcast::Sender<AgentMessage>,
    /// Broadcast channel for live video frames received from clients.
    pub video_tx: broadcast::Sender<Vec<u8>>,
    /// Broadcast channel for live audio frames received from clients.
    pub audio_tx: broadcast::Sender<Vec<u8>>,
    /// Thread-safe flag indicating if the addon feature is enabled at runtime.
    pub addon_enabled: Arc<RwLock<bool>>,
}

impl AppState {
    /// Create a new application state from the provided configuration.
    ///
    /// This initializes the broadcast channels and loads existing session histories.
    ///
    /// # Errors
    ///
    /// Returns an error if the session manager fails to load from disk.
    pub async fn new(config: Config) -> Result<Self, Box<dyn std::error::Error + Send + Sync>> {
        let (response_tx, _) = broadcast::channel(256);
        let (video_tx, _) = broadcast::channel(64);
        let (audio_tx, _) = broadcast::channel(64);
        let addon_enabled = config.addon.enabled;

        let session_manager = SessionManager::new(&config.addon.session_history_dir)?;

        Ok(Self {
            config,
            session_manager: Arc::new(RwLock::new(session_manager)),
            response_tx,
            video_tx,
            audio_tx,
            addon_enabled: Arc::new(RwLock::new(addon_enabled)),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_content_type_serialization() {
        assert_eq!(
            serde_json::to_value(ContentType::Text).unwrap(),
            serde_json::json!("text")
        );
        assert_eq!(
            serde_json::to_value(ContentType::Html).unwrap(),
            serde_json::json!("html")
        );
        assert_eq!(
            serde_json::to_value(ContentType::Markdown).unwrap(),
            serde_json::json!("markdown")
        );
        assert_eq!(
            serde_json::to_value(ContentType::File).unwrap(),
            serde_json::json!("file")
        );
        assert_eq!(
            serde_json::to_value(ContentType::AudioStream).unwrap(),
            serde_json::json!("audio_stream")
        );
        assert_eq!(
            serde_json::to_value(ContentType::VideoStream).unwrap(),
            serde_json::json!("video_stream")
        );
        assert_eq!(
            serde_json::to_value(ContentType::Image).unwrap(),
            serde_json::json!("image")
        );
    }

    #[test]
    fn test_content_type_deserialization() {
        assert!(matches!(
            serde_json::from_str::<ContentType>("\"text\"").unwrap(),
            ContentType::Text
        ));
        assert!(matches!(
            serde_json::from_str::<ContentType>("\"html\"").unwrap(),
            ContentType::Html
        ));
        assert!(matches!(
            serde_json::from_str::<ContentType>("\"markdown\"").unwrap(),
            ContentType::Markdown
        ));
        assert!(matches!(
            serde_json::from_str::<ContentType>("\"file\"").unwrap(),
            ContentType::File
        ));
        assert!(matches!(
            serde_json::from_str::<ContentType>("\"audio_stream\"").unwrap(),
            ContentType::AudioStream
        ));
        assert!(matches!(
            serde_json::from_str::<ContentType>("\"video_stream\"").unwrap(),
            ContentType::VideoStream
        ));
        assert!(matches!(
            serde_json::from_str::<ContentType>("\"image\"").unwrap(),
            ContentType::Image
        ));
    }

    #[test]
    fn test_agent_message_roundtrip() {
        let msg = AgentMessage {
            id: "msg-1".to_string(),
            session_id: "session-1".to_string(),
            content_type: ContentType::Text,
            payload: "Hello world".to_string(),
            timestamp: "2024-01-01T00:00:00Z".to_string(),
            file_path: None,
            metadata: None,
        };
        let json = serde_json::to_string(&msg).unwrap();
        let deserialized: AgentMessage = serde_json::from_str(&json).unwrap();
        assert_eq!(deserialized.id, msg.id);
        assert_eq!(deserialized.session_id, msg.session_id);
        assert_eq!(deserialized.payload, msg.payload);
        assert!(matches!(deserialized.content_type, ContentType::Text));
    }

    #[test]
    fn test_agent_message_with_file() {
        let msg = AgentMessage {
            id: "msg-2".to_string(),
            session_id: "session-1".to_string(),
            content_type: ContentType::File,
            payload: "File uploaded".to_string(),
            timestamp: "2024-01-01T00:00:00Z".to_string(),
            file_path: Some("/tmp/file.txt".to_string()),
            metadata: Some(serde_json::json!({"size": 42})),
        };
        let json = serde_json::to_string(&msg).unwrap();
        let deserialized: AgentMessage = serde_json::from_str(&json).unwrap();
        assert_eq!(deserialized.file_path, Some("/tmp/file.txt".to_string()));
        assert_eq!(deserialized.metadata.unwrap()["size"], 42);
    }
}
