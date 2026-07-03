# Nebula Backend - Custom Wrapper Scripts

## Overview

Wrapper scripts translate between Nebula's JSON-over-stdin protocol and your AI agent's CLI interface. This guide explains the protocol and provides templates for common agents.

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

## Writing a Wrapper

### Basic Structure (Any Language)

```python
#!/usr/bin/env python3
import sys, json, subprocess

# 1. Read JSON from stdin
line = sys.stdin.read()
data = json.loads(line)
message = data["payload"]

# 2. Call the agent CLI
result = subprocess.run(
    ["your-agent-cli", message],
    capture_output=True, text=True
)

# 3. Output response as single line
print(result.stdout.strip())
```

### PowerShell (Windows) — OpenCode

This is the default wrapper at `~/.nebula/opencode-wrapper.ps1`:

```powershell
param()
$inputJson = [Console]::In.ReadToEnd()
$parsed = $inputJson | ConvertFrom-Json
$message = $parsed.payload
$output = & opencode run --format json $message 2>&1
$responseText = ""
foreach ($line in $output) {
    $lineStr = "$line"
    try {
        $event = $lineStr | ConvertFrom-Json
        if ($event.type -eq "text" -and $event.part.text) {
            $responseText += $event.part.text
        }
    } catch {}
}
Write-Output $responseText
```

### PowerShell — Claude Code

Available at `~/.nebula/claude-wrapper.ps1`:

```powershell
param()
$inputJson = [Console]::In.ReadToEnd()
$parsed = $inputJson | ConvertFrom-Json
$message = $parsed.payload
$output = & claude "$message" 2>&1
$responseText = $output | Out-String
Write-Output $responseText.Trim()
```

### Bash/Linux — OpenCode

```bash
#!/usr/bin/env bash
read -r line
message=$(echo "$line" | python3 -c "import sys,json; print(json.load(sys.stdin)['payload'])")
opencode run --format json "$message" 2>/dev/null | \
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
"
```

### Bash/Linux — Claude Code

```bash
#!/usr/bin/env bash
read -r line
message=$(echo "$line" | python3 -c "import sys,json; print(json.load(sys.stdin)['payload'])")
claude "$message" 2>/dev/null
```

### Bash/Linux — Generic (any CLI)

```bash
#!/usr/bin/env bash
read -r line
message=$(echo "$line" | python3 -c "import sys,json; print(json.load(sys.stdin)['payload'])")
your-cli "$message"
```

## Installing a Custom Wrapper

1. Place your wrapper in `~/.nebula/` (e.g., `~/.nebula/my-wrapper.ps1`)
2. Update `~/.nebula/config.toml`:

```toml
[agent]
command = "powershell"
args = ["-File", "C:\\Users\\You\\.nebula\\my-wrapper.ps1"]
mode = "stdio"
```

3. Restart the Nebula server.

## Testing a Wrapper

Test your wrapper independently before connecting it to Nebula:

```powershell
# Simulate what Nebula sends
'{"payload":"Say hello in one word"}' | powershell -File ~/.nebula/my-wrapper.ps1
```

Expected output should be a single line with the agent's response.

## Error Handling

- If the wrapper exits with non-zero code, Nebula logs the error but continues running
- If the wrapper outputs nothing, Nebula treats the response as empty
- If the wrapper outputs multiple lines, Nebula only reads the first line
