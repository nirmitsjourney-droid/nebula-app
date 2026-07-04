//! # AI Agent Communication Module
//!
//! This module coordinates the interaction with configured AI agent runners. It supports
//! two communication modes: `"stdio"` (spawning process commands and communicating over stdin/stdout)
//! and `"http"` (sending POST requests to an external endpoint). It also handles live video and audio frame
//! streaming forwarders in the background.

use crate::addon;
use crate::config::Config;
use crate::state::{AgentMessage, AppState};
use serde_json::json;
use std::sync::Arc;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::process::Command;
use tracing::{error, info};

/// Build the JSON payload to send to the AI agent.
///
/// If the addon is enabled, this dynamically injects the contents of `agent.md`
/// and the long-term memory file into the payload metadata.
///
/// # Errors
///
/// Returns an error if JSON construction fails.
async fn build_agent_payload(
    config: &Config,
    addon_enabled: bool,
    message: &AgentMessage,
) -> Result<serde_json::Value, Box<dyn std::error::Error + Send + Sync>> {
    let mut payload = json!({
        "id": message.id,
        "session_id": message.session_id,
        "content_type": message.content_type,
        "payload": message.payload,
        "timestamp": message.timestamp,
    });

    if let Some(ref fp) = message.file_path {
        payload["file_path"] = json!(fp);
    }
    if let Some(ref meta) = message.metadata {
        payload["metadata"] = meta.clone();
    }

    if addon_enabled {
        // Attach agent.md
        match addon::read_agent_md(&config.addon.agent_md_path).await {
            Ok(agent_md) => { payload["agent_md"] = json!(agent_md); }
            Err(e) => { error!("Failed to read agent.md: {}", e); }
        }

        // Attach long-term memory
        match addon::read_memory(&config.addon.memory_file).await {
            Ok(memory) => { payload["long_term_memory"] = json!(memory); }
            Err(e) => { error!("Failed to read long-term memory: {}", e); }
        }
    }

    Ok(payload)
}

/// Forward a user message or upload payload to the AI agent and await the response.
///
/// Dispatches the request depending on the agent's communication mode (`stdio` or `http`).
///
/// # Errors
///
/// Returns an error if the agent mode is unknown or communication fails.
pub async fn forward_to_agent(
    state: &Arc<AppState>,
    message: AgentMessage,
) -> Result<String, Box<dyn std::error::Error + Send + Sync>> {
    let addon_enabled = *state.addon_enabled.read().await;
    let payload = build_agent_payload(&state.config, addon_enabled, &message).await?;
    let payload_str = serde_json::to_string(&payload)?;

    match state.config.agent.mode.as_str() {
        "stdio" => forward_stdio(&state.config.agent.command, &state.config.agent.args, &payload_str).await,
        "http" => forward_http(&state.config.agent.endpoint_url, &payload_str).await,
        other => Err(format!("Unknown agent mode: {}", other).into()),
    }
}

/// Forward the payload to a spawned child process via stdin and read its response from stdout.
///
/// # Errors
///
/// Returns an error if command spawning, piping, writing, or reading fails.
async fn forward_stdio(
    command: &str,
    args: &[String],
    payload: &str,
) -> Result<String, Box<dyn std::error::Error + Send + Sync>> {
    info!("Forwarding to agent via stdio: {} {:?}", command, args);

    let mut child = Command::new(command)
        .args(args)
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .spawn()?;

    // Write payload to stdin
    if let Some(mut stdin) = child.stdin.take() {
        stdin.write_all(payload.as_bytes()).await?;
        stdin.write_all(b"\n").await?;
        // Drop stdin to signal EOF
        drop(stdin);
    }

    // Read response from stdout
    let mut response = String::new();
    if let Some(stdout) = child.stdout.take() {
        let mut reader = BufReader::new(stdout);
        reader.read_line(&mut response).await?;
    }

    let status = child.wait().await?;
    if !status.success() {
        error!("Agent process exited with status: {}", status);
    }

    Ok(response.trim().to_string())
}

/// Forward the payload to the agent via an HTTP POST request.
///
/// Uses a direct, manual TCP connection to transmit HTTP/1.1 headers and request body to avoid
/// pulling in heavy external dependencies like `reqwest`.
///
/// # Errors
///
/// Returns an error if parsing the host, connecting, or reading the response stream fails.
async fn forward_http(
    endpoint_url: &str,
    _payload: &str,
) -> Result<String, Box<dyn std::error::Error + Send + Sync>> {
    info!("Forwarding to agent via HTTP: {}", endpoint_url);

    // Use a simple TCP connection to avoid requiring reqwest dependency.
    // Parse the URL manually.
    let url = endpoint_url.trim_start_matches("http://");
    let (host_port, path) = url.split_once('/').unwrap_or((url, ""));
    let path = format!("/{}", path);

    let stream = tokio::net::TcpStream::connect(host_port).await?;
    let (reader, mut writer) = tokio::io::split(stream);

    let request = format!(
        "POST {} HTTP/1.1\r\nHost: {}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
        path, host_port, _payload.len(), _payload
    );
    writer.write_all(request.as_bytes()).await?;

    let mut buf_reader = BufReader::new(reader);
    let mut response = String::new();
    let mut body_started = false;
    let mut line = String::new();

    loop {
        line.clear();
        let bytes_read = buf_reader.read_line(&mut line).await?;
        if bytes_read == 0 {
            break;
        }
        if body_started {
            response.push_str(&line);
        }
        if line.trim().is_empty() && !body_started {
            body_started = true;
        }
    }

    Ok(response.trim().to_string())
}

/// Spawn a background task to receive live video frames, base64-encode them, and forward to the agent process.
///
/// # Errors
///
/// Returns an error if task initiation fails.
pub async fn start_video_forwarder(
    state: Arc<AppState>,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let mut video_rx = state.video_tx.subscribe();
    let config = state.config.clone();

    tokio::spawn(async move {
        info!("Video forwarder started");
        while let Ok(frame) = video_rx.recv().await {
            // Encode frame as base64 and forward
            let b64 = base64_encode(&frame);
            let payload = json!({
                "type": "video_frame",
                "data": b64,
                "timestamp": chrono::Utc::now().to_rfc3339(),
            });

            if let Err(e) = forward_stdio(
                &config.agent.command,
                &config.agent.args,
                &payload.to_string(),
            ).await {
                error!("Failed to forward video frame: {}", e);
            }
        }
    });

    Ok(())
}

/// Spawn a background task to receive live audio frames, base64-encode them, and forward to the agent process.
///
/// # Errors
///
/// Returns an error if task initiation fails.
pub async fn start_audio_forwarder(
    state: Arc<AppState>,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let mut audio_rx = state.audio_tx.subscribe();
    let config = state.config.clone();

    tokio::spawn(async move {
        info!("Audio forwarder started");
        while let Ok(frame) = audio_rx.recv().await {
            let b64 = base64_encode(&frame);
            let payload = json!({
                "type": "audio_frame",
                "data": b64,
                "timestamp": chrono::Utc::now().to_rfc3339(),
            });

            if let Err(e) = forward_stdio(
                &config.agent.command,
                &config.agent.args,
                &payload.to_string(),
            ).await {
                error!("Failed to forward audio frame: {}", e);
            }
        }
    });

    Ok(())
}

/// Standard Base64 encoder helper function.
///
/// Converts a byte slice to its base64 string representation.
fn base64_encode(data: &[u8]) -> String {
    const CHARS: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut result = String::new();
    for chunk in data.chunks(3) {
        let b0 = chunk[0] as u32;
        let b1 = if chunk.len() > 1 { chunk[1] as u32 } else { 0 };
        let b2 = if chunk.len() > 2 { chunk[2] as u32 } else { 0 };
        let triple = (b0 << 16) | (b1 << 8) | b2;

        result.push(CHARS[((triple >> 18) & 0x3F) as usize] as char);
        result.push(CHARS[((triple >> 12) & 0x3F) as usize] as char);
        if chunk.len() > 1 {
            result.push(CHARS[((triple >> 6) & 0x3F) as usize] as char);
        } else {
            result.push('=');
        }
        if chunk.len() > 2 {
            result.push(CHARS[(triple & 0x3F) as usize] as char);
        } else {
            result.push('=');
        }
    }
    result
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::state::ContentType;

    #[test]
    fn test_base64_encode_empty() {
        assert_eq!(base64_encode(b""), "");
    }

    #[test]
    fn test_base64_encode_hello() {
        assert_eq!(base64_encode(b"Hello, World!"), "SGVsbG8sIFdvcmxkIQ==");
    }

    #[test]
    fn test_base64_encode_padding() {
        assert_eq!(base64_encode(b"f"), "Zg==");
        assert_eq!(base64_encode(b"fo"), "Zm8=");
        assert_eq!(base64_encode(b"foo"), "Zm9v");
        assert_eq!(base64_encode(b"foob"), "Zm9vYg==");
        assert_eq!(base64_encode(b"fooba"), "Zm9vYmE=");
        assert_eq!(base64_encode(b"foobar"), "Zm9vYmFy");
    }

    #[test]
    fn test_base64_encode_binary() {
        let data = vec![0x00, 0x01, 0x02, 0x03];
        assert_eq!(base64_encode(&data), "AAECAw==");
    }

    #[test]
    fn test_base64_encode_known() {
        // Standard test vectors
        assert_eq!(base64_encode(b""), "");
        assert_eq!(base64_encode(b"f"), "Zg==");
        assert_eq!(base64_encode(b"fo"), "Zm8=");
        assert_eq!(base64_encode(b"foo"), "Zm9v");
        assert_eq!(base64_encode(b"foob"), "Zm9vYg==");
        assert_eq!(base64_encode(b"fooba"), "Zm9vYmE=");
        assert_eq!(base64_encode(b"foobar"), "Zm9vYmFy");
    }

    #[test]
    fn test_build_agent_payload_text() {
        let config = Config {
            input_port: 3001,
            output_port: 3002,
            addon: crate::config::AddonConfig { enabled: false, memory_file: String::new(), session_history_dir: String::new(), agent_md_path: String::new() },
            agent: crate::config::AgentConfig { command: "echo".into(), args: vec![], mode: "stdio".into(), endpoint_url: String::new() },
        };
        let message = AgentMessage {
            id: "msg-1".to_string(),
            session_id: "session-1".to_string(),
            content_type: ContentType::Text,
            payload: "Hello".to_string(),
            timestamp: "2024-01-01T00:00:00Z".to_string(),
            file_path: None,
            metadata: None,
        };

        let payload = tokio::runtime::Runtime::new().unwrap().block_on(
            build_agent_payload(&config, false, &message)
        ).unwrap();

        assert_eq!(payload["id"], "msg-1");
        assert_eq!(payload["session_id"], "session-1");
        assert_eq!(payload["payload"], "Hello");
        assert!(payload.get("agent_md").is_none());
        assert!(payload.get("long_term_memory").is_none());
    }

    #[test]
    fn test_build_agent_payload_with_file_and_metadata() {
        let config = Config {
            input_port: 3001,
            output_port: 3002,
            addon: crate::config::AddonConfig { enabled: false, memory_file: String::new(), session_history_dir: String::new(), agent_md_path: String::new() },
            agent: crate::config::AgentConfig { command: "echo".into(), args: vec![], mode: "stdio".into(), endpoint_url: String::new() },
        };
        let message = AgentMessage {
            id: "msg-2".to_string(),
            session_id: "session-1".to_string(),
            content_type: ContentType::File,
            payload: "File uploaded".to_string(),
            timestamp: "2024-01-01T00:00:00Z".to_string(),
            file_path: Some("/tmp/test.txt".to_string()),
            metadata: Some(serde_json::json!({"filename": "test.txt", "size": 100})),
        };

        let payload = tokio::runtime::Runtime::new().unwrap().block_on(
            build_agent_payload(&config, false, &message)
        ).unwrap();

        assert_eq!(payload["file_path"], "/tmp/test.txt");
        assert_eq!(payload["metadata"]["filename"], "test.txt");
        assert_eq!(payload["metadata"]["size"], 100);
    }
}
