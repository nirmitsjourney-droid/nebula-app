# Nebula Backend — Setup Guide

## Prerequisites

- **Rust 1.75+** — [rustup.rs](https://rustup.rs)
- **OpenCode** (optional) — `npm install -g opencode-ai`
- **Claude Code** (optional) — install via your preferred method
- An AI provider configured for your chosen agent

---

## Quick Start

1. **Build the binary:**

   ```bash
   cargo build --release
   ```

   The binary is at `target/release/nebula-backend.exe`.

2. **Run it:**

   ```bash
   ./target/release/nebula-backend.exe
   ```

   On first run, the binary automatically creates `~/.Nebula/` with:
   - `config.toml` — server configuration
   - `opencode-wrapper.ps1` — bridge script for OpenCode
   - `claude-wrapper.ps1` — bridge script for Claude Code
   - `data/agent.md` — agent persona instructions
   - `data/memory/long_term_memory.md` — persistent cross-session memory
   - `data/memory/chats/` — session history storage
   - `data/conversations/` — per-session AI conversation files (managed by wrapper)

   No manual file creation needed.

3. **Verify it's running:**

   ```bash
   curl http://localhost:3001/health
   curl http://localhost:3002/health
   ```

---

## Configuration

All configuration lives in `~/.Nebula/config.toml`:

```toml
input_port = 3001
output_port = 3002

[addon]
enabled = true

[agent]
command = "powershell"
args = ["-File", "C:\\Users\\You\\.Nebula\\opencode-wrapper.ps1"]
mode = "stdio"
```

### Configuration Reference

| Key | Default | Description |
|-----|---------|-------------|
| `input_port` | `3001` | Port for the input server (text, files, streams) |
| `output_port` | `3002` | Port for the output server (responses, broadcasts) |
| `addon.enabled` | `true` | Enable/disable memory and session history addon |
| `addon.memory_file` | `~/.Nebula/data/memory/long_term_memory.md` | Path to long-term memory file |
| `addon.session_history_dir` | `~/.Nebula/data/memory/chats` | Path to session history directory |
| `addon.agent_md_path` | `~/.Nebula/data/agent.md` | Path to agent persona markdown |
| `agent.command` | `echo` | Command to launch the AI agent (e.g. `powershell`, `opencode`, `python`) |
| `agent.args` | `[]` | Arguments passed to the agent command |
| `agent.mode` | `stdio` | Communication mode: `stdio` (stdin/stdout) or `http` (HTTP POST) |
| `agent.endpoint_url` | `http://localhost:8080` | Base URL for HTTP mode |

The config file is optional. If missing, defaults are used and a warning is logged. The server also checks the current working directory for `config.toml` as a fallback.

---

## Choosing an AI Agent

### OpenCode (recommended)

The default `config.toml` points to `opencode-wrapper.ps1`. Make sure OpenCode is installed and configured:

```bash
opencode providers list     # Check configured providers
opcode models               # List available models
opencode run "hello"        # Verify it works
```

### Claude Code

Edit `~/.Nebula/config.toml` to use the Claude wrapper:

```toml
[agent]
command = "powershell"
args = ["-File", "C:\\Users\\You\\.Nebula\\claude-wrapper.ps1"]
mode = "stdio"
```

Make sure `claude` is available on your PATH.

### Custom Agent

Write your own wrapper script (see the [Custom Wrappers guide](./03-custom-wrappers.md)), place it in `~/.Nebula/`, and point `config.toml` at it.

---

## Testing the Setup

```bash
# 1. Health check
curl http://localhost:3001/health

# 2. Send a text message
curl -X POST http://localhost:3001/input/text \
  -H "Content-Type: application/json" \
  -d '{"content": "Hello, what can you do?"}'

# 3. Check session history
curl http://localhost:3002/output/sessions
```
