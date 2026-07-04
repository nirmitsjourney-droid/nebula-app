# Nebula Backend - Architecture

## Overview

Nebula is a Rust backend server that acts as a communication bridge between user inputs and a user-configured AI agent. It uses a dual-port architecture and supports a custom memory and session-history addon.

The backend **never sends session history** to the AI agent. Instead, wrapper scripts maintain per-session conversation files locally, ensuring conversational continuity while keeping the backend stateless.

```
Client                     Input Server (3001)          Agent (Wrapper)        Output Server (3002)         Client (subscriber)
  |                              |                          |                         |                          |
  |-- POST /input/text --------->|                          |                         |                          |
  |   {content: "hello"}         |                          |                         |                          |
  |                              |                          |                         |                          |
  |                              | 1. Create/reuse session  |                         |                          |
  |                              | 2. Build AgentMessage    |                         |                          |
  |                              | 3. Record in chat log    |                         |                          |
  |                              | 4. Forward to wrapper    |                         |                          |
  |                              |    (JSON via stdin)      |-- JSON payload -------->|                          |
  |                              |   (single message only,  |   {session_id, payload}  |                          |
  |                              |    no history)           |                         |                          |
  |                              |                          | 5. Append user msg to   |                          |
  |                              |                          |    conversation file    |                          |
  |                              |                          | 6. Send full history    |                          |
  |                              |                          |    to AI CLI            |                          |
  |                              |                          | 7. Append AI response   |                          |
  |                              |                          |    to conversation file |                          |
  |                              |                          |<-- response line -------|                          |
  |                              | 8. Record response       |                         |                          |
  |                              | 9. Broadcast via WS      |                         |                          |
  |                              |                          |--- broadcast ---------->|-- WS stream ----------->|
  |<---- {session_id, response} -|                          |                         |                          |
```

## Directory Structure (User's machine)

```
~/.Nebula/
├── config.toml                  # Server configuration
├── opencode-wrapper.ps1         # OpenCode bridge script
├── claude-wrapper.ps1           # Claude Code bridge script
├── data/
│   ├── agent.md                 # Agent persona (passed to wrapper)
│   ├── conversations/           # Per-session AI conversation state (managed by wrapper)
│   │   └── {session-id}.txt     # Full conversation for a session
│   └── memory/
│       ├── long_term_memory.md  # Persistent memory file
│       └── chats/               # Per-session chat logs (managed by backend)
│           └── {session-id}/
│               ├── session.json # Session metadata
│               ├── chat.md      # Full chat transcript
│               ├── inputs/      # Raw input copies
│               ├── outputs/     # Raw output copies
│               └── assets/      # Uploaded files
```

## Communication Protocol

### Server → Wrapper (stdin)

The backend sends only the current single message — **never** the session history:

```json
{
  "id": "msg-uuid",
  "session_id": "session-uuid",
  "content_type": "text",
  "payload": "Hello, agent!",
  "timestamp": "2026-07-03T12:00:00Z",

  "agent_md": "# Agent Configuration\n\n...",
  "long_term_memory": "# Long-Term Memory\n\n..."
}
```

The `agent_md` and `long_term_memory` fields are only included when the addon is enabled.

### Wrapper → Server (stdout)

The wrapper must output a **single line** of text to stdout. This is the AI's new response only.

### How the Wrapper Maintains Conversation Continuity

1. Reads the JSON payload from stdin
2. Extracts `session_id` and `payload` (the new user message)
3. Loads or creates the conversation file at `~/.Nebula/data/conversations/{session_id}.txt`
4. If this is the first message and `agent_md` is provided, prepends it as system instructions
5. Appends the user's message (`User: ...`)
6. Sends the **entire conversation** to the underlying AI CLI (opencode, claude, etc.)
7. Appends the AI's response (`Assistant: ...`) to the conversation file
8. Outputs only the new response text to stdout

This ensures each message continues the same conversation without the backend needing to send history.

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
| DELETE | `/sessions/{id}` | Delete session folder + wrapper conversation file |
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

1. Read JSON from stdin (single message, no history)
2. Load per-session conversation file from `~/.Nebula/data/conversations/{session_id}.txt`
3. Append the new user message to the conversation
4. Call the AI agent CLI with the **full conversation** as input
5. Append the AI response to the conversation file
6. Write only the new response as a single line to stdout

This allows Nebula to work with **any** CLI-based AI agent while maintaining conversation continuity across messages.
