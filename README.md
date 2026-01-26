# Hibiki

```                                       
 _     _ _     _ _    _              .-----------.  
| |   (_) |   (_) |  (_)          .-'   .-----.   '-. 
| |__  _| |__  _| | ___          /   .--'     '--.   \ 
| '_ \| | '_ \| | |/ / |        /   /   .-----.   \   \
| | | | | |_) | |   <| |       /   /   /       \   \   \ 
|_| |_|_|_.__/|_|_|\_\_|      |   |   |   (O)   |   |   |
```


A macOS menu bar app that reads selected text aloud using OpenAI's text-to-speech API, with AI-powered summarization and translation.

## Features

### Text-to-Speech
- **Global hotkey** - Select text in any application and press Option+F to hear it read aloud
- **Streaming audio** - Audio plays as it's generated for fast response times
- **Multiple voices** - Choose from OpenAI's TTS voices (Alloy, Echo, Fable, Onyx, Nova, Shimmer, Coral, Sage)
- **Playback speed control** - Adjust speed from 1.0x to 2.5x during playback
- **Text chunking** - Automatically handles long texts by splitting them into chunks

### AI Summarization
- **Summarize + TTS** - Summarize long texts with AI before reading aloud (Shift+Option+F)
- **Customizable prompts** - Configure the summarization system prompt to your needs
- **Model selection** - Choose between GPT-5 Nano, GPT-5 Mini, or GPT-5.2

### Translation
- **Translate + TTS** - Translate text to another language before reading aloud
- **Multiple languages** - Supports English, Japanese, and German
- **Customizable prompts** - Configure translation prompts with `{language}` placeholder
- **Combined workflows** - Summarize and translate in one action

### Configurable Hotkeys
- **Trigger TTS** - Read selected text aloud (default: Option+F)
- **Summarize + TTS** - Summarize then read (default: Shift+Option+F)
- **Translate + TTS** - Translate then read
- **Summarize + Translate + TTS** - Full processing pipeline

### Command Line Interface
- **CLI tool** - Use Hibiki from the terminal with `hibiki --text "Hello"`
- **Pipeline options** - Combine `--summarize` and `--translate` flags
- **Integration** - Works with the running Hibiki app via URL scheme

### Additional Features
- **Audio player UI** - Visual waveform display during playback
- **History tracking** - Review and replay past TTS requests
- **Usage statistics** - Track your API usage and costs
- **Menu bar app** - Runs quietly in your menu bar, no dock icon
- **Debug logging** - Built-in debug log viewer in Settings to troubleshoot issues

## Requirements

- macOS 14.0 or later
- OpenAI API key with access to the TTS API
- Accessibility permission (to read selected text from other apps)

## Installation

### Build from source

```bash
# Clone the repository
git clone <repo-url>
cd hibiki

# Build the app
./build.sh

# Optionally set OpenAI API Key
export OPENAI_API_KEY='sk-...'

# Run the app
open .build/Hibiki.app

# Or just run ./build.sh --run
```

### Create DMG installer

To create a DMG file for distribution:

```bash
# Build release version and create DMG
./build.sh --dmg

# The DMG will be created at .build/Hibiki.dmg
```

Open the DMG and drag Hibiki to your Applications folder to install.

### Install CLI tool

The CLI tool is built alongside the app. Use `--install` to add it to your PATH:

```bash
# Build and install CLI to /usr/local/bin (may prompt for sudo)
./build.sh --install

# Or combine with other flags
./build.sh --run --install
```

After installation, you can run `hibiki` from anywhere:

```bash
hibiki --text "Hello world"
hibiki --help
```

**Manual installation alternatives:**

```bash
# Symlink to /usr/local/bin
sudo ln -sf "$(pwd)/.build/debug/hibiki" /usr/local/bin/hibiki

# Or add build directory to PATH (in ~/.zshrc or ~/.bashrc)
export PATH="$PATH:/path/to/hibiki/.build/debug"
```

The CLI is also available inside the app bundle at `Hibiki.app/Contents/MacOS/hibiki-cli`.

### Development

```bash
# Build only
swift build

# Run directly (without .app bundle)
swift run
```

## Setup

1. **Launch Hibiki** - The app appears as a speaker icon in your menu bar

2. **Grant Accessibility Permission**
   - Click the menu bar icon and select "Settings..."
   - Follow the instructions to grant Accessibility permission in System Settings
   - You may need to restart the app after granting permission

3. **Add your OpenAI API Key**
   - In Settings, enter your OpenAI API key
   - Alternatively, set the `OPENAI_API_KEY` environment variable

4. **Configure Hotkeys** (optional)
   - The default TTS hotkey is Option+F
   - The default Summarize+TTS hotkey is Shift+Option+F
   - You can customize all hotkeys in Settings

5. **Configure Translation** (optional)
   - Select a target language in Settings (English, Japanese, German)
   - Customize the translation model and prompt as needed

## Usage

### Basic TTS
1. Select text in any application (Chrome, Safari, Notes, etc.)
2. Press Option+F (or your configured hotkey)
3. Listen to the text being read aloud
4. Press Option to stop playback

### Summarize + TTS
1. Select text in any application
2. Press Shift+Option+F
3. Watch the streaming summarization, then listen to the summary

### Translate + TTS
1. Select text in any application
2. Press your configured Translate+TTS hotkey
3. Listen to the translation being read aloud

### Combined Summarize + Translate + TTS
1. Select text in any application
2. Press your configured hotkey
3. Text is summarized, then translated, then read aloud

### Command Line Interface

The `hibiki` CLI allows you to use Hibiki from the terminal. The Hibiki app must be running.

```bash
# Basic text-to-speech
hibiki --text "Hello, world!"

# Summarize before speaking
hibiki --text "Long article text here..." --summarize

# Translate to another language
hibiki --text "Hello" --translate ja

# Full pipeline: summarize, translate, then speak
hibiki --text "Long article..." --summarize --translate fr

# Get help
hibiki --help
```

**Supported languages for `--translate`:**
- `en` - English
- `ja` - Japanese
- `de` - German
- `fr` - French
- `es` - Spanish

**How it works:** The CLI sends a request to the running Hibiki app via a custom URL scheme (`hibiki://`). The app processes the text using your configured settings (voice, API key, etc.) and plays the audio through the AudioPlayerPanel. The entry is saved to history just like hotkey-triggered requests.

### Claude Code Hook Integration

Hibiki can be used as a [Claude Code hook](https://docs.anthropic.com/en/docs/claude-code/hooks) to speak Claude's responses aloud. For example, configure a `Stop` hook to read the final assistant message when a session ends.

**1. Create the hook script** (`~/.claude/hooks/speak-summary.sh`):

```bash
#!/bin/bash
input=$(cat)
transcript_path=$(echo "$input" | jq -r '.transcript_path' | sed "s|^~|$HOME|")

if [[ ! -f "$transcript_path" ]]; then
    exit 1
fi

# Extract the last assistant message (up to 500 chars)
last_message=""
while IFS= read -r line; do
    msg_type=$(echo "$line" | jq -r '.type // empty' 2>/dev/null)
    if [[ "$msg_type" == "assistant" ]]; then
        last_message=$(echo "$line" | jq -r '.message.content[] | select(.type == "text") | .text' 2>/dev/null | head -c 500)
    fi
done < "$transcript_path"

if [[ -n "$last_message" ]]; then
    hibiki --text "$last_message" &
fi
```

Make it executable: `chmod +x ~/.claude/hooks/speak-summary.sh`

**2. Configure the hook** in your Claude Code settings (`~/.claude/settings.json` or project `.claude/settings.json`):

```json
{
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/speak-summary.sh"
          }
        ]
      }
    ]
  }
}
```

Now when you exit Claude Code, Hibiki will read Claude's final response aloud.

## Troubleshooting

### Text not being captured from Chrome/web browsers

Some applications (like Chrome) don't properly expose selected text via the accessibility API. Hibiki automatically falls back to using the clipboard method (simulating Cmd+C) when this happens.

### Debug Logs

Open Settings and click the Debug tab to see detailed logs of what Hibiki is doing. This can help diagnose issues with:
- Accessibility permissions
- Text selection detection
- API connectivity
- Audio playback

### Common Issues

- **"No text selected"** - Make sure text is actually selected in the target app before pressing the hotkey
- **"Accessibility permission not granted"** - Follow the setup instructions to grant permission in System Settings
- **"No API key configured"** - Add your OpenAI API key in Settings or set the `OPENAI_API_KEY` environment variable

## Architecture

```
Sources/
├── HibikiCLI/
│   └── HibikiCLI.swift          # CLI executable (argument parsing, URL scheme)
└── Hibiki/
    ├── HibikiApp.swift              # App entry point
    ├── AppDelegate.swift            # Menu bar setup, window management, URL handling
    ├── Core/
    │   ├── AppState.swift           # Main application state
    │   ├── AccessibilityManager.swift   # Text selection via accessibility API
    │   ├── CLIRequestHandler.swift  # Handles CLI requests via URL scheme
    │   ├── PermissionManager.swift      # Permission checking
    │   ├── DebugLogger.swift        # In-app debug logging
    │   ├── HistoryManager.swift     # TTS history tracking
    │   ├── HistoryEntry.swift       # History data model
    │   ├── LLMService.swift         # OpenAI LLM API client (summarization/translation)
    │   ├── TextChunker.swift        # Long text chunking
    │   └── UsageStatistics.swift    # Usage tracking
    ├── Audio/
    │   ├── TTSService.swift         # OpenAI TTS API client
    │   ├── StreamingAudioPlayer.swift   # PCM audio playback
    │   └── AudioLevelMonitor.swift  # Audio level monitoring for waveform
    └── Views/
        ├── MainSettingsView.swift   # Tabbed settings window
        ├── MenuBarView.swift        # Menu bar popover
        ├── AudioPlayerPanel.swift   # Audio player with waveform
        ├── WaveformView.swift       # Waveform visualization
        └── Tabs/
            ├── ConfigurationTab.swift   # API key, voice, hotkeys
            ├── DebugTab.swift           # Debug log viewer
            ├── HistoryTab.swift         # TTS history
            └── StatisticsTab.swift      # Usage statistics
```
