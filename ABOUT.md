# About Neo-Synapse

## What is Neo-Synapse?

Neo-Synapse is the next evolution of Synapse — a native macOS floating command center that consolidates multiple workflows into a single keyboard-driven interface.

Neo-Synapse takes the core Synapse experience and adds:

1. **Session-based conversation history** — inspired by Claude Code's conversation management
2. **Filesystem memory paradigm** — inspired by OpenViking's context database for AI Agents
3. **Matrix visual theme** — immersive green-on-black terminal aesthetic with digital rain
4. **Headless AI Native voice agent** — SynapseVoice, a pi-agent-core Unix philosophy pet robot

## Design Principles

### Single Entry
All operations accessible through one interface. Global hotkey activates everywhere.

### Keyboard First
High-frequency operations require no mouse. Arrow keys navigate, Enter executes, Escape dismisses.

### Native First
Swift + SwiftUI + AppKit for performance. External tools only where native APIs are insufficient.

### Memory as Filesystem
Memories organized in virtual directories (`synapse://`), with L0/L1/L2 tiered context loading — inspired by OpenViking's approach to context management for AI Agents.

### Headless AI Native
SynapseVoice embodies the Unix philosophy: only 4 primitives (read/write/edit/bash), everything else is filesystem. No GUI needed. Pure intelligence.

### Structured Feedback
Results as actionable cards. Selectable, copyable, clickable. Matrix-style or Native-style rendering.

## Target Users

- **Developers**: Quick access to file search, app switching, code generation, system commands
- **AI Power Users**: Context-aware AI with persistent memory and conversation history
- **Terminal Enthusiasts**: Matrix aesthetic, keyboard-first, headless voice agent
- **Knowledge Workers**: Unified command interface with structured feedback

## Relationship to Synapse

Neo-Synapse is a feature-enhanced fork of [Synapse](https://github.com/0smboy/Synapse). All original Synapse capabilities are preserved and enhanced.

Key additions over Synapse v1.3.x:
- Session management for conversation history (500 entries, session grouping, auto-titles)
- OpenViking-inspired filesystem memory with synapse:// URI scheme and L0/L1/L2 tiers
- Enhanced Matrix visual theme with animated digital rain, scanlines, glow effects
- SynapseVoice pet robot with personality system, proactive capabilities, and autonomous agent mode
- New commands: `/sessions`, `/tree`, `schedule`, `watch`, `agent`, `status`, etc.
