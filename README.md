# Neo-Synapse

**Neo-Synapse** is the next evolution of [Synapse](https://github.com/0smboy/Synapse) — a floating command center for macOS.
It unifies app control, file search, system actions, and AI tasks in one keyboard-first surface, now with enhanced conversation history, OpenViking-inspired memory management, Matrix visual styling, and a headless AI Native voice agent.

## What's New in Neo-Synapse

### Session-Based Conversation History (Claude Code Style)
- Conversations are grouped into **sessions** — new session on app launch or after 30 min idle
- Browse sessions via `/sessions`, search across all history with keyword highlighting
- Each session has auto-generated titles for easy recall
- Up to 500 history entries with session metadata

### OpenViking-Inspired Memory System
- Memories organized in a **filesystem paradigm** with `synapse://` URI scheme
- Auto-categorization into directories: `preferences/`, `facts/`, `identity/`, `goals/`, `skills/`
- **L0/L1/L2 tiered context**: Abstract → Overview → Full details for efficient token usage
- Browse memory tree via `/tree`, explore categories with `/memory preferences`
- Up to 500 persistent memory items

### Matrix Visual Theme (黑客帝国风)
- Full Matrix terminal aesthetic with green-on-black rendering
- **Animated digital rain** background behind AI responses
- **Scanline overlay** with scrolling animation
- **Glow pulse** border effects on AI cards
- Dynamic Matrix headers: `ACCESS_GRANTED`, `SIGNAL_STRENGTH`, `DECRYPTION: COMPLETE`
- Character-by-character typing effect for AI responses

### SynapseVoice: Headless AI Native Pet Robot
- **Pet personality system** — configurable persona stored in `~/.synapse-voice/personality.md`
- Default personality: "Neo" — a friendly, slightly sarcastic AI assistant
- **pi-agent-core Unix philosophy**: only 4 tools — `read/write/edit/bash`, everything else is filesystem
- **Proactive capabilities**: `schedule`, `watch`, `agent` for autonomous task execution
- **Matrix-style terminal output** with ASCII art banner and typing animation
- Built-in commands: `status`, `search`, `open`, `weather`

## Feature Showcase

### Command Palette + Prefix Matching
Type `/` to see all commands, fuzzy-match with partial input.

### App Launch with Arrow Key Navigation
`/open` and `/close` show matched apps — use `↑/↓` to navigate, `Enter` to confirm.

### AI with Matrix Visual Style
AI responses render in green-on-black with digital rain, scanlines, and glow effects.

### Memory Filesystem Tree
```
synapse://
├── user/
│   └── memories/
│       ├── preferences/ (12 items)
│       ├── facts/ (8 items)
│       ├── identity/ (3 items)
│       ├── goals/ (5 items)
│       └── general/ (15 items)
└── agent/
    └── skills/ (2 items)
```

## Core Capabilities

- **Single entry**: global hotkey + slash commands + natural language
- **Smart intent routing**: command-first, fuzzy matching, then AI fallback
- **System operations**: launch/close apps, file search, lock/screenshot/dark mode/date/ip/battery/trash
- **AI features (Codex-only)**: `/ask`, `/web`, `/code`, `/write`, `/translate`
- **Context layer**: session-based conversation history + auto-managed filesystem memory
- **Voice loop**: wake word + real-time speech recognition + optional auto-execute + TTS
- **Rich rendering**: selectable/copyable output, structured formatting, Matrix/Native visual modes

## Install

### Build from Source

```shell
git clone https://github.com/0smboy/neo-synapse.git
cd neo-synapse
swift build
swift run Synapse
```

### Headless Voice Edition

```shell
swift run SynapseVoice
swift run SynapseVoice --mute          # no TTS
swift run SynapseVoice --personality   # custom personality
```

## Command Reference

| Command | Args | Description | Example |
|---------|------|-------------|---------|
| `/open` | required | Launch app | `/open Safari` |
| `/close` | required | Close app | `/close WeChat` |
| `/find` | required | Find files | `/find report.pdf` |
| `/setting` | none | Open macOS settings | `/setting` |
| `/config` | none | Open Synapse settings | `/config` |
| `/help` | none | Open command menu | `/help` |
| `/quit` | none | Quit Synapse | `/quit` |
| `/ask` | required | Knowledge query | `/ask What is vector DB` |
| `/web` | required | Web search | `/web SwiftData tutorial` |
| `/code` | required | Code generation | `/code write LRU cache in Swift` |
| `/write` | required | Writing assistant | `/write weekly project summary` |
| `/translate` | required | Translation | `/translate hello to Chinese` |
| `/history` | optional | Query conversation history | `/history release` |
| `/sessions` | none | List conversation sessions | `/sessions` |
| `/memory` | optional | Query memory | `/memory preferences` |
| `/tree` | none | Memory filesystem tree | `/tree` |
| `/remember` | required | Add explicit memory | `/remember I prefer concise output` |
| `/forget` | none | Clear memory | `/forget` |
| `/calc` | required | Calculator | `/calc (32+16)*4` |
| `/define` | required | Dictionary lookup | `/define serendipity` |
| `/color` | required | Color parser | `/color #4F46E5` |
| `/emoji` | required | Emoji search | `/emoji happy` |
| `/clipboard` | none | Clipboard history | `/clipboard` |
| `/lock` | none | Lock screen | `/lock` |
| `/screenshot` | none | Screenshot | `/screenshot` |
| `/darkmode` | none | Toggle dark mode | `/darkmode` |
| `/ip` | none | IP card | `/ip` |
| `/battery` | none | Battery card | `/battery` |
| `/date` | none | Date/time card | `/date` |
| `/trash` | none | Empty trash | `/trash` |

## Voice System

Real-time voice command loop:

- Real-time ASR (`Speech` framework)
- Wake word trigger (`synapse` by default)
- Optional auto-execute after recognition
- Optional response TTS

Required macOS permissions: Microphone, Speech Recognition, Apple Events.

## SynapseVoice Commands

```
voice> read <path>                    # Read file
voice> write <path> <<< <content>     # Write file
voice> edit <path> | <find> => <replace>  # Edit file
voice> bash <command>                 # Run shell command
voice> remember <text>                # Save to memory
voice> memory                         # View memory
voice> history                        # View history
voice> status                         # System status
voice> search <query>                 # Search files
voice> open <app>                     # Launch app
voice> weather                        # Weather info
voice> schedule <time> <task>         # Schedule reminder
voice> watch <path>                   # Watch file changes
voice> agent <task>                   # Autonomous agent
voice> personality                    # View personality
voice> set-personality <text>         # Set personality
voice> <any question>                 # AI query via Codex
voice> quit                           # Exit
```

## Configuration

Open with `/config`.

- **Codex mode**: `fast / think / deep_research`
- **Per-mode model selection & reasoning effort**
- **Timeouts** for knowledge/code/writing
- **Auto memory** toggle
- **Web search** toggle
- **Rich AI formatting** toggle
- **Visual style**: `matrix` / `native`
- **Voice** toggles + wake word + locale
- **Global hotkey** preset

## Architecture

```
SearchBar -> SynapseViewModel -> IntentEngine -> IntentExecutor
  -> Modules (AI / Web / System / File / Memory / History / Voice)
  -> ResultListView (structured, selectable, copyable)

Memory Layer:
  synapse://user/memories/{category}/{id}  (L0/L1/L2 tiered)
  synapse://agent/skills/{id}

Session Layer:
  ConversationSession -> ConversationHistoryEntry (grouped by session)

Voice Agent (SynapseVoice):
  pi-agent-core: read/write/edit/bash
  personality + memory + history -> Codex
```

## Design Philosophy

### Inspired by Claude Code
Session-based conversation management with auto-titling and cross-session search.

### Inspired by OpenViking
Filesystem paradigm for memory — memories as virtual files in directories, L0/L1/L2 tiered loading.

### Inspired by pi-agent-core
Unix minimalism — only `read/write/edit/bash`, everything else is filesystem.

### Headless AI Native
SynapseVoice is a typeless, headless agent. No GUI needed. Pure terminal + voice.

## Development

```shell
swift build
swift test
swift run Synapse          # GUI version
swift run SynapseVoice     # Headless voice version
```

## System Requirements

- **Platform:** macOS Sonoma (14.0) or later
- **Architecture:** ARM64 (Apple Silicon)
- **Dependencies:** Codex CLI (for AI features)
- **Permissions:** Accessibility, Automation, Microphone, Speech Recognition

## License

MIT License. See LICENSE for details.
