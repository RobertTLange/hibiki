#!/bin/bash
# Claude Code "Stop" hook: speak the agent's final message with Hibiki.
#
# Debug log is opt-in because it contains transcript text:
#   HIBIKI_HOOK_DEBUG=1  ->  ${TMPDIR:-/tmp}/hibiki-speak-summary.log (owner-only)

# Longest message handed to hibiki. The CLI rejects requests above ~32KB after URL
# encoding (and --summarize runs after transport), so longer messages are cut here.
MAX_CHARS=12000

if [[ -n "$HIBIKI_HOOK_DEBUG" ]]; then
    umask 077
    LOG="${TMPDIR:-/tmp}/hibiki-speak-summary.log"
else
    LOG=/dev/null
fi
log() { echo "$*" >> "$LOG"; }

log "=== $(date) ==="

# Read the hook input from stdin
input=$(cat)

# Extract transcript path (expand ~)
transcript_path=$(echo "$input" | jq -r '.transcript_path' | sed "s|^~|$HOME|")
log "Transcript path: $transcript_path"

if [[ ! -f "$transcript_path" ]]; then
    log "ERROR: File not found: $transcript_path"
    exit 1
fi

# Get the last assistant message
last_message=""
while IFS= read -r line; do
    msg_type=$(echo "$line" | jq -r '.type // empty' 2>/dev/null)
    if [[ "$msg_type" == "assistant" ]]; then
        last_message=$(echo "$line" | jq -r '.message.content[] | select(.type == "text") | .text' 2>/dev/null)
    fi
done < "$transcript_path"

log "Last message length: ${#last_message}"

if [[ -z "$last_message" ]]; then
    log "No message found"
    exit 0
fi

if [[ ${#last_message} -gt $MAX_CHARS ]]; then
    log "Message > $MAX_CHARS chars, truncating"
    last_message="${last_message:0:$MAX_CHARS}"
fi

# --text=<value>: a message starting with "-" (markdown bullet) must not be read as a flag.
if [[ ${#last_message} -gt 500 ]]; then
    summary_prompt="Very concise summary of coding agent activity. 1-2 short sentences. Mention key changes and files."
    log "Message > 500 chars, using --summarize"
    hibiki --text="$last_message" --summarize --prompt="$summary_prompt" >> "$LOG" 2>&1 &
else
    log "Calling hibiki..."
    hibiki --text="$last_message" >> "$LOG" 2>&1 &
fi

log "Done"
