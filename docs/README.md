# Nebula Backend - Documentation

A Rust backend server that bridges user inputs with AI agents (OpenCode, Claude, etc.).

## Guides

| Guide | Description |
|-------|-------------|
| [01-setup.md](./01-setup.md) | Installation, configuration, and quick start |
| [02-architecture.md](./02-architecture.md) | System architecture, protocol, and API reference |
| [03-custom-wrappers.md](./03-custom-wrappers.md) | How to write wrapper scripts for any AI agent |

## Quick Links

- **Binary**: `Backend/target/release/nebula-backend.exe`
- **Config**: `~/.Nebula/config.toml` (auto-created on first run)
- **Wrappers**: `~/.Nebula/opencode-wrapper.ps1` and `~/.Nebula/claude-wrapper.ps1`
- **Data**: `~/.Nebula/data/` (agent.md, long-term memory, session history, conversation files)

## Source Code

```
Backend/
├── src/
│   ├── main.rs      # Entrypoint + auto-init of ~/.Nebula/
│   ├── config.rs    # Config loading from ~/.Nebula/
│   ├── state.rs     # Shared AppState & AgentMessage
│   ├── addon.rs     # Memory & session addon
│   ├── session.rs   # Session manager & chat log
│   ├── agent.rs     # Agent communication (stdio/http)
│   ├── input.rs     # Input server routes
│   ├── output.rs    # Output server routes
│   └── media.rs     # Video/audio streaming
└── Cargo.toml
```

## Building from Source

```bash
cd Backend
cargo build --release
```
