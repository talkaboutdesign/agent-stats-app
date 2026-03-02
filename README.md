# Agent Stats

![CodeRabbit Pull Request Reviews](https://img.shields.io/coderabbit/prs/github/talkaboutdesign/agent-stats-app?utm_source=oss&utm_medium=github&utm_campaign=talkaboutdesign%2Fagent-stats-app&labelColor=171717&color=FF570A&link=https%3A%2F%2Fcoderabbit.ai&label=CodeRabbit+Reviews)

Agent Stats is an open source macOS SwiftUI app for analyzing local AI agent activity from Codex and Claude CLI sessions.

It gives you a live dashboard for:
- Session/thread activity
- Token usage patterns
- Estimated model cost over time
- Active/recent session rollups
- Provider/account limit status surfaced from local CLI/auth state

## Why Agent Stats

If you use local agent tooling heavily, it is hard to answer basic questions like:
- Which models are driving spend?
- What are my busiest hours/days?
- How much activity is active right now?
- How do Codex and Claude usage compare over the same period?

Agent Stats aggregates local session metadata into a single desktop view so you can monitor usage without leaving your machine.

## Features

- Multi-provider ingestion:
  - Codex sessions from `~/.codex`
  - Claude sessions from `~/.claude/projects`
- Dashboard views:
  - Overview metrics
  - Costs and model trends
  - Thread-level activity table
- Visualization components:
  - Cost-by-model bars
  - Daily activity + hourly usage charts
  - Activity heatmap
- Local persistence/cache via SwiftData for faster reloads
- Auto-refresh loop (plus manual refresh)
- Model pricing snapshots bundled in app resources

## Privacy & Data Handling

Agent Stats is local-first:
- Reads files from your local `~/.codex` and `~/.claude` directories
- Uses local SQLite/JSONL parsing for analysis
- Stores cached snapshots locally using SwiftData

No external telemetry pipeline is required for core dashboard functionality.

## Requirements

- macOS
- Xcode 15+ (or newer)

## Run

1. Open `Agent Stats.xcodeproj` in Xcode.
2. Select the `Agent Stats` scheme.
3. Build and run on `My Mac`.

Or from terminal:

```bash
xcodebuild -project "Agent Stats.xcodeproj" \
  -scheme "Agent Stats" \
  -configuration Debug \
  -destination 'platform=macOS' \
  build
```

## Project Structure

Current architecture is organized by responsibility:

- `Agent Stats/Domain`:
  - Core domain utilities (token math, model normalization)
- `Agent Stats/Services`:
  - Application services (cost calculation, live session rollups, snapshot store)
- `Agent Stats/Infrastructure`:
  - File system, CLI/process, pricing loading, metadata and DB adapters
- `Agent Stats/Parsers`:
  - Codex/Claude session JSONL parsers
- `Agent Stats/ViewModels`:
  - Section-level view models for Dashboard / Pricing / Threads
- `Agent Stats/*.swift`:
  - App composition, root model, and SwiftUI views/components

## Data Sources

The app builds snapshots from:
- Session files (`.jsonl`) in Codex/Claude local folders
- Codex local state database (`state_5.sqlite`) when available
- Bundled pricing files:
  - `Agent Stats/openai_pricing.json`
  - `Agent Stats/claude_pricing.json`

## Contributing

Contributions are welcome.

Suggested workflow:
1. Fork the repo
2. Create a feature branch
3. Make focused changes with clear commit messages
4. Validate with local build:
   `xcodebuild -project "Agent Stats.xcodeproj" -scheme "Agent Stats" -configuration Debug -destination 'platform=macOS' build`
5. Open a pull request with:
   - What changed
   - Why it changed
   - Any behavior/UI impact

## Roadmap Ideas

- Export analytics as CSV/JSON
- Configurable refresh interval
- Additional provider adapters
- Historical trend comparison presets
- Optional snapshot import/export

## License

This project is licensed under the Apache License 2.0. See `LICENSE` for details.
