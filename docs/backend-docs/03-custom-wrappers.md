# Nebula Backend — Custom Wrapper Scripts

## Overview

Wrapper scripts translate between Nebula's JSON-over-stdin protocol and your AI agent's CLI interface. The backend sends only the **current single message** (never session history). Wrappers are responsible for maintaining conversation continuity by persisting per-session conversation files locally.

## The Protocol

Nebula sends one JSON line to the wrapper's **stdin**:

```json
{
  "id": "msg-uuid",
  "session_id": "session-uuid",
  "content_type": "text",
  "payload": "User's message here",
  "timestamp": "2026-07-03T12:00:00Z",
  "agent_md": "# Agent Configuration\n\n...",
  "long_term_memory": "# Long-Term Memory\n\n..."
}
```

The wrapper must output **one line of text** to **stdout** — this becomes the AI response. `session_id` is required for conversation continuity.

The `content_type` field indicates the input type (`text`, `html`, `markdown`, `file`, `audio_stream`, `video_stream`, `image`). For file uploads, a `file_path` and `metadata` object are also provided.

## Conversation Continuity Contract

Every wrapper **must**:

1. Read the JSON payload from stdin (single message, no history from backend)
2. Extract `session_id` and `payload`
3. Maintain a per-session conversation file at `~/.Nebula/data/conversations/{session_id}.txt`
4. Load the existing conversation from that file (if any)
5. If this is a new conversation and `agent_md` is provided, prepend it as system instructions
6. If this is a new conversation and `long_term_memory` is provided, include it as context
7. Append the new user message as `User: {payload}`
8. Send the **full conversation** to the underlying AI CLI
9. Append the AI's response as `Assistant: {response}`
10. Save the conversation file
11. Output only the new response text to stdout

## Default Wrappers

### OpenCode Wrapper (`~/.Nebula/opencode-wrapper.ps1`)

```powershell
param()
try {
    $inputJson = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($inputJson)) { exit 1 }
    $parsed = $inputJson | ConvertFrom-Json
    $sessionId = $parsed.session_id
    $message = $parsed.payload
    $agentMd = $parsed.agent_md
    $longTermMemory = $parsed.long_term_memory
    if ([string]::IsNullOrWhiteSpace($message)) { $message = "" }

    $nebulaDir = Split-Path -Parent $PSCommandPath
    $convDir = Join-Path $nebulaDir "data\conversations"
    if (-not (Test-Path $convDir)) { New-Item -ItemType Directory -Path $convDir -Force | Out-Null }
    $convFile = Join-Path $convDir "$sessionId.txt"

    $conversation = ""
    if (Test-Path $convFile) { $conversation = Get-Content $convFile -Raw }
    if ([string]::IsNullOrWhiteSpace($conversation) -and -not [string]::IsNullOrWhiteSpace($agentMd)) {
        $conversation = "System: $agentMd`r`n`r`n"
    }
    if ($conversation -match "^System:" -and -not [string]::IsNullOrWhiteSpace($longTermMemory)) {
        $conversation += "Context: $longTermMemory`r`n`r`n"
    }

    $conversation += "User: $message`r`n"
    $output = & opencode run --format json $conversation 2>&1
    $responseText = ""
    foreach ($line in $output) {
        $lineStr = "$line"
        if ([string]::IsNullOrWhiteSpace($lineStr)) { continue }
        try {
            $event = $lineStr | ConvertFrom-Json
            if ($event.type -eq "text" -and $event.part.text) { $responseText += $event.part.text }
        } catch {}
    }
    if ([string]::IsNullOrWhiteSpace($responseText)) { $responseText = "I processed your request." }

    $conversation += "Assistant: $responseText`r`n"
    Set-Content -Path $convFile -Value $conversation -Encoding utf8
    Write-Output $responseText
} catch { Write-Output "Error processing request"; exit 1 }
```

### Claude Code Wrapper (`~/.Nebula/claude-wrapper.ps1`)

```powershell
param()
try {
    $inputJson = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($inputJson)) { exit 1 }
    $parsed = $inputJson | ConvertFrom-Json
    $sessionId = $parsed.session_id
    $message = $parsed.payload
    $agentMd = $parsed.agent_md
    $longTermMemory = $parsed.long_term_memory
    if ([string]::IsNullOrWhiteSpace($message)) { $message = "" }

    $nebulaDir = Split-Path -Parent $PSCommandPath
    $convDir = Join-Path $nebulaDir "data\conversations"
    if (-not (Test-Path $convDir)) { New-Item -ItemType Directory -Path $convDir -Force | Out-Null }
    $convFile = Join-Path $convDir "$sessionId.txt"

    $conversation = ""
    if (Test-Path $convFile) { $conversation = Get-Content $convFile -Raw }
    if ([string]::IsNullOrWhiteSpace($conversation) -and -not [string]::IsNullOrWhiteSpace($agentMd)) {
        $conversation = "System: $agentMd`r`n`r`n"
    }
    if ($conversation -match "^System:" -and -not [string]::IsNullOrWhiteSpace($longTermMemory)) {
        $conversation += "Context: $longTermMemory`r`n`r`n"
    }

    $conversation += "User: $message`r`n"
    $output = & claude "$conversation" 2>&1
    $responseText = $output | Out-String
    if ([string]::IsNullOrWhiteSpace($responseText)) { $responseText = "I processed your request." }
    $responseText = $responseText.Trim()

    $conversation += "Assistant: $responseText`r`n"
    Set-Content -Path $convFile -Value $conversation -Encoding utf8
    Write-Output $responseText
} catch { Write-Output "Error processing request"; exit 1 }
```

## Writing Custom Wrappers

### Basic Structure (Python)

```python
#!/usr/bin/env python3
import sys, json, subprocess, os

line = sys.stdin.read()
data = json.loads(line)
session_id = data["session_id"]
message = data["payload"]
agent_md = data.get("agent_md", "")
long_term_memory = data.get("long_term_memory", "")

nebula_dir = os.path.dirname(os.path.abspath(__file__))
conv_dir = os.path.join(nebula_dir, "data", "conversations")
os.makedirs(conv_dir, exist_ok=True)
conv_file = os.path.join(conv_dir, f"{session_id}.txt")

conversation = ""
if os.path.exists(conv_file):
    with open(conv_file, "r") as f:
        conversation = f.read()

if not conversation and agent_md:
    conversation = f"System: {agent_md}\n\n"
if not conversation and long_term_memory:
    conversation = f"System: {agent_md}\n\nContext: {long_term_memory}\n\n"

conversation += f"User: {message}\n"

result = subprocess.run(
    ["your-agent-cli"],
    input=conversation,
    capture_output=True, text=True
)
response = result.stdout.strip()

conversation += f"Assistant: {response}\n"
with open(conv_file, "w") as f:
    f.write(conversation)

print(response)
```

### Basic Structure (Bash)

```bash
#!/usr/bin/env bash
set -e
read -r line
session_id=$(echo "$line" | python3 -c "import sys,json; print(json.load(sys.stdin)['session_id'])")
message=$(echo "$line" | python3 -c "import sys,json; print(json.load(sys.stdin)['payload'])")
agent_md=$(echo "$line" | python3 -c "import sys,json; print(json.load(sys.stdin).get('agent_md',''))")
ltm=$(echo "$line" | python3 -c "import sys,json; print(json.load(sys.stdin).get('long_term_memory',''))")

nebula_dir="$(dirname "$(readlink -f "$0")")"
conv_dir="$nebula_dir/data/conversations"
mkdir -p "$conv_dir"
conv_file="$conv_dir/$session_id.txt"

conversation=""
[ -f "$conv_file" ] && conversation=$(cat "$conv_file")
[ -z "$conversation" ] && [ -n "$agent_md" ] && conversation="System: $agent_md\n\n"
[ -z "$conversation" ] && [ -n "$ltm" ] && conversation="$conversation\nContext: $ltm\n\n"

conversation="$conversation\nUser: $message\n"
response=$(your-cli "$conversation")

conversation="$conversation\nAssistant: $response\n"
echo "$conversation" > "$conv_file"
echo "$response"
```

## Installing a Custom Wrapper

1. Place your wrapper in `~/.Nebula/` (e.g., `~/.Nebula/my-wrapper.ps1`)
2. Update `~/.Nebula/config.toml`:

```toml
[agent]
command = "powershell"
args = ["-File", "C:\\Users\\You\\.Nebula\\my-wrapper.ps1"]
mode = "stdio"
```

3. Restart the Nebula server.

## Testing a Wrapper

Test your wrapper independently before connecting it to Nebula:

```powershell
# Simulate what Nebula sends
'{"session_id":"test-123","payload":"Say hello in one word"}' | powershell -File ~/.Nebula/my-wrapper.ps1
```

Expected output should be a single line with the agent's response.

## Error Handling

- If the wrapper exits with a non-zero code, Nebula logs the error but continues running
- If the wrapper outputs nothing, Nebula treats the response as empty
- If the wrapper outputs multiple lines, Nebula only reads the first line
- If the wrapper outputs an error message, it is recorded as-is in the session log
- If a session is deleted via the API, the backend removes both the session folder and its conversation file
