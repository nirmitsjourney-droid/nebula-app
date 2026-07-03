# Nebula Backend Server

A production-ready Rust backend server designed to act as a communication bridge between user inputs and a user-configured AI agent. The server uses a dual-port architecture and supports a custom memory and session-history addon.

## Architecture & Flow

The server listens on one configurable port (input port) for client requests and broadcasts responses/logs on a second configurable port (output port).

```mermaid
graph TD
    Client[Client App] -->|Sends text, files, audio/video stream| InputServer[Input Server (Port 3001)]
    InputServer -->|Logs & Session Files| Addon[Addon / Session History]
    InputServer -->|Forwards paired payload + agent.md| Agent[AI Agent (OpenClaw, Hermes, OpenCode, etc.)]
    Agent -->|Returns AI response| InputServer
    InputServer -->|Broadcasts response| State[App State]
    State -->|Broadcasts response| OutputServer[Output Server (Port 3002)]
    OutputServer -->|WebSocket stream / SSE| Client
```

---

## Folder Structure

```
backend/
├── Cargo.toml                  # Cargo dependencies
├── config.toml                  # Configurable server and agent settings
├── data/
│   ├── agent.md                # System instructions/persona passed to the agent
│   ├── memory/
│   │   └── long_term_memory.md # Persistent markdown memory file
│   └── session-history/        # Session histories folder
│       └── [session-id]/       # Subfolder per chat session
│           ├── session.json    # Metadata (created, last active, message count)
│           ├── chat.md         # Full chat transcript in Markdown
│           ├── inputs/         # Copies of raw inputs received
│           ├── outputs/        # Copies of raw responses sent
│           └── assets/         # Uploaded files and media
└── src/
    ├── main.rs                 # Server entrypoint & runner
    ├── config.rs               # config.toml loader
    ├── state.rs                # Shared AppState & broadcast channels
    ├── addon.rs                # Long-term memory & core addon logic
    ├── session.rs              # Session manager & filesystem recorder
    ├── agent.rs                # Agent runner (stdio and HTTP modes)
    ├── input.rs                # Input port routes (text, file uploads, media streams)
    ├── output.rs               # Output port routes (SSE, WebSocket response stream)
    └── media.rs                # Audio/Video WebSocket stream broadcaster
```

---

## Configuration

The server configuration resides in [config.toml](file:///C:/Users/NirmitPatel/Desktop/Projects/nebula-app/backend/config.toml).

### Main Settings

- **`input_port`**: `[FILL: input port]` (e.g., `3001`) — Port where clients submit text/files/streams.
- **`output_port`**: `[FILL: output port]` (e.g., `3002`) — Port where clients listen for streaming responses.

### Custom Addon Toggles

- **`addon.enabled`**: Set to `true` or `false` to enable or disable the custom addon (long-term memory, session subfolders, and agent.md context).
- **`addon.memory_file`**: Path to the long-term markdown memory file.
- **`addon.session_history_dir`**: Folder where per-session directories are created.
- **`addon.agent_md_path`**: Path to the markdown file defining the agent persona.

### Agent Setup

Nebula works with any backend agent (e.g., OpenClaw, Hermes, OpenCode, etc.) without requiring setup on the agent's side.

- **`agent.command`**: The executable command for the agent (e.g., `openclaw`, `opencode`, `hermes`, `python`).
- **`agent.args`**: Arguments array to pass to the command (e.g. `["--verbose", "--model", "custom"]`).
- **`agent.mode`**: `"stdio"` (spawns child process, communicates via stdin/stdout) or `"http"` (submits HTTP POST requests).
- **`agent.endpoint_url`**: The URL if `agent.mode` is set to `"http"`.

---

## Getting Started

### Prerequisites

Ensure you have Rust and Cargo installed:
```bash
rustc --version
cargo --version
```

### Installation & Running

1. Open a terminal in the `backend` folder.
2. Edit [config.toml](file:///C:/Users/NirmitPatel/Desktop/Projects/nebula-app/backend/config.toml) to configure ports and the command to invoke your AI agent.
3. Run the server:
   ```bash
   cargo run
   ```

---

## API Documentation

### 1. Input Server (Port `3001` by default)

- **`POST /input/text`**
  - Content-Type: `application/json`
  - Body:
    ```json
    {
      "session_id": "optional-uuid-here",
      "content": "Hello, agent!",
      "metadata": {}
    }
    ```
- **`POST /input/html`**
  - Content-Type: `application/json`
  - Body:
    ```json
    {
      "session_id": "optional-uuid-here",
      "content": "<div>Hello World</div>"
    }
    ```
- **`POST /input/markdown`**
  - Content-Type: `application/json`
  - Body:
    ```json
    {
      "session_id": "optional-uuid-here",
      "content": "# Markdown title"
    }
    ```
- **`POST /input/file`**
  - Multipart form upload.
  - Fields:
    - `session_id`: (optional)
    - `file`: The file binary (supports any type).
- **`GET /input/stream/video`** (WebSocket)
  - Connect to stream binary video frames in real-time.
- **`GET /input/stream/audio`** (WebSocket)
  - Connect to stream binary audio frames in real-time.
- **`POST /addon/toggle`**
  - Dynamically toggle the addon on or off.
- **`GET /addon/status`**
  - Retrieve current status (enabled/disabled) and configuration paths.

### 2. Output Server (Port `3002` by default)

- **`GET /output/stream`** (WebSocket)
  - Connect to receive real-time JSON responses from the agent.
- **`GET /output/stream/video`** (WebSocket)
  - Forwards the active video stream broadcast to subscribers.
- **`GET /output/stream/audio`** (WebSocket)
  - Forwards the active audio stream broadcast to subscribers.
- **`GET /output/session/{id}`**
  - Retrieves a summary of the session: metadata, full chat log, and a list of asset filenames.
- **`GET /output/sessions`**
  - Returns a list of all session metadata on the server.
- **`GET /output/memory`**
  - Reads the current contents of the long-term memory markdown file.
