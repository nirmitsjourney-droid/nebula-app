//! # Configuration Module
//!
//! This module defines the configuration structures (`Config`, `AddonConfig`, `AgentConfig`) 
//! loaded from `config.toml`. It also handles default configurations when the file is missing or values are omitted.

use serde::Deserialize;
use std::path::PathBuf;

/// Complete application configuration.
#[derive(Debug, Clone, Deserialize)]
pub struct Config {
    /// Port where the client submits text, files, and streams. Defaults to `3001`.
    #[serde(default = "default_input_port")]
    pub input_port: u16,
    /// Port where the client subscribes to real-time response streams and broadcasts. Defaults to `3002`.
    #[serde(default = "default_output_port")]
    pub output_port: u16,
    /// Configuration settings for the session manager and long-term memory addon.
    #[serde(default)]
    pub addon: AddonConfig,
    /// Configuration settings for the AI Agent runner.
    #[serde(default)]
    pub agent: AgentConfig,
}

/// Configuration settings for the session memory and persistent files addon.
#[derive(Debug, Clone, Deserialize)]
pub struct AddonConfig {
    /// Toggles the custom memory and session history addon on or off. Defaults to `true`.
    #[serde(default = "default_addon_enabled")]
    pub enabled: bool,
    /// Path to the long-term markdown memory file. Defaults to `data/memory/long_term_memory.md`.
    #[serde(default = "default_memory_file")]
    pub memory_file: String,
    /// Path to the folder containing session history data. Defaults to `data/memory/chats`.
    #[serde(default = "default_session_dir")]
    pub session_history_dir: String,
    /// Path to the markdown file defining the agent's persona. Defaults to `data/agent.md`.
    #[serde(default = "default_agent_md")]
    pub agent_md_path: String,
}

/// Configuration settings for the AI Agent runner.
#[derive(Debug, Clone, Deserialize)]
pub struct AgentConfig {
    /// The command to launch the AI agent process (e.g., `"openclaw"`, `"hermes"`, `"opencode"`, `"echo"`).
    #[serde(default = "default_agent_command")]
    pub command: String,
    /// Optional arguments to pass to the agent process command line.
    #[serde(default)]
    pub args: Vec<String>,
    /// Communication mode: `"stdio"` (communicates via stdin/stdout) or `"http"` (communicates via HTTP endpoint).
    #[serde(default = "default_agent_mode")]
    pub mode: String,
    /// Base URL endpoint of the agent, if communication mode is set to `"http"`.
    #[serde(default = "default_agent_url")]
    pub endpoint_url: String,
}

fn default_input_port() -> u16 { 3001 }
fn default_output_port() -> u16 { 3002 }
fn default_addon_enabled() -> bool { true }
fn default_memory_file() -> String { "data/memory/long_term_memory.md".to_string() }
fn default_session_dir() -> String { "data/memory/chats".to_string() }
fn default_agent_md() -> String { "data/agent.md".to_string() }
fn default_agent_command() -> String { "echo".to_string() }
fn default_agent_mode() -> String { "stdio".to_string() }
fn default_agent_url() -> String { "http://localhost:8080".to_string() }

impl Default for AddonConfig {
    fn default() -> Self {
        Self {
            enabled: default_addon_enabled(),
            memory_file: default_memory_file(),
            session_history_dir: default_session_dir(),
            agent_md_path: default_agent_md(),
        }
    }
}

impl Default for AgentConfig {
    fn default() -> Self {
        Self {
            command: default_agent_command(),
            args: vec![],
            mode: default_agent_mode(),
            endpoint_url: default_agent_url(),
        }
    }
}

impl Config {
    /// Load configuration from `config.toml` in the current working directory.
    ///
    /// If the file is not found, defaults are loaded and a warning is logged.
    ///
    /// # Errors
    ///
    /// Returns an error if the file exists but cannot be read or parsed.
    pub fn load() -> Result<Self, Box<dyn std::error::Error + Send + Sync>> {
        let config_path = PathBuf::from("config.toml");
        if config_path.exists() {
            let content = std::fs::read_to_string(&config_path)?;
            let config: Config = toml::from_str(&content)?;
            Ok(config)
        } else {
            tracing::warn!("config.toml not found, using defaults");
            Ok(Config {
                input_port: default_input_port(),
                output_port: default_output_port(),
                addon: AddonConfig::default(),
                agent: AgentConfig::default(),
            })
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_input_port() {
        assert_eq!(default_input_port(), 3001);
    }

    #[test]
    fn test_default_output_port() {
        assert_eq!(default_output_port(), 3002);
    }

    #[test]
    fn test_default_addon_enabled() {
        assert!(default_addon_enabled());
    }

    #[test]
    fn test_default_agent_command() {
        assert_eq!(default_agent_command(), "echo");
    }

    #[test]
    fn test_default_agent_mode() {
        assert_eq!(default_agent_mode(), "stdio");
    }

    #[test]
    fn test_config_parse_full() {
        let toml_str = r#"
input_port = 4000
output_port = 5000

[addon]
enabled = false
memory_file = "test_memory.md"
session_history_dir = "test_sessions"
agent_md_path = "test_agent.md"

[agent]
command = "python"
args = ["-m", "my_agent"]
mode = "http"
endpoint_url = "http://localhost:9000"
"#;
        let config: Config = toml::from_str(toml_str).expect("Failed to parse config");
        assert_eq!(config.input_port, 4000);
        assert_eq!(config.output_port, 5000);
        assert!(!config.addon.enabled);
        assert_eq!(config.addon.memory_file, "test_memory.md");
        assert_eq!(config.addon.session_history_dir, "test_sessions");
        assert_eq!(config.addon.agent_md_path, "test_agent.md");
        assert_eq!(config.agent.command, "python");
        assert_eq!(config.agent.args, vec!["-m", "my_agent"]);
        assert_eq!(config.agent.mode, "http");
        assert_eq!(config.agent.endpoint_url, "http://localhost:9000");
    }

    #[test]
    fn test_config_defaults() {
        let config = Config {
            input_port: default_input_port(),
            output_port: default_output_port(),
            addon: AddonConfig::default(),
            agent: AgentConfig::default(),
        };
        assert_eq!(config.input_port, 3001);
        assert_eq!(config.output_port, 3002);
        assert!(config.addon.enabled);
        assert_eq!(config.agent.command, "echo");
        assert_eq!(config.agent.mode, "stdio");
    }

    #[test]
    fn test_addon_config_default() {
        let addon = AddonConfig::default();
        assert!(addon.enabled);
        assert_eq!(addon.memory_file, "data/memory/long_term_memory.md");
        assert_eq!(addon.session_history_dir, "data/memory/chats");
        assert_eq!(addon.agent_md_path, "data/agent.md");
    }

    #[test]
    fn test_agent_config_default() {
        let agent = AgentConfig::default();
        assert_eq!(agent.command, "echo");
        assert!(agent.args.is_empty());
        assert_eq!(agent.mode, "stdio");
        assert_eq!(agent.endpoint_url, "http://localhost:8080");
    }
}
