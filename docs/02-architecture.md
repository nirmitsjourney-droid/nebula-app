# Nebula Backend - Architecture

## Overview

Nebula is a Rust backend server that acts as a communication bridge between user inputs and a user-configured AI agent. It uses a dual-port architecture and supports a custom memory and session-history addon.

```
Client                     Input Server (3001)          Agent Process          Output Server (3002)         Client (subscriber)
  |                              |                          |                         |                          |
  |-- POST /input/text --------->|                          |                         |                          |
  |   {content: "hello"}         |                          |                         |                          |
  |                              |                          |                         |                          |
  |                              | 1. Create/reuse session  |                         |                          |
  |                              | 2. Build AgentMessage    |                         |                          |
  |                              | 3. Record in chat log    |                         |                          |
  |                              | 4. Forward to agent      |                         |                          |
  |                              |    (JSON via stdin)      |-- JSON payload -------->|                          |
  |                              |                          |<-- response line -------|                          |
  |                              | 5. Record response       |                         |                          |
  |                              | 6. Broadcast via WS      |                         |                          |
  |                              |                          |--- broadcast ---------->|-- WS stream ----------->|
  |<---- {session_id, response} -|                          |                         |                          |
```

## Directory Structure (User's machine)

```
~/.nebula/
├── config.toml                  # Server configuration
├── opencode-wrapper.ps1         # OpenCode bridge script
├── claude-wrapper.ps1           # Claude Code bridge script
├── data/
│   ├── agent.md                 # Agent persona (passed to AI)
│   └── memory/
│       ├── long_term_memory.md  # Persistent memory file
│       └── chats/               # Per-session chat logs
│           └── {session-id}/
│               ├── session.json # Session metadata
│               ├── chat.md      # Full chat transcript
│               ├── inputs/      # Raw input copies
│               ├── outputs/     # Raw output copies
│               └── assets/      # Uploaded files
```

## Communication Protocol

### Server → Agent (stdin)

```json
{
  "id": "uuid",
  "session_id": "uuid",
  "content_type": "text",
  "payload": "Hello, agent!",
  "timestamp": "2026-07-03T12:00:00Z",

  "agent_md": "# Agent Configuration\n\n...",
  "long_term_memory": "# Long-Term Memory\n\n..."
}
```

The `agent_md` and `long_term_memory` fields are only included when the addon is enabled.

### Agent → Server (stdout)

The agent must output a **single line** of text to stdout. This entire line becomes the response.

## API Endpoints

### Input Server (port 3001)

| Method | Route | Description |
|--------|-------|-------------|
| POST | `/input/text` | Send plain text |
| POST | `/input/html` | Send HTML snippet |
| POST | `/input/markdown` | Send Markdown content |
| POST | `/input/file` | Upload file (multipart) |
| GET | `/input/stream/video` | WebSocket for live video |
| GET | `/input/stream/audio` | WebSocket for live audio |
| GET | `/sessions` | List session summaries |
| POST | `/sessions/new` | Create new session |
| POST | `/addon/toggle` | Toggle addon on/off |
| GET | `/addon/status` | Get addon status |
| GET | `/health` | Health check |

### Output Server (port 3002)

| Method | Route | Description |
|--------|-------|-------------|
| GET | `/output/stream` | WebSocket for real-time responses |
| GET | `/output/stream/video` | WebSocket for video broadcast |
| GET | `/output/stream/audio` | WebSocket for audio broadcast |
| GET | `/output/session/{id}` | Get session detail + chat log |
| GET | `/output/sessions` | List all sessions |
| GET | `/output/memory` | Read long-term memory |
| GET | `/health` | Health check |

## How the Wrapper Works

The wrapper scripts bridge Nebula's JSON-over-stdin protocol to CLI-based AI agents:

1. Read JSON line from stdin
2. Extract the `payload` field (the user's message)
3. Call the AI agent CLI with the message
4. Parse the agent's output
5. Write the response as a single line to stdout

This allows Nebula to work with **any** CLI-based AI agent without modifying the backend.
