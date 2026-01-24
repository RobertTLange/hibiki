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
Sources/Hibiki/
├── HibikiApp.swift              # App entry point
├── AppDelegate.swift            # Menu bar setup, window management
├── Core/
│   ├── AppState.swift           # Main application state
│   ├── AccessibilityManager.swift   # Text selection via accessibility API
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
