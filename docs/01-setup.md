# Nebula Backend - Setup Guide

## Prerequisites

- **Rust** (1.75+) — [rustup.rs](https://rustup.rs)
- **opencode** (optional) — `npm install -g opencode-ai`
- **Claude Code** (optional) — install via your preferred method
- An AI provider configured for your chosen agent

---

## Quick Start (Binary)

1. **Download or build the binary:**

   ```bash
   cd Backend
   cargo build --release
   ```

   The binary is at `Backend/target/release/nebula-backend.exe`.

2. **Run it — that's it:**

   ```bash
   ./nebula-backend.exe
   ```

   On first run, the binary automatically creates `~/.Nebula/` with:
   - `config.toml` — server configuration
   - `opencode-wrapper.ps1` — bridge script for OpenCode
   - `claude-wrapper.ps1` — bridge script for Claude Code
   - `data/agent.md` — agent persona instructions
   - `data/memory/long_term_memory.md` — persistent memory
   - `data/memory/chats/` — session history storage
   - `data/conversations/` — per-session AI agent conversation files (managed by wrapper)

   No manual file creation needed.

3. **Verify it's running:**

   ```bash
   curl http://localhost:3001/health
   curl http://localhost:3002/health
   ```

---

## Configuration

All configuration lives in `~/.Nebula/config.toml`. Edit it to customize:

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

### Key settings

| Setting | Default | Description |
|---------|---------|-------------|
| `input_port` | `3001` | Port for submitting text/files/streams |
| `output_port` | `3002` | Port for receiving streaming responses |
| `agent.command` | `powershell` | Command to launch your AI agent |
| `agent.args` | wrapper path | Arguments for the agent command |
| `agent.mode` | `stdio` | `stdio` or `http` communication mode |
| `addon.enabled` | `true` | Enable/disable memory and session history |

---

## Choosing an AI Agent

### Option A: OpenCode (recommended)

The default `config.toml` points to `opencode-wrapper.ps1`. Make sure `opencode` is installed and configured:

```bash
opencode providers list     # Check configured providers
opencode models             # List available models
opencode run "hello"        # Verify it works
```

### Option B: Claude Code

Edit `~/.Nebula/config.toml` to use the Claude wrapper:

```toml
[agent]
command = "powershell"
args = ["-File", "C:\\Users\\You\\.Nebula\\claude-wrapper.ps1"]
mode = "stdio"
```

Make sure `claude` is available on your PATH.

### Option C: Any custom agent

Write your own wrapper script (see the [Custom Wrappers guide](./03-custom-wrappers.md)), place it in `~/.nebula/`, and point `config.toml` at it.

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
