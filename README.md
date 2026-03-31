# Hibiki

```
 _     _ _     _ _    _              .-----------.
| |   (_) |   (_) |  (_)          .-'   .-----.   '-.
| |__  _| |__  _| | ___          /   .--'     '--.   \
| '_ \| | '_ \| | |/ / |        /   /   .-----.   \   \
| | | | | |_) | |   <| |       /   /   /       \   \   \
|_| |_|_|_.__/|_|_|\_\_|      |   |   |   (O)   |   |   |
```

A macOS menu bar app that reads selected text aloud using OpenAI, ElevenLabs, or self-hosted local TTS endpoints. Built for agentic workflows, Hibiki supports global hotkeys, streaming audio playback, and a CLI (`hibiki --text "Hello"`) so text from editors, browsers, and terminal sessions can be spoken instantly. Agent integration is a core feature: the repo includes ready-to-use skill and hook files so coding agents can trigger speech and spoken summaries directly from workflows. Hibiki also supports optional AI summarization and translation before playback, plus history and usage tracking.

**Blog walkthrough:** [How I Built Hibiki](https://roberttlange.com/index.html#posts/blog/02-hibiki-tts.md)

[![Read the Hibiki walkthrough blog post](docs/demo.png)](https://roberttlange.com/index.html#posts/blog/02-hibiki-tts.md)

## Features

| Feature | Description |
|---------|-------------|
| **Agent Integration** | Built-in skill + hook templates for agent-driven spoken output |
| **Global Hotkeys** | Option+F for TTS, Shift+Option+F for Summarize+TTS |
| **Streaming Audio** | Audio plays as it's generated for fast response |
| **TTS Providers** | OpenAI, ElevenLabs, local Pocket TTS, or self-hosted Mistral Voxtral |
| **AI Summarization** | Condense long texts before reading (GPT-5 Nano/Mini/5.2) |
| **Translation** | Translate to English, Japanese, German, French, Spanish |
| **CLI Tool** | `hibiki --text "Hello"` or `hibiki --file-name README.md` with `--summarize` and `--translate` flags |
| **History & Stats** | Track past requests and API usage costs |
| **Audio Player UI** | Visual waveform display with playback speed control (1.0x-2.5x) |

## Requirements

- macOS 14.0 or later
- OpenAI API key (required for summarization/translation and OpenAI TTS)
- ElevenLabs API key (required if using ElevenLabs TTS provider)
- `uv` (required for one-click managed Pocket TTS install)
- Accessibility permission (to read selected text from other apps)

## Installation

Build from source (recommended):

```bash
git clone https://github.com/RobertTLange/hibiki.git
cd hibiki
./build.sh
cp -R .build/Hibiki.app /Applications/Hibiki.app
open /Applications/Hibiki.app
sudo ln -sf /Applications/Hibiki.app/Contents/MacOS/hibiki-cli /usr/local/bin/hibiki
```

CLI binary path inside the app bundle: `Hibiki.app/Contents/MacOS/hibiki-cli`

## Setup

1. **Launch Hibiki** — appears as speaker icon in menu bar
2. **Grant Accessibility Permission** — Settings → follow instructions
3. **Add API key(s)** — OpenAI and/or ElevenLabs in Settings, or env vars `OPENAI_API_KEY` / `ELEVENLABS_API_KEY`
4. **Configure Hotkeys** (optional) — defaults: Option+F (TTS), Shift+Option+F (Summarize+TTS)

### Environment Variables (macOS menu bar apps)

If Hibiki is launched from Finder or `open`, it may not inherit terminal shell exports.  
Set env vars through `launchctl` for GUI app visibility:

```bash
launchctl setenv OPENAI_API_KEY "sk-..."
launchctl setenv ELEVENLABS_API_KEY "..."
launchctl setenv POCKET_TTS_BASE_URL "http://127.0.0.1:8000"
launchctl setenv MISTRAL_TTS_BASE_URL "http://127.0.0.1:8091"
launchctl setenv MISTRAL_TTS_API_KEY "optional-local-token"
launchctl setenv MISTRAL_TTS_MODEL_ID "mistralai/Voxtral-4B-TTS-2603"
```

Remove them later with `launchctl unsetenv <NAME>`.

### Local Pocket TTS (managed)

1. Open **Settings → Configuration → Local Pocket TTS (Managed)**.
2. Enable managed runtime.
3. Click **Install / Reinstall** (uses `uv` to create a local venv and install `pocket-tts`).
4. Click **Start** (or enable auto-start).
5. Select provider **Pocket TTS (Local)** in the Text to Speech section.

Default managed endpoint: `http://127.0.0.1:8000`

Integration note: Hibiki uses a managed local Pocket TTS runtime (install/start/health checks in-app) and streams Pocket-generated WAV audio directly to the built-in player.

Official Pocket TTS repository: [kyutai-labs/pocket-tts](https://github.com/kyutai-labs/pocket-tts)

Note: Pocket local mode is currently English-only in Hibiki.

### Local Mistral Voxtral TTS

Hibiki can target `mistralai/Voxtral-4B-TTS-2603` either through a manual OpenAI-compatible endpoint or a managed local runtime.

Managed mode is backend-dependent:
- On Apple Silicon macOS, Hibiki installs `mlx-audio[all]` and runs `mlx_audio.server` locally with the MLX-converted model `mlx-community/Voxtral-4B-TTS-2603-mlx-bf16`.
- On Linux GPU hosts, Hibiki installs `vllm>=0.18.0` plus `vllm-omni` and launches `vllm serve mistralai/Voxtral-4B-TTS-2603 --omni`.

#### Managed Voxtral runtime

1. Open **Settings → Configuration → Local Voxtral TTS (Managed)**.
2. Enable managed runtime.
3. Click **Install / Reinstall**.
4. Click **Start** (or enable auto-start).
5. Select provider **Mistral Voxtral (Local)** in the Text to Speech section.

Default managed endpoint: `http://127.0.0.1:8091`

Note: Managed Voxtral on Mac requires Apple Silicon because the local path uses MLX. If managed install or launch fails on your host, Hibiki will surface the runtime error and you can still use manual endpoint mode.

#### Manual Voxtral endpoint

1. Start a compatible server, for example:

```bash
vllm serve mistralai/Voxtral-4B-TTS-2603 --omni
```

2. Open **Settings → Text to Speech**.
3. Select provider **Mistral Voxtral (Local)**.
4. Set the base URL, model ID, and voice preset if needed.
5. Optionally set `MISTRAL_TTS_BASE_URL`, `MISTRAL_TTS_MODEL_ID`, and `MISTRAL_TTS_API_KEY` via `launchctl`.

Hibiki sends requests to `/v1/audio/speech` and converts the returned WAV audio for playback.

Official model card: [mistralai/Voxtral-4B-TTS-2603](https://huggingface.co/mistralai/Voxtral-4B-TTS-2603)

## CLI Usage

The Hibiki app must be running. Use hotkeys (Option+F, Shift+Option+F) for GUI-based TTS.

```bash
hibiki --text "Hello, world!"                        # Basic TTS
hibiki --file-name README.md                         # Read from file
hibiki --text "Long article..." --summarize          # Summarize + TTS
hibiki --file-name Sources/HibikiCLI/HibikiCLI.swift --summarize # Summarize file + TTS
hibiki --text "Long article..." --summarize --prompt "Summarize in 3 bullets." # Custom summary prompt
hibiki --text "Hello" --translate ja                 # Translate + TTS
hibiki --text "Article..." --summarize --translate fr # Full pipeline
```

**Languages:** `en` (English), `ja` (Japanese), `de` (German), `fr` (French), `es` (Spanish)
**Prompt override:** `--prompt` replaces the default summarization prompt (requires `--summarize`).
**Input source:** use exactly one of `--text` or `--file-name`.
**File decoding:** `--file-name` expects UTF-8 text files.
**Markdown cleanup:** `.md` / `.markdown` files get balanced cleanup (frontmatter/comments removed, headings/lists normalized, links simplified, code fences converted for speech).
**Input size limit:** request URL payload must stay under ~32KB after encoding; very large files should be summarized or split.

## Agent Integration

See the `agents/` directory for integration files.

### Skill

Add Hibiki as a Claude Code skill so Claude can speak text aloud:

```bash
mkdir -p ~/.claude/skills/tts-hibiki
cp agents/SKILL.md ~/.claude/skills/tts-hibiki/SKILL.md
```

### Hook

Automatically speak Claude's final response when a session ends:

```bash
cp agents/speak-summary.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/speak-summary.sh
```

Then merge `agents/hooks.json` into your `~/.claude/settings.json`.

## Security

- Never commit API keys to this repo.
- Prefer configuring keys inside Hibiki Settings.
- For menu bar app launches, prefer `launchctl setenv ...` so Hibiki can read env vars.

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "No text selected" | Ensure text is selected before pressing hotkey |
| "Accessibility permission not granted" | Grant permission in System Settings |
| "No OpenAI API key configured" | Add key in Settings, or run `launchctl setenv OPENAI_API_KEY "sk-..."` |
| "No ElevenLabs API key configured" | Add key in Settings, or run `launchctl setenv ELEVENLABS_API_KEY "..."` |
| "uv was not found" | Install `uv` and retry Pocket managed install |
| "Managed Voxtral runtime is not supported on this Mac configuration" | Use Apple Silicon for the local MLX path, or run Voxtral on a separate Linux GPU host and use manual endpoint mode |
| "Voxtral install failed" | Ensure the host can run `vllm` / `vllm-omni`, then retry the managed install or use manual endpoint mode |
| "Invalid API URL" with Mistral Voxtral | Verify the base URL points at a compatible server exposing `/v1/audio/speech` |
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
    │   ├── PocketTTSRuntimeManager.swift # Managed local Pocket runtime install/start/health
    │   ├── PermissionManager.swift      # Permission checking
    │   ├── DebugLogger.swift        # In-app debug logging
    │   ├── HistoryManager.swift     # TTS history tracking
    │   ├── HistoryEntry.swift       # History data model
    │   ├── LLMService.swift         # OpenAI LLM API client (summarization/translation)
    │   ├── TextChunker.swift        # Long text chunking
    │   └── UsageStatistics.swift    # Usage tracking
    ├── Audio/
    │   ├── TTSService.swift         # OpenAI + ElevenLabs + local Pocket/Voxtral TTS client
    │   ├── WAVStreamDecoder.swift   # Streaming WAV -> PCM decoder for local Pocket TTS
    │   ├── StreamingAudioPlayer.swift   # PCM audio playback
    │   └── AudioLevelMonitor.swift  # Audio level monitoring for waveform
    └── Views/
        ├── MainSettingsView.swift   # Tabbed settings window
        ├── MenuBarView.swift        # Menu bar popover
        ├── AudioPlayerPanel.swift   # Audio player with waveform
        ├── WaveformView.swift       # Waveform visualization
        └── Tabs/
            ├── ConfigurationTab.swift   # Provider, API keys, voice, hotkeys
            ├── DebugTab.swift           # Debug log viewer
            ├── HistoryTab.swift         # TTS history
            └── StatisticsTab.swift      # Usage statistics
```
