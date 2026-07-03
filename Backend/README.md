# Nebula Backend Server

A Rust backend server that bridges user inputs with AI agents (OpenCode, Claude, etc.) using a dual-port architecture with memory and session-history addon.

The backend **never sends session history** to the AI agent. Wrapper scripts maintain per-session conversation files locally for conversational continuity.

## Quick Start

```bash
cargo run --release
```

On first run, `~/.Nebula/` is auto-created with default config, wrapper scripts, and data files.

See [docs/](../docs/) for full setup and architecture documentation.

## Source Layout

```
src/
├── main.rs     # Entrypoint + auto-init of ~/.Nebula/
├── config.rs   # Config loading (~/.Nebula/config.toml, then CWD fallback)
├── state.rs    # Shared AppState & AgentMessage
├── addon.rs    # Memory & session addon
├── session.rs  # Session manager & chat log
├── agent.rs    # Agent communication (stdio / http)
├── input.rs    # Input server routes
├── output.rs   # Output server routes
└── media.rs    # Video/audio streaming
```

## Runtime Files (auto-created in `~/.Nebula/`)

| File | Purpose |
|------|---------|
| `config.toml` | Server and agent configuration |
| `opencode-wrapper.ps1` | Bridge script for OpenCode |
| `claude-wrapper.ps1` | Bridge script for Claude Code |
| `data/agent.md` | Agent persona instructions |
| `data/memory/long_term_memory.md` | Persistent memory |
| `data/memory/chats/` | Per-session chat logs (managed by backend) |
| `data/conversations/` | Per-session AI conversation state (managed by wrapper) |

## Building

```bash
cargo build --release
# Binary: target/release/nebula-backend.exe
```
