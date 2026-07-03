//! # Session Management Module
//!
//! This module handles the creation, retrieval, and disk persistence of chat sessions.
//! Each session persists metadata (`session.json`), a Markdown transcript (`chat.md`),
//! uploaded raw input/output binaries, and user-uploaded media files or assets.

use chrono::Utc;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::PathBuf;
use tracing::info;

/// Metadata of a chat session, serialized to disk in `session.json`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Session {
    /// Unique session UUID.
    pub id: String,
    /// Timestamp of session creation.
    pub created_at: String,
    /// Timestamp of the last user or agent message in the session.
    pub last_active: String,
    /// Total number of messages recorded in this session.
    pub message_count: usize,
    /// Absolute or relative path to the folder housing this session's resources.
    pub folder_path: PathBuf,
}

/// Thread-safe manager responsible for tracking active sessions and directory structures.
pub struct SessionManager {
    /// The base directory containing all session subdirectories.
    base_dir: PathBuf,
    /// A in-memory cache map of loaded sessions.
    sessions: HashMap<String, Session>,
}

impl SessionManager {
    /// Initialize a `SessionManager` targeting the provided base directory.
    ///
    /// Iterates through existing subfolders to load any session metadata (`session.json`) present.
    ///
    /// # Errors
    ///
    /// Returns an error if reading the directory or parsing file contents fails.
    pub fn new(base_dir: &str) -> Result<Self, Box<dyn std::error::Error + Send + Sync>> {
        let base = PathBuf::from(base_dir);
        std::fs::create_dir_all(&base)?;

        // Load existing sessions from disk
        let mut sessions = HashMap::new();
        if base.exists() {
            for entry in std::fs::read_dir(&base)? {
                let entry = entry?;
                if entry.file_type()?.is_dir() {
                    let session_id = entry.file_name().to_string_lossy().to_string();
                    let meta_path = entry.path().join("session.json");
                    if meta_path.exists() {
                        let content = std::fs::read_to_string(&meta_path)?;
                        if let Ok(session) = serde_json::from_str::<Session>(&content) {
                            sessions.insert(session_id, session);
                        }
                    }
                }
            }
        }

        info!("Session manager initialized with {} existing sessions", sessions.len());
        Ok(Self { base_dir: base, sessions })
    }

    /// Create a new session, sets up the directory layout, and returns the session metadata.
    ///
    /// # Errors
    ///
    /// Returns an error if directory creation or file writing fails.
    pub fn create_session(&mut self) -> Result<Session, Box<dyn std::error::Error + Send + Sync>> {
        let id = uuid::Uuid::new_v4().to_string();
        let now = Utc::now().format("%Y-%m-%d %H:%M:%S UTC").to_string();
        let folder_path = self.base_dir.join(&id);

        std::fs::create_dir_all(&folder_path)?;
        std::fs::create_dir_all(folder_path.join("assets"))?;
        std::fs::create_dir_all(folder_path.join("inputs"))?;
        std::fs::create_dir_all(folder_path.join("outputs"))?;

        let session = Session {
            id: id.clone(),
            created_at: now.clone(),
            last_active: now,
            message_count: 0,
            folder_path: folder_path.clone(),
        };

        // Write session metadata
        let meta = serde_json::to_string_pretty(&session)?;
        std::fs::write(folder_path.join("session.json"), &meta)?;

        // Create chat log
        std::fs::write(
            folder_path.join("chat.md"),
            format!("# Chat Session {}\n\nStarted: {}\n\n---\n\n", &id[..8], &session.created_at),
        )?;

        self.sessions.insert(id, session.clone());
        info!("Created new session: {}", session.id);
        Ok(session)
    }

    /// Get a reference to an existing session by ID.
    pub fn get_session(&self, id: &str) -> Option<&Session> {
        self.sessions.get(id)
    }

    /// List all loaded sessions, sorted chronologically by `last_active` descending.
    pub fn list_sessions(&self) -> Vec<&Session> {
        let mut sessions: Vec<&Session> = self.sessions.values().collect();
        sessions.sort_by(|a, b| b.last_active.cmp(&a.last_active));
        sessions
    }

    /// Record a message in the session's chat log markdown and update session metadata.
    ///
    /// # Errors
    ///
    /// Returns an error if the session ID is not found, or if file writes fail.
    pub fn record_message(
        &mut self,
        session_id: &str,
        role: &str,
        content: &str,
    ) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        let session = self.sessions.get_mut(session_id)
            .ok_or_else(|| format!("Session not found: {}", session_id))?;

        session.message_count += 1;
        session.last_active = Utc::now().format("%Y-%m-%d %H:%M:%S UTC").to_string();

        // Append to chat log
        let entry = format!(
            "**[{}]** ({})\n{}\n\n---\n\n",
            role,
            &session.last_active,
            content
        );
        let chat_path = session.folder_path.join("chat.md");
        let mut existing = std::fs::read_to_string(&chat_path).unwrap_or_default();
        existing.push_str(&entry);
        std::fs::write(&chat_path, &existing)?;

        // Update session metadata
        let meta = serde_json::to_string_pretty(&session)?;
        std::fs::write(session.folder_path.join("session.json"), &meta)?;

        Ok(())
    }

    /// Delete a session: removes it from memory and recursively deletes its folder from disk.
    ///
    /// # Errors
    ///
    /// Returns an error if the session ID is not found or if deleting the folder fails.
    pub fn delete_session(&mut self, session_id: &str) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        let session = self.sessions.remove(session_id)
            .ok_or_else(|| format!("Session not found: {}", session_id))?;

        if session.folder_path.exists() {
            std::fs::remove_dir_all(&session.folder_path)?;
            info!("Deleted session folder: {}", session.folder_path.display());
        }
        Ok(())
    }

    /// Save a raw byte buffer file asset into the session's `assets/` subfolder.
    ///
    /// # Errors
    ///
    /// Returns an error if session is not found, or file writing fails.
    pub fn save_asset(
        &self,
        session_id: &str,
        filename: &str,
        data: &[u8],
    ) -> Result<PathBuf, Box<dyn std::error::Error + Send + Sync>> {
        let session = self.sessions.get(session_id)
            .ok_or_else(|| format!("Session not found: {}", session_id))?;

        let asset_path = session.folder_path.join("assets").join(filename);
        std::fs::write(&asset_path, data)?;
        info!("Saved asset to session {}: {}", &session_id[..8], filename);
        Ok(asset_path)
    }

    /// Save raw byte input data into the session's `inputs/` subfolder.
    ///
    /// # Errors
    ///
    /// Returns an error if session is not found, or file writing fails.
    #[allow(dead_code)]
    pub fn save_input(
        &self,
        session_id: &str,
        filename: &str,
        data: &[u8],
    ) -> Result<PathBuf, Box<dyn std::error::Error + Send + Sync>> {
        let session = self.sessions.get(session_id)
            .ok_or_else(|| format!("Session not found: {}", session_id))?;

        let input_path = session.folder_path.join("inputs").join(filename);
        std::fs::write(&input_path, data)?;
        Ok(input_path)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::env;

    fn temp_dir() -> PathBuf {
        let dir = env::temp_dir().join(format!("nebula_test_{}", uuid::Uuid::new_v4()));
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn test_session_new_creates_base_dir() {
        let dir = temp_dir();
        let base = dir.join("sessions");
        let manager = SessionManager::new(base.to_str().unwrap()).unwrap();
        assert!(base.exists());
        assert!(manager.sessions.is_empty());
    }

    #[test]
    fn test_create_session() {
        let dir = temp_dir();
        let base = dir.join("sessions");
        let mut manager = SessionManager::new(base.to_str().unwrap()).unwrap();

        let session = manager.create_session().unwrap();
        assert!(!session.id.is_empty());
        assert!(session.folder_path.exists());
        assert!(session.folder_path.join("session.json").exists());
        assert!(session.folder_path.join("chat.md").exists());
        assert!(session.folder_path.join("assets").exists());
        assert!(session.folder_path.join("inputs").exists());
        assert!(session.folder_path.join("outputs").exists());
        assert_eq!(session.message_count, 0);
    }

    #[test]
    fn test_get_session() {
        let dir = temp_dir();
        let base = dir.join("sessions");
        let mut manager = SessionManager::new(base.to_str().unwrap()).unwrap();

        let session = manager.create_session().unwrap();
        let retrieved = manager.get_session(&session.id);
        assert!(retrieved.is_some());
        assert_eq!(retrieved.unwrap().id, session.id);

        assert!(manager.get_session("nonexistent").is_none());
    }

    #[test]
    fn test_list_sessions() {
        let dir = temp_dir();
        let base = dir.join("sessions");
        let mut manager = SessionManager::new(base.to_str().unwrap()).unwrap();

        assert!(manager.list_sessions().is_empty());

        manager.create_session().unwrap();
        assert_eq!(manager.list_sessions().len(), 1);

        manager.create_session().unwrap();
        assert_eq!(manager.list_sessions().len(), 2);
    }

    #[test]
    fn test_record_message() {
        let dir = temp_dir();
        let base = dir.join("sessions");
        let mut manager = SessionManager::new(base.to_str().unwrap()).unwrap();

        let session = manager.create_session().unwrap();
        manager.record_message(&session.id, "User", "Hello").unwrap();
        manager.record_message(&session.id, "Agent", "Hi there!").unwrap();

        let updated = manager.get_session(&session.id).unwrap();
        assert_eq!(updated.message_count, 2);

        let chat = std::fs::read_to_string(updated.folder_path.join("chat.md")).unwrap();
        assert!(chat.contains("Hello"));
        assert!(chat.contains("Hi there!"));
    }

    #[test]
    fn test_record_message_invalid_session() {
        let dir = temp_dir();
        let base = dir.join("sessions");
        let mut manager = SessionManager::new(base.to_str().unwrap()).unwrap();

        let result = manager.record_message("nonexistent", "User", "test");
        assert!(result.is_err());
    }

    #[test]
    fn test_save_asset() {
        let dir = temp_dir();
        let base = dir.join("sessions");
        let mut manager = SessionManager::new(base.to_str().unwrap()).unwrap();

        let session = manager.create_session().unwrap();
        let data = b"test file content";
        let path = manager.save_asset(&session.id, "test.txt", data).unwrap();
        assert!(path.exists());
        assert_eq!(std::fs::read_to_string(&path).unwrap(), "test file content");
    }

    #[test]
    fn test_save_asset_invalid_session() {
        let dir = temp_dir();
        let base = dir.join("sessions");
        let manager = SessionManager::new(base.to_str().unwrap()).unwrap();

        let result = manager.save_asset("nonexistent", "test.txt", b"data");
        assert!(result.is_err());
    }

    #[test]
    fn test_save_input() {
        let dir = temp_dir();
        let base = dir.join("sessions");
        let mut manager = SessionManager::new(base.to_str().unwrap()).unwrap();

        let session = manager.create_session().unwrap();
        let data = b"input data";
        let path = manager.save_input(&session.id, "input.bin", data).unwrap();
        assert!(path.exists());
        assert_eq!(std::fs::read_to_string(&path).unwrap(), "input data");
    }

    #[test]
    fn test_session_json_roundtrip() {
        let session = Session {
            id: "test-id".to_string(),
            created_at: "2024-01-01 00:00:00 UTC".to_string(),
            last_active: "2024-01-01 00:00:00 UTC".to_string(),
            message_count: 5,
            folder_path: PathBuf::from("/tmp/test"),
        };
        let json = serde_json::to_string_pretty(&session).unwrap();
        let deserialized: Session = serde_json::from_str(&json).unwrap();
        assert_eq!(deserialized.id, session.id);
        assert_eq!(deserialized.message_count, session.message_count);
        assert_eq!(deserialized.folder_path, session.folder_path);
    }

    #[test]
    fn test_load_existing_sessions() {
        let dir = temp_dir();
        let base = dir.join("sessions");
        let mut manager = SessionManager::new(base.to_str().unwrap()).unwrap();
        let session = manager.create_session().unwrap();

        // Create a new manager reading the same directory
        let manager2 = SessionManager::new(base.to_str().unwrap()).unwrap();
        let loaded = manager2.get_session(&session.id);
        assert!(loaded.is_some());
        assert_eq!(loaded.unwrap().message_count, 0);
    }
}
