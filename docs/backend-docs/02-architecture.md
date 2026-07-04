# Nebula Backend — Architecture

## Overview

Nebula is a Rust backend server that acts as a communication bridge between user inputs and a user-configured AI agent. It uses a **dual-port architecture** with an optional memory and session-history addon.

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
  |                              |    no history)           |   + agent_md, memory}   |                          |
  |                              |                          |                         |                          |
  |                              |                          | 5. Append user msg to   |                          |
  |                              |                          |    conversation file    |                          |
  |                              |                          | 6. Send full history    |                          |
  |                              |                          |    to AI CLI            |                          |
  |                              |                          | 7. Append AI response   |                          |
  |                              |                          |    to conversation file |                          |
  |                              |                          |<-- response line -------|                          |
  |                              | 8. Record response       |                         |                          |
  |                              |    in chat log           |                         |                          |
  |                              | 9. Broadcast via WS      |                         |                          |
  |                              |                          |--- broadcast ---------->|-- WS stream ----------->|
  |<---- {session_id, response} -|                          |                         |                          |
```

## Directory Structure

```
~/.Nebula/
├── config.toml                  # Server configuration
├── opencode-wrapper.ps1         # OpenCode bridge script
├── claude-wrapper.ps1           # Claude Code bridge script
├── data/
│   ├── agent.md                 # Agent persona (passed to wrapper as metadata)
│   ├── conversations/           # Per-session AI conversation state (managed by wrapper)
│   │   └── {session-id}.txt     # Full conversation for a session
│   └── memory/
│       ├── long_term_memory.md  # Persistent cross-session memory file
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

The backend sends only the **current single message** — never the session history. If the addon is enabled, it also injects `agent.md` and `long_term_memory.md` contents as metadata.

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

The `content_type` field can be: `text`, `html`, `markdown`, `file`, `audio_stream`, `video_stream`, or `image`. For file uploads, a `file_path` and `metadata` field are also included.

### Wrapper → Server (stdout)

The wrapper must output a **single line** of text to stdout. This is the AI's new response only. Any stderr output is captured and logged but ignored.

### How the Wrapper Maintains Conversation Continuity

1. Reads the JSON payload from stdin
2. Extracts `session_id` and `payload` (the new user message)
3. Loads or creates the conversation file at `~/.Nebula/data/conversations/{session_id}.txt`
4. If this is the first message and `agent_md` is provided, prepends it as system instructions
5. If `long_term_memory` is provided on the first message, includes it as context
6. Appends the user's message (`User: ...`)
7. Sends the **entire conversation** to the underlying AI CLI
8. Appends the AI's response (`Assistant: ...`) to the conversation file
9. Outputs only the new response text to stdout

## API Reference

### Input Server (port 3001)

| Method | Route | Description |
|--------|-------|-------------|
| POST | `/input/text` | Send plain text |
| POST | `/input/html` | Send HTML snippet |
| POST | `/input/markdown` | Send Markdown content |
| POST | `/input/file` | Upload file (multipart) |
| GET | `/input/stream/video` | WebSocket for live video input |
| GET | `/input/stream/audio` | WebSocket for live audio input |
| GET | `/sessions` | List all sessions |
| POST | `/sessions/new` | Create a new session |
| DELETE | `/sessions/{id}` | Delete session folder + wrapper conversation file |
| POST | `/addon/toggle` | Toggle addon on/off |
| GET | `/addon/status` | Get addon status and configured paths |
| GET | `/health` | Health check |

### Output Server (port 3002)

| Method | Route | Description |
|--------|-------|-------------|
| GET | `/output/stream` | WebSocket for real-time response stream |
| GET | `/output/stream/video` | WebSocket for video broadcast |
| GET | `/output/stream/audio` | WebSocket for audio broadcast |
| GET | `/output/session/{id}` | Get session detail, chat log, and assets |
| GET | `/output/sessions` | List all sessions |
| GET | `/output/memory` | Read long-term memory file |
| GET | `/health` | Health check |

## Agent Communication Modes

### stdio Mode (default)

The backend spawns the agent command as a child process, writes the JSON payload to its stdin, and reads the first line of stdout as the response. This is the primary mode used for wrapper scripts.

### HTTP Mode

The backend sends the JSON payload as an HTTP POST request to the configured `endpoint_url`. This allows integration with remote agent services or HTTP-based AI runners.

## Media Streaming

Live audio and video streams flow through WebSocket connections:

1. A client connects to `/input/stream/video` (or `/input/stream/audio`) on the input server
2. Binary frames are broadcast internally via Tokio broadcast channels
3. Background tasks in the agent module receive these frames, base64-encode them, and forward them to the AI agent as JSON payloads with `type: "video_frame"` / `type: "audio_frame"`
4. Other clients can subscribe to the output via `/output/stream/video` or `/output/stream/audio` on the output server
