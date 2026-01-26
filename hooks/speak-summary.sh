#!/bin/bash

LOG="/tmp/speak-summary-debug.log"
echo "=== $(date) ===" >> "$LOG"

# Read the hook input from stdin
input=$(cat)
echo "Input: $input" >> "$LOG"

# Extract transcript path (expand ~)
transcript_path=$(echo "$input" | jq -r '.transcript_path' | sed "s|^~|$HOME|")
echo "Transcript path: $transcript_path" >> "$LOG"

# Check if file exists
if [[ ! -f "$transcript_path" ]]; then
    echo "ERROR: File not found: $transcript_path" >> "$LOG"
    exit 1
fi

echo "File exists, reading..." >> "$LOG"

# Get the last assistant message - using a different approach to avoid subshell issue
last_message=""
while IFS= read -r line; do
    msg_type=$(echo "$line" | jq -r '.type // empty' 2>/dev/null)
    if [[ "$msg_type" == "assistant" ]]; then
        last_message=$(echo "$line" | jq -r '.message.content[] | select(.type == "text") | .text' 2>/dev/null | head -c 500)
    fi
done < "$transcript_path"

echo "Last message (first 100 chars): ${last_message:0:100}" >> "$LOG"

if [[ -n "$last_message" ]]; then
    echo "Calling hibiki..." >> "$LOG"
    hibiki --text "$last_message" >> "$LOG" 2>&1 &
    echo "hibiki exit code: $?" >> "$LOG"
else
    echo "No message found" >> "$LOG"
fi

echo "Done" >> "$LOG"
