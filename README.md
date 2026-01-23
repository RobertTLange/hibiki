# Hibiki

```
 _     _ _     _ _    _
| |   (_) |   (_) |  (_)
| |__  _| |__  _| | ___
| '_ \| | '_ \| | |/ / |
| | | | | |_) | |   <| |
|_| |_|_|_.__/|_|_|\_\_|
```

A macOS menu bar app that reads selected text aloud using OpenAI's text-to-speech API.

## Features

- **Global hotkey** - Select text in any application and press Option+F to hear it read aloud
- **Streaming audio** - Audio plays as it's generated for fast response times
- **Multiple voices** - Choose from OpenAI's TTS voices (Alloy, Echo, Fable, Onyx, Nova, Shimmer, Coral, Sage)
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

# Run the app
open .build/Hibiki.app
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

4. **Configure Hotkey** (optional)
   - The default hotkey is Option+F
   - You can change it in Settings

## Usage

1. Select text in any application (Chrome, Safari, Notes, etc.)
2. Press Option+F (or your configured hotkey)
3. Listen to the text being read aloud
4. Press the hotkey again to stop playback

## Troubleshooting

### Text not being captured from Chrome/web browsers

Some applications (like Chrome) don't properly expose selected text via the accessibility API. Hibiki automatically falls back to using the clipboard method (simulating Cmd+C) when this happens.

### Debug Logs

Open Settings and scroll to the Debug Logs section to see detailed logs of what Hibiki is doing. This can help diagnose issues with:
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
├── HibikiApp.swift           # App entry point
├── AppDelegate.swift        # Menu bar setup, window management
├── Core/
│   ├── AppState.swift       # Main application state
│   ├── AccessibilityManager.swift  # Text selection via accessibility API
│   ├── PermissionManager.swift     # Permission checking
│   └── DebugLogger.swift    # In-app debug logging
├── Audio/
│   ├── TTSService.swift     # OpenAI TTS API client
│   └── StreamingAudioPlayer.swift  # PCM audio playback
└── Views/
    ├── SettingsView.swift   # Settings window
    ├── MenuBarView.swift    # Menu bar popover
    └── DebugLogTableView.swift  # Debug log display
```

## License

MIT
