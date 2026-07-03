# Nebula Backend Server

A Rust backend server that bridges user inputs with AI agents (OpenCode, Claude, etc.) using a dual-port architecture with memory and session-history addon.

## Quick Start

```bash
cargo run --release
```

On first run, `~/.nebula/` is auto-created with default config, wrapper scripts, and data files.

See [docs/](../docs/) for full setup and architecture documentation.

## Source Layout

```
src/
├── main.rs     # Entrypoint + auto-init of ~/.nebula/
├── config.rs   # Config loading (~/.nebula/config.toml, then CWD fallback)
├── state.rs    # Shared AppState & AgentMessage
├── addon.rs    # Memory & session addon
├── session.rs  # Session manager & chat log
├── agent.rs    # Agent communication (stdio / http)
├── input.rs    # Input server routes
├── output.rs   # Output server routes
└── media.rs    # Video/audio streaming
```

## Runtime Files (auto-created in `~/.nebula/`)

| File | Purpose |
|------|---------|
| `config.toml` | Server and agent configuration |
| `opencode-wrapper.ps1` | Bridge script for OpenCode |
| `claude-wrapper.ps1` | Bridge script for Claude Code |
| `data/agent.md` | Agent persona instructions |
| `data/memory/long_term_memory.md` | Persistent memory |
| `data/memory/chats/` | Per-session chat logs |

## Building

```bash
cargo build --release
# Binary: target/release/nebula-backend.exe
```
