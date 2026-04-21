---
name: hibiki-tts
description: Text-to-speech via OpenAI API with optional summarization and translation using the hibiki CLI.
---

# Hibiki TTS Skill

Use the `hibiki` CLI to speak text aloud using OpenAI's text-to-speech API, with optional AI-powered summarization and translation.

## When to Use

Invoke this skill when the user:
- Wants text read aloud
- Asks to hear something spoken
- Needs to summarize and speak content
- Wants text translated and spoken
- Requests audio output of text content
- Wants a file read aloud

## Requirements

- The Hibiki macOS app must be running (check menu bar for speaker icon)
- The CLI communicates with the app via URL scheme

## Commands

### Basic Text-to-Speech
```bash
hibiki --text "Hello, world!"
```
Speaks the provided text aloud using the configured voice.

### File Input (Text from File)
```bash
hibiki --file-name README.md
```
Reads UTF-8 text from a file and speaks it aloud.

### Summarize + TTS
```bash
hibiki --text "Long article or document text here..." --summarize
hibiki --file-name notes.md --summarize
```
Summarizes the text using an LLM, then speaks the summary aloud. Useful for long content.

### Summarize + TTS (Custom Prompt)
```bash
hibiki --text "Long article..." --summarize --prompt "Concise: 3 bullets, no fluff."
hibiki --text "Design doc..." --summarize --prompt "Thorough: goals, decisions, tradeoffs, risks, next steps."
```
Overrides the default summarization prompt (requires `--summarize`).

### Translate + TTS
```bash
hibiki --text "Hello" --translate ja
hibiki --file-name draft.txt --translate fr
```
Translates the text to the specified language, then speaks it aloud.

### Full Pipeline (Summarize + Translate + TTS)
```bash
hibiki --text "Long article text..." --summarize --translate fr
```
Summarizes the text, translates the summary, then speaks it aloud.

### Help
```bash
hibiki --help
```

## Supported Languages

| Code | Language |
|------|----------|
| `en` | English |
| `ja` | Japanese |
| `de` | German |
| `fr` | French |
| `es` | Spanish |

## Example Usage

**User asks:** "Read this paragraph aloud"
```bash
hibiki --text "The paragraph content here"
```

**User asks:** "Summarize this article and read it to me"
```bash
hibiki --text "Full article content..." --summarize
```

**User asks:** "Give me a concise summary and read it"
```bash
hibiki --text "Full article content..." --summarize --prompt "Provide a concise summary: 2 bullets."
```

**User asks:** "Give me a thorough summary and read it"
```bash
hibiki --text "Full article content..." --summarize --prompt "Provide a thorough summary: key points, evidence, caveats, next steps."
```

**User asks:** "Translate this to Japanese and speak it"
```bash
hibiki --text "Hello, how are you?" --translate ja
```

**User asks:** "Summarize this and read it in German"
```bash
hibiki --text "Long content..." --summarize --translate de
```

**User asks:** "Read this file out loud"
```bash
hibiki --file-name docs/notes.txt
```

## Notes

- Maximum text length is ~32KB (after URL encoding)
- Input source: use exactly one of `--text` or `--file-name`
- `--file-name` expects UTF-8 text files
- Audio plays through the Hibiki AudioPlayerPanel UI
- Requests are saved to Hibiki's history
- Voice and API settings are configured in the Hibiki app's Settings
- The command runs asynchronously - audio plays after a brief processing delay
- For very long content, use `--summarize` to condense before speaking
