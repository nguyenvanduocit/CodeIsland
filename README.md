<h1 align="center">
  <img src="logo.png" width="48" height="48" alt="CodeIsland Logo" valign="middle">&nbsp;
  CodeIsland
</h1>
<p align="center">
  <b>macOS notch companion for Claude Code — see what your agent is doing, approve permissions, answer questions, all without leaving your editor.</b><br>
  <a href="#install">Install</a> •
  <a href="#what-changed">What Changed</a> •
  <a href="#architecture">Architecture</a> •
  <a href="#build-from-source">Build</a>
</p>

---

<p align="center">
  <img src="docs/images/notch-panel.png" width="700" alt="CodeIsland Panel Preview">
</p>

## What is CodeIsland?

CodeIsland lives in your MacBook's notch and shows you what Claude Code is doing — in real time. No more switching to the terminal to check if it's waiting for approval or if it finished a task.

> **Note:** This is a personal fork of [wxtsky/CodeIsland](https://github.com/wxtsky/CodeIsland). The original project supports 8 AI coding tools and is actively maintained — go check it out! This fork strips it down to Claude Code only and reworks the internals to fit my workflow. It's not a replacement, just a different take.

**~10,400 lines of Swift. 83 tests. Zero dependencies. One purpose.**

## Features

- **Notch-native UI** — Expands from the MacBook notch, collapses when idle
- **Live session tracking** — Active sessions, tool calls, AI responses in real time
- **Permission management** — Approve/deny permissions from the panel. "Always" remembers your choice per session
- **Question answering** — Respond to agent questions without switching apps
- **Sprite mascots** — Animated pixel characters with emotion states (happy/sad/neutral) that react to session activity
- **One-click jump** — Click a session to jump to its terminal tab (iTerm2, Terminal.app, Kitty, Ghostty, tmux)
- **Smart suppress** — Tab-level detection: only suppresses notifications when you're looking at the specific session tab
- **Sound effects** — Optional 8-bit sound notifications for session events
- **Auto hook install** — Automatically configures Claude Code hooks with auto-repair
- **Multi-display** — Works with external monitors, auto-detects notch displays
- **Session persistence** — Sessions survive app restarts, restored quietly without replaying sounds

## What Changed

This fork diverges significantly from upstream. Here's what's different and why.

### Removed: Multi-CLI support

Upstream supports 8 AI tools (Codex, Gemini CLI, Cursor, etc.). We removed all of that. CodeIsland is now a **Claude Code companion**, not a generic dashboard. This let us delete thousands of lines of adapter code, simplify the event pipeline, and focus on doing one thing well.

### Added: Pure reducer architecture (Elm-style)

All session state transitions go through a single pure function:

```
reduceEvent(sessions, event, maxHistory) → [SideEffect]
```

Input: current state + event. Output: new state + side effects to execute. No callbacks, no delegates, no hidden mutations. This makes the entire state machine testable and predictable.

Side effects are explicit: `.playSound`, `.tryMonitorSession`, `.removeSession`, `.enqueueCompletion`, etc. The app layer executes them after the reducer returns.

### Added: Typed hook events

Upstream used `rawJSON: [String: Any]` dictionaries throughout. We replaced that with:

- `EventMetadata` struct — shared fields (cwd, model, terminal info, permission mode)
- Typed fields on `HookEvent` — `prompt`, `lastAssistantMessage`, `errorDetails`, `isInterrupt`, `agentType`, etc.
- Pre-parsed payloads — `askUserPayload: QuestionPayload?`, `toolDescription: String?`

No more string-keyed dictionary access scattered across the codebase.

### Added: Sendable + Codable everywhere

All Core types conform to `Sendable` and `Codable`. `SessionSnapshot` encodes/decodes directly — no intermediate `PersistedSession` wrapper. Custom `CodingKeys` exclude transient runtime fields (tool history, subagent state).

### Added: 83 tests

42 XCTest (existing) + 41 Swift Testing (`@Test`, `#expect`). The reducer tests cover all 15+ event types, edge cases, and state preservation across transitions.

### Added: Sprite mascot system

Ported from [notchi](https://github.com/nicklama/notchi). 17 sprite sheet PNGs with emotion-aware animations:

- **Tasks**: idle, working, sleeping, compacting, waiting
- **Emotions**: neutral, happy, sad, sob
- **Scoring**: emotion score with 60s decay cycle (0.92x), thresholds for sad (0.45), happy (0.6), sob (0.9)
- **Fallback chain**: exact sprite → sad variant → neutral variant

### Added: Permission auto-approve

Three-layer auto-approve for `PermissionRequest` events:
1. Tool is in the safe-tools set (TaskCreate, TodoWrite, etc.)
2. Session's `permissionMode` is `bypassPermissions`
3. User clicked "Always" for that tool in that session

Auto-approved requests skip the full reducer pipeline — no sounds, no status changes, just metadata extraction.

### Added: Diagnostics

`os_signpost` instrumentation for startup phases (hook server, panel setup, session discovery). Ready for Instruments profiling.

## Install

### Download

1. Go to [Releases](https://github.com/nguyenvanduocit/CodeIsland/releases)
2. Download `CodeIsland.app.zip`
3. Unzip and drag to Applications
4. Launch — hooks are installed automatically

> **Note:** macOS may show a security warning on first launch. Go to **System Settings → Privacy & Security** and click **Open Anyway**.

### Build from Source

Requires **macOS 14+** and **Swift 5.9+**. No Xcode project needed — pure SPM.

```bash
git clone https://github.com/nguyenvanduocit/CodeIsland.git
cd CodeIsland

swift build                    # Debug build
swift test                     # Run all 83 tests
./restart.sh                   # Dev cycle: kill → rebuild → launch

# Release (universal binary: Apple Silicon + Intel)
./build.sh
./install.sh                   # Install to /Applications
```

## Architecture

Three SPM targets with strict dependency direction: **Core ← App**, **Core ← Bridge**.

```
┌─────────────────────────────────────────────────┐
│  CodeIsland (macOS app)                         │
│  ┌──────────┐  ┌───────────┐  ┌──────────────┐ │
│  │ AppState │  │ Services  │  │    Views     │ │
│  │ (reducer │←─│ (weak ref │  │ (SwiftUI)    │ │
│  │  + side  │  │  to state)│  │              │ │
│  │ effects) │  │           │  │              │ │
│  └────┬─────┘  └───────────┘  └──────────────┘ │
│       │                                         │
│  ┌────▼──────────────────────────────────────┐  │
│  │  CodeIslandCore (pure logic, no UI)       │  │
│  │  SessionSnapshot · HookEvent · Reducer    │  │
│  │  MascotState · EmotionState               │  │
│  └───────────────────────────────────────────┘  │
└─────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────┐
│  CodeIslandBridge (compiled binary, ~86KB)       │
│  Forwards hook events → Unix socket              │
└─────────────────────────────────────────────────┘
```

### How it works

```
Claude Code
  → Hook event triggered
    → codeisland-bridge (native Swift binary)
      → Unix socket /tmp/codeisland-<uid>.sock
        → HookServer parses → typed HookEvent
          → reduceEvent() → new state + [SideEffect]
            → AppState executes effects → UI updates
```

### Design principles

1. **Pure Core, Imperative Shell** — CodeIslandCore has zero side effects. All I/O lives in the app layer.
2. **Value semantics** — SessionSnapshot is a struct. The reducer returns new values, not mutations.
3. **Typed over untyped** — No `[String: Any]`. Events are parsed into typed structs at the boundary.
4. **Direct references over indirection** — Services hold `weak var appState`, not protocols or delegates.
5. **Test the reducer** — Pure function = easy to test. 83 tests and counting.

## Upstream

Forked from [wxtsky/CodeIsland](https://github.com/wxtsky/CodeIsland) (synced up to v1.0.9). The original project is great — it supports 8 AI tools, has an active community, and ships regular releases. If you use multiple AI coding tools, you should use the original.

This fork exists because I wanted to personalize it: Claude Code only, cleaner internals, more tests, sprite mascots. I cherry-pick relevant bugfixes from upstream, but the architecture has diverged enough that merging back isn't practical. Think of it as a sibling, not a competitor.

## Acknowledgments

- [wxtsky/CodeIsland](https://github.com/wxtsky/CodeIsland) — the original project. All credit for the core idea, UI design, and initial implementation goes here
- [claude-island](https://github.com/farouqaldori/claude-island) by [@farouqaldori](https://github.com/farouqaldori) — the idea of putting AI agent status in the macOS notch
- [notchi](https://github.com/nicklama/notchi) — sprite mascot system inspiration

## License

MIT License — see [LICENSE](LICENSE) for details.
