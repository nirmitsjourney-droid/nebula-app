# Nebula Backend — Documentation

A Rust backend server that bridges user inputs with AI agents (OpenCode, Claude, etc.) using a dual-port architecture.

## Guides

| Guide | Description |
|-------|-------------|
| [01-setup.md](./01-setup.md) | Installation, configuration, and quick start |
| [02-architecture.md](./02-architecture.md) | System architecture, protocol, and API reference |
| [03-custom-wrappers.md](./03-custom-wrappers.md) | How to write wrapper scripts for any AI agent |

## Quick Links

- **Binary**: `target/release/nebula-backend.exe`
- **Config**: `~/.Nebula/config.toml` (auto-created on first run)
- **Wrappers**: `~/.Nebula/opencode-wrapper.ps1` and `~/.Nebula/claude-wrapper.ps1`
- **Data**: `~/.Nebula/data/` (agent.md, long-term memory, session history, conversation files)

## Source Layout

```
src/
├── lib.rs      # Library root, re-exports all modules
├── main.rs     # Entrypoint, auto-init, server bootstrap
├── config.rs   # Config loading (~/.Nebula/config.toml, CWD fallback)
├── state.rs    # Shared AppState, AgentMessage, ContentType enum
├── session.rs  # Session manager with disk-persisted chat logs
├── addon.rs    # Long-term memory & agent.md management
├── agent.rs    # Agent communication (stdio/http) + media forwarders
├── input.rs    # Input server routes (port 3001)
├── output.rs   # Output server routes (port 3002)
└── media.rs    # WebSocket video/audio stream handlers
```

## Building from Source

```bash
cargo build --release
```
