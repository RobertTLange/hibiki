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

| Feature | Description |
|---------|-------------|
| **Global Hotkeys** | Option+F for TTS, Shift+Option+F for Summarize+TTS |
| **Streaming Audio** | Audio plays as it's generated for fast response |
| **Multiple Voices** | Alloy, Echo, Fable, Onyx, Nova, Shimmer, Coral, Sage |
| **AI Summarization** | Condense long texts before reading (GPT-5 Nano/Mini/5.2) |
| **Translation** | Translate to English, Japanese, German, French, Spanish |
| **CLI Tool** | `hibiki --text "Hello"` with `--summarize` and `--translate` flags |
| **History & Stats** | Track past requests and API usage costs |
| **Audio Player UI** | Visual waveform display with playback speed control (1.0x-2.5x) |

## Requirements

- macOS 14.0 or later
- OpenAI API key with access to the TTS API
- Accessibility permission (to read selected text from other apps)

## Installation

```bash
git clone <repo-url> && cd hibiki
./build.sh --run              # Build and run
./build.sh --install          # Install CLI to /usr/local/bin
./build.sh --dmg              # Create DMG for distribution
```

Or download the DMG, double-click to mount, and drag Hibiki to Applications.

The CLI is also available at `Hibiki.app/Contents/MacOS/hibiki-cli`.

## Setup

1. **Launch Hibiki** — appears as speaker icon in menu bar
2. **Grant Accessibility Permission** — Settings → follow instructions
3. **Add OpenAI API Key** — Settings or `OPENAI_API_KEY` environment variable
4. **Configure Hotkeys** (optional) — defaults: Option+F (TTS), Shift+Option+F (Summarize+TTS)

## CLI Usage

The Hibiki app must be running. Use hotkeys (Option+F, Shift+Option+F) for GUI-based TTS.

```bash
hibiki --text "Hello, world!"                        # Basic TTS
hibiki --text "Long article..." --summarize          # Summarize + TTS
hibiki --text "Hello" --translate ja                 # Translate + TTS
hibiki --text "Article..." --summarize --translate fr # Full pipeline
```

**Languages:** `en` (English), `ja` (Japanese), `de` (German), `fr` (French), `es` (Spanish)

## Claude Code Integration

See the `claude/` directory for integration files.

### Skill

Add Hibiki as a Claude Code skill so Claude can speak text aloud:

```bash
mkdir -p ~/.claude/skills/tts-hibiki
cp claude/SKILL.md ~/.claude/skills/tts-hibiki/SKILL.md
```

### Hook

Automatically speak Claude's final response when a session ends:

```bash
cp claude/speak-summary.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/speak-summary.sh
```

Then merge `claude/hooks.json` into your `~/.claude/settings.json`.

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "No text selected" | Ensure text is selected before pressing hotkey |
| "Accessibility permission not granted" | Grant permission in System Settings |
| "No API key configured" | Add key in Settings or set `OPENAI_API_KEY` |
| Chrome not capturing text | Hibiki auto-falls back to clipboard (Cmd+C) |

Debug logs available in Settings → Debug tab.

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
