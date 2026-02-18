# Changelog

## v1.3.1 - Reliability + Voice Loop + English Docs

### Added

- Automatic memory ingestion for user preferences/facts during AI interactions (ChatGPT-like memory behavior).
- In-app voice command chain:
  - real-time ASR
  - wake word detection
  - optional auto-execute
  - response TTS
- Voice controls in the main search bar and full voice configuration in settings.
- Web search multi-source fallback pipeline:
  - DuckDuckGo -> Wikipedia -> Bing RSS
- Knowledge query fallback to web results when Codex is unavailable.
- New regression test for automatic memory capture.

### Changed

- Arrow-key navigation now works consistently for both app candidates and `/` help menu candidates.
- Enter key now applies the currently highlighted help command.
- AI output rendering now enforces better structure/spacing and improved Matrix visual style (not background-only).
- Settings panel is now scrollable/resizable and no longer clips lower sections.
- Packaging script now includes microphone + speech recognition usage descriptions in `Info.plist`.
- Primary docs are now English-first.

### Fixed

- Menu bar "Preferences" action now reliably opens the settings window.
- Nested settings scroll issue in the embedded panel.

### QA

- `swift build` passed.
- `swift test` passed (`16 tests passed`).

## v1.3.0 - AI Native Context + Voice Edition

### Added

- Conversation history persistence (`conversation_history.json`) with `/history` query support.
- Memory persistence (`memory.json`) with `/memory`, `/remember`, and `/forget`.
- Web search command `/web` (DuckDuckGo API in v1.3.0 baseline).
- Arrow-key app candidate selection for app open/close flows.
- New `SynapseVoice` headless executable:
  - core tools: `read/write/edit/bash`
  - filesystem-based memory/history
  - TTS output (`--mute` supported)

### Changed

- AI prompts now include memory + recent conversation context.
- Matrix visual mode added for AI cards (`aiVisualStyle=matrix`).
- New config options:
  - `enableWebSearch`
  - `aiVisualStyle`

## v1.2.2 - Model Options Alignment

### Changed

- Fast / Think / Deep Research model lists aligned to available Codex CLI models:
  - `gpt-5.3-codex`
  - `gpt-5.2-codex`
  - `gpt-5.1-codex-max`
  - `gpt-5.2`
  - `gpt-5.1-codex-mini`
- Updated default mode models:
  - Fast: `gpt-5.1-codex-mini`
  - Think: `gpt-5.1-codex-max`
  - Deep Research: `gpt-5.2`
- README, packaging scripts, and release docs updated to `v1.2.2`.

## v1.2.1 - Deep Research Compatibility Patch

### Fixed

- Deep Research mode now falls back automatically when `--search` is unsupported by the local `codex-cli`.
- Hard errors (unsupported model/arguments) no longer trigger unnecessary retries.

### Changed

- README, packaging scripts, release notes, and Homebrew cask updated to `v1.2.1`.

## v1.2.0 - Hotkey + Fuzzy + AI Mode Refactor

### Added

- Configurable global hotkey presets (default `Option + Space`) with live re-registration.
- New AI translation capability (`/translate` + natural-language translation intent).
- Slash command fuzzy matching with alias support (`/q` routes to `/quit`).

### Changed

- Codex mode strategy refactored to mode-specific model selection.
- Per-mode reasoning effort controls (`fast / think / deep_research`) are independently configurable.
- App launch/close now use local app indexing and fuzzy matching (partial names supported).

### Fixed

- Removed model fallback path for deterministic mode behavior.
- Improved slash-command miss handling to fall back to natural-language intent recognition.
- Reduced translation-intent misrouting.

## v1.0.0 - First Release

### Added

- Initial macOS floating panel architecture.
- Intent engine with rule + module routing.
- Slash command palette and command filtering.
- Absolute-path file search with click-to-open behavior.
- Synapse configuration panel and settings persistence.
- Codex AI integration for knowledge/code/writing.
- Visual cards for IP, battery, and date.

### Fixed

- IME (Chinese/English switch) related intent extraction crash.
- Slash command completion and help matching behavior.
- Panel expand/collapse behavior for empty and command states.
- File search output ordering and path rendering.
