//! # Addon Module
//!
//! This module provides functions to initialize and interact with the custom memory and session
//! context files, including the long-term memory file and the agent persona markdown template (`agent.md`).

use crate::config::AddonConfig;
use crate::state::AppState;
use std::path::Path;
use std::sync::Arc;
use tracing::info;

/// Initialize the addon: create directories and memory files if they do not exist.
///
/// This checks if `memory_file` and `agent_md_path` exist, creating them with default templates
/// if they are missing. It also ensures the session history directory is created.
///
/// # Errors
///
/// Returns an error if directory creation or file writing fails.
pub async fn initialize(
    config: &AddonConfig,
    _state: &Arc<AppState>,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    // Create memory file directory and file
    let memory_path = Path::new(&config.memory_file);
    if let Some(parent) = memory_path.parent() {
        tokio::fs::create_dir_all(parent).await?;
    }
    if !memory_path.exists() {
        let initial_content = "# Long-Term Memory\n\n\
            > This file is automatically maintained by the Nebula addon.\n\
            > It stores persistent context across all sessions.\n\n\
            ## Key Facts\n\n\
            ## User Preferences\n\n\
            ## Learned Context\n\n";
        tokio::fs::write(memory_path, initial_content).await?;
        info!("Created long-term memory file: {}", config.memory_file);
    }

    // Create session history directory
    tokio::fs::create_dir_all(&config.session_history_dir).await?;
    info!("Session history directory ready: {}", config.session_history_dir);

    // Create agent.md if it doesn't exist
    let agent_md_path = Path::new(&config.agent_md_path);
    if let Some(parent) = agent_md_path.parent() {
        tokio::fs::create_dir_all(parent).await?;
    }
    if !agent_md_path.exists() {
        let agent_md_content = "# Agent Configuration\n\n\
            > This file is passed to the AI agent alongside user input.\n\
            > Customize it to define the agent's persona, instructions, and behavior.\n\n\
            ## Identity\n\n\
            You are a helpful AI assistant connected via the Nebula backend.\n\n\
            ## Instructions\n\n\
            - Respond clearly and concisely.\n\
            - Use the long-term memory to maintain context across sessions.\n\
            - Reference session history when relevant.\n\n\
            ## Capabilities\n\n\
            - Text, HTML, and Markdown processing\n\
            - File analysis (all types)\n\
            - Live audio and video stream processing\n\n";
        tokio::fs::write(agent_md_path, agent_md_content).await?;
        info!("Created agent.md: {}", config.agent_md_path);
    }

    Ok(())
}

/// Read the entire long-term memory file contents.
///
/// # Errors
///
/// Returns an error if the file cannot be read from disk.
pub async fn read_memory(memory_file: &str) -> Result<String, Box<dyn std::error::Error + Send + Sync>> {
    Ok(tokio::fs::read_to_string(memory_file).await?)
}

/// Append new information with a timestamp to a designated section in the long-term memory file.
///
/// # Errors
///
/// Returns an error if the file cannot be opened or written to.
#[allow(dead_code)]
pub async fn append_memory(
    memory_file: &str,
    section: &str,
    content: &str,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    use tokio::io::AsyncWriteExt;
    let mut file = tokio::fs::OpenOptions::new()
        .append(true)
        .open(memory_file)
        .await?;
    let entry = format!(
        "\n### {} — {}\n{}\n",
        section,
        chrono::Utc::now().format("%Y-%m-%d %H:%M:%S UTC"),
        content
    );
    file.write_all(entry.as_bytes()).await?;
    Ok(())
}

/// Read the agent persona markdown (`agent.md`) template content.
///
/// # Errors
///
/// Returns an error if the file cannot be read from disk.
pub async fn read_agent_md(agent_md_path: &str) -> Result<String, Box<dyn std::error::Error + Send + Sync>> {
    Ok(tokio::fs::read_to_string(agent_md_path).await?)
}
