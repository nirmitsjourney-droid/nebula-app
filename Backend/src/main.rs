//! # Nebula Backend Server Entrypoint
//!
//! This module initializes logging, loads configuration, manages shared application state,
//! sets up background tasks for forwarding media streams, and starts the dual-port
//! web servers (input and output) using Axum.

use std::sync::Arc;
use tracing::info;

use nebula_backend::{addon, agent, config, input, output, state};

const DEFAULT_CONFIG_TOML: &str = r#"# Nebula Backend Server Configuration
# Located in ~/.nebula/config.toml

input_port = 3001
output_port = 3002

[addon]
enabled = true

[agent]
command = "powershell"
args = ["-File", "WINDOWS_PLACEHOLDER/opencode-wrapper.ps1"]
mode = "stdio"
"#;

const DEFAULT_AGENT_MD: &str = r#"# Agent Configuration

> This file is passed to the AI agent alongside user input.
> Customize it to define the agent's persona, instructions, and behavior.

## Identity

You are a helpful AI assistant connected via the Nebula backend.

## Instructions

- Respond clearly and concisely.
- Use the long-term memory to maintain context across sessions.
- Reference session history when relevant.

## Capabilities

- Text, HTML, and Markdown processing
- File analysis (all types)
- Live audio and video stream processing
"#;

const DEFAULT_MEMORY_MD: &str = r#"# Long-Term Memory

> This file is automatically maintained by the Nebula addon.
> It stores persistent context across all sessions.

## Key Facts

## User Preferences

## Learned Context
"#;

const OPENCODE_WRAPPER_PS1: &str = r#"# opencode-wrapper.ps1
# Reads JSON from stdin, maintains per-session conversation history,
# sends the full conversation context to opencode run,
# and outputs only the new response as a single line.

param()

try {
    $inputJson = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($inputJson)) {
        exit 1
    }
    $parsed = $inputJson | ConvertFrom-Json
    $sessionId = $parsed.session_id
    $message = $parsed.payload
    $agentMd   = $parsed.agent_md
    $longTermMemory = $parsed.long_term_memory
    if ([string]::IsNullOrWhiteSpace($message)) {
        $message = ""
    }

    # Determine nebula directory from this script's location
    $nebulaDir = Split-Path -Parent $PSCommandPath
    $convDir = Join-Path $nebulaDir "data\conversations"
    if (-not (Test-Path $convDir)) {
        New-Item -ItemType Directory -Path $convDir -Force | Out-Null
    }
    $convFile = Join-Path $convDir "$sessionId.txt"

    # Read existing conversation
    $conversation = ""
    if (Test-Path $convFile) {
        $conversation = Get-Content $convFile -Raw
    }

    # If this is a fresh conversation and agent_md is provided, prepend system instructions
    if ([string]::IsNullOrWhiteSpace($conversation) -and -not [string]::IsNullOrWhiteSpace($agentMd)) {
        $conversation = "System: $agentMd`r`n`r`n"
    }

    # If long-term memory is provided, include it as context (only on first message)
    if ($conversation -match "^System:" -and -not [string]::IsNullOrWhiteSpace($longTermMemory)) {
        $conversation += "Context: $longTermMemory`r`n`r`n"
    }

    # Append user message
    $conversation += "User: $message`r`n"

    # Send full conversation to opencode
    $output = & opencode run --format json $conversation 2>&1
    $responseText = ""
    foreach ($line in $output) {
        $lineStr = "$line"
        if ([string]::IsNullOrWhiteSpace($lineStr)) { continue }
        try {
            $event = $lineStr | ConvertFrom-Json
            if ($event.type -eq "text" -and $event.part.text) {
                $responseText += $event.part.text
            }
        } catch {
            # skip non-JSON lines
        }
    }
    if ([string]::IsNullOrWhiteSpace($responseText)) {
        $responseText = "I processed your request."
    }

    # Append response to conversation and persist
    $conversation += "Assistant: $responseText`r`n"
    Set-Content -Path $convFile -Value $conversation -Encoding utf8

    Write-Output $responseText
} catch {
    Write-Output "Error processing request"
    exit 1
}
"#;

const CLAUDE_WRAPPER_PS1: &str = r#"# claude-wrapper.ps1
# Reads JSON from stdin, maintains per-session conversation history,
# sends the full conversation context to claude,
# and outputs only the new response as a single line.

param()

try {
    $inputJson = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($inputJson)) {
        exit 1
    }
    $parsed = $inputJson | ConvertFrom-Json
    $sessionId = $parsed.session_id
    $message = $parsed.payload
    $agentMd   = $parsed.agent_md
    $longTermMemory = $parsed.long_term_memory
    if ([string]::IsNullOrWhiteSpace($message)) {
        $message = ""
    }

    # Determine nebula directory from this script's location
    $nebulaDir = Split-Path -Parent $PSCommandPath
    $convDir = Join-Path $nebulaDir "data\conversations"
    if (-not (Test-Path $convDir)) {
        New-Item -ItemType Directory -Path $convDir -Force | Out-Null
    }
    $convFile = Join-Path $convDir "$sessionId.txt"

    # Read existing conversation
    $conversation = ""
    if (Test-Path $convFile) {
        $conversation = Get-Content $convFile -Raw
    }

    # If this is a fresh conversation and agent_md is provided, prepend system instructions
    if ([string]::IsNullOrWhiteSpace($conversation) -and -not [string]::IsNullOrWhiteSpace($agentMd)) {
        $conversation = "System: $agentMd`r`n`r`n"
    }

    # If long-term memory is provided, include it as context (once)
    if ($conversation -match "^System:" -and -not [string]::IsNullOrWhiteSpace($longTermMemory)) {
        $conversation += "Context: $longTermMemory`r`n`r`n"
    }

    # Append user message
    $conversation += "User: $message`r`n"

    # Send full conversation to claude
    $output = & claude "$conversation" 2>&1
    $responseText = $output | Out-String
    if ([string]::IsNullOrWhiteSpace($responseText)) {
        $responseText = "I processed your request."
    }
    $responseText = $responseText.Trim()

    # Append response to conversation and persist
    $conversation += "Assistant: $responseText`r`n"
    Set-Content -Path $convFile -Value $conversation -Encoding utf8

    Write-Output $responseText
} catch {
    Write-Output "Error processing request"
    exit 1
}
"#;

/// Initialize `~/.nebula/` with default config, data files, and wrapper scripts on first run.
fn init_nebula_dir() -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let nebula = config::nebula_dir();

    let files: Vec<(&str, &str, &str)> = vec![
        ("config.toml", "", DEFAULT_CONFIG_TOML),
        ("data/agent.md", "", DEFAULT_AGENT_MD),
        ("data/memory/long_term_memory.md", "", DEFAULT_MEMORY_MD),
        ("opencode-wrapper.ps1", "opencode-wrapper.ps1", OPENCODE_WRAPPER_PS1),
        ("claude-wrapper.ps1", "claude-wrapper.ps1", CLAUDE_WRAPPER_PS1),
    ];

    for (rel_path, _exec_name, content) in &files {
        let full_path = nebula.join(rel_path);
        if !full_path.exists() {
            if let Some(parent) = full_path.parent() {
                std::fs::create_dir_all(parent)?;
            }
            let mut content_str = content.to_string();
            // Replace placeholder with nebula dir path (use forward slashes for TOML)
            if *rel_path == "config.toml" {
                let path = nebula.to_string_lossy().replace("\\", "/");
                content_str = content_str.replace("WINDOWS_PLACEHOLDER", &path);
            }
            std::fs::write(&full_path, &content_str)?;
            info!("Created default: {}", full_path.display());
        }
    }

    // Ensure session history directory
    let session_dir = nebula.join("data/memory/chats");
    std::fs::create_dir_all(&session_dir)?;

    Ok(())
}

/// The main application entrypoint.
///
/// Sets up the subscriber for tracing, initializes `~/.nebula/` with defaults,
/// loads config, initializes the shared application state, runs the media stream
/// forwarding tasks, and serves the input and output routers concurrently.
#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "nebula_backend=info,tower_http=info".into()),
        )
        .init();

    // Initialize ~/.nebula/ with defaults (safe to call every run)
    init_nebula_dir()?;

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
