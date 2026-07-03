# Nebula Backend - Custom Wrapper Scripts

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

The wrapper must output **one line of text** to **stdout** — this becomes the AI response.

`session_id` is required for conversation continuity. The wrapper should use it to maintain a per-session conversation file.

## Conversation Continuity Contract

Every wrapper **must**:

1. Read the JSON payload from stdin (single message, no history from backend)
2. Extract `session_id` and `payload`
3. Maintain a per-session conversation file at `~/.Nebula/data/conversations/{session_id}.txt`
4. Load the existing conversation from that file (if any)
5. If this is a new conversation and `agent_md` is provided, prepend it as system instructions
6. Append the new user message as `User: {payload}`
7. Send the **full conversation** to the underlying AI CLI
8. Append the AI's response as `Assistant: {response}`
9. Save the conversation file
10. Output only the new response text to stdout

## Writing a Wrapper

### Basic Structure (Any Language)

```python
#!/usr/bin/env python3
import sys, json, subprocess, os

# 1. Read JSON from stdin
line = sys.stdin.read()
data = json.loads(line)
session_id = data["session_id"]
message = data["payload"]
agent_md = data.get("agent_md", "")

# 2. Determine conversation file path
nebula_dir = os.path.dirname(os.path.abspath(__file__))
conv_dir = os.path.join(nebula_dir, "data", "conversations")
os.makedirs(conv_dir, exist_ok=True)
conv_file = os.path.join(conv_dir, f"{session_id}.txt")

# 3. Load existing conversation
conversation = ""
if os.path.exists(conv_file):
    with open(conv_file, "r") as f:
        conversation = f.read()

# 4. If new conversation, prepend agent instructions
if not conversation and agent_md:
    conversation = f"System: {agent_md}\n\n"

# 5. Append user message
conversation += f"User: {message}\n"

# 6. Send full conversation to the AI CLI
result = subprocess.run(
    ["your-agent-cli"],
    input=conversation,
    capture_output=True, text=True
)
response = result.stdout.strip()

# 7. Append response and persist
conversation += f"Assistant: {response}\n"
with open(conv_file, "w") as f:
    f.write(conversation)

# 8. Output only the new response
print(response)
```

### PowerShell (Windows) — OpenCode

This is the default wrapper at `~/.Nebula/opencode-wrapper.ps1`:

```powershell
param()
try {
    $inputJson = [Console]::In.ReadToEnd()
    $parsed = $inputJson | ConvertFrom-Json
    $sessionId = $parsed.session_id
    $message = $parsed.payload
    $agentMd = $parsed.agent_md

    $nebulaDir = Split-Path -Parent $PSCommandPath
    $convDir = Join-Path $nebulaDir "data\conversations"
    if (-not (Test-Path $convDir)) { New-Item -ItemType Directory -Path $convDir -Force | Out-Null }
    $convFile = Join-Path $convDir "$sessionId.txt"

    $conversation = ""
    if (Test-Path $convFile) { $conversation = Get-Content $convFile -Raw }
    if ([string]::IsNullOrWhiteSpace($conversation) -and -not [string]::IsNullOrWhiteSpace($agentMd)) {
        $conversation = "System: $agentMd`r`n`r`n"
    }

    $conversation += "User: $message`r`n"

    $output = & opencode run --format json $conversation 2>&1
    $responseText = ""
    foreach ($line in $output) {
        $lineStr = "$line"
        try {
            $event = $lineStr | ConvertFrom-Json
            if ($event.type -eq "text" -and $event.part.text) { $responseText += $event.part.text }
        } catch {}
    }

    $conversation += "Assistant: $responseText`r`n"
    Set-Content -Path $convFile -Value $conversation -Encoding utf8
    Write-Output $responseText
} catch { Write-Output "Error processing request"; exit 1 }
```

### PowerShell — Claude Code

Available at `~/.Nebula/claude-wrapper.ps1`:

```powershell
param()
try {
    $inputJson = [Console]::In.ReadToEnd()
    $parsed = $inputJson | ConvertFrom-Json
    $sessionId = $parsed.session_id
    $message = $parsed.payload
    $agentMd = $parsed.agent_md

    $nebulaDir = Split-Path -Parent $PSCommandPath
    $convDir = Join-Path $nebulaDir "data\conversations"
    if (-not (Test-Path $convDir)) { New-Item -ItemType Directory -Path $convDir -Force | Out-Null }
    $convFile = Join-Path $convDir "$sessionId.txt"

    $conversation = ""
    if (Test-Path $convFile) { $conversation = Get-Content $convFile -Raw }
    if ([string]::IsNullOrWhiteSpace($conversation) -and -not [string]::IsNullOrWhiteSpace($agentMd)) {
        $conversation = "System: $agentMd`r`n`r`n"
    }

    $conversation += "User: $message`r`n"
    $output = & claude "$conversation" 2>&1
    $responseText = ($output | Out-String).Trim()

    $conversation += "Assistant: $responseText`r`n"
    Set-Content -Path $convFile -Value $conversation -Encoding utf8
    Write-Output $responseText
} catch { Write-Output "Error processing request"; exit 1 }
```

### Bash/Linux — OpenCode

```bash
#!/usr/bin/env bash
set -e
read -r line
session_id=$(echo "$line" | python3 -c "import sys,json; print(json.load(sys.stdin)['session_id'])")
message=$(echo "$line" | python3 -c "import sys,json; print(json.load(sys.stdin)['payload'])")
agent_md=$(echo "$line" | python3 -c "import sys,json; print(json.load(sys.stdin).get('agent_md',''))")

nebula_dir="$(dirname "$(readlink -f "$0")")"
conv_dir="$nebula_dir/data/conversations"
mkdir -p "$conv_dir"
conv_file="$conv_dir/$session_id.txt"

conversation=""
[ -f "$conv_file" ] && conversation=$(cat "$conv_file")
[ -z "$conversation" ] && [ -n "$agent_md" ] && conversation="System: $agent_md\n\n"

conversation="$conversation\nUser: $message\n"
response=$(opencode run --format json "$conversation" 2>/dev/null | \
  python3 -c "
import sys, json
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try:
        ev = json.loads(line)
        if ev.get('type') == 'text':
            print(ev.get('part', {}).get('text', ''), end='')
    except: pass
")

conversation="$conversation\nAssistant: $response\n"
echo "$conversation" > "$conv_file"
echo "$response"
```

### Bash/Linux — Claude Code

```bash
#!/usr/bin/env bash
set -e
read -r line
session_id=$(echo "$line" | python3 -c "import sys,json; print(json.load(sys.stdin)['session_id'])")
message=$(echo "$line" | python3 -c "import sys,json; print(json.load(sys.stdin)['payload'])")
agent_md=$(echo "$line" | python3 -c "import sys,json; print(json.load(sys.stdin).get('agent_md',''))")

nebula_dir="$(dirname "$(readlink -f "$0")")"
conv_dir="$nebula_dir/data/conversations"
mkdir -p "$conv_dir"
conv_file="$conv_dir/$session_id.txt"

conversation=""
[ -f "$conv_file" ] && conversation=$(cat "$conv_file")
[ -z "$conversation" ] && [ -n "$agent_md" ] && conversation="System: $agent_md\n\n"

conversation="$conversation\nUser: $message\n"
response=$(claude "$conversation" 2>/dev/null)

conversation="$conversation\nAssistant: $response\n"
echo "$conversation" > "$conv_file"
echo "$response"
```

### Bash/Linux — Generic (any CLI)

```bash
#!/usr/bin/env bash
set -e
read -r line
session_id=$(echo "$line" | python3 -c "import sys,json; print(json.load(sys.stdin)['session_id'])")
message=$(echo "$line" | python3 -c "import sys,json; print(json.load(sys.stdin)['payload'])")

nebula_dir="$(dirname "$(readlink -f "$0")")"
conv_dir="$nebula_dir/data/conversations"
mkdir -p "$conv_dir"
conv_file="$conv_dir/$session_id.txt"

conversation=""
[ -f "$conv_file" ] && conversation=$(cat "$conv_file")

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

- If the wrapper exits with non-zero code, Nebula logs the error but continues running
- If the wrapper outputs nothing, Nebula treats the response as empty
- If the wrapper outputs multiple lines, Nebula only reads the first line
- If a session is deleted via the API, the backend removes both the session folder and its conversation file
