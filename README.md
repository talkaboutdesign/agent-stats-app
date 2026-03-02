# Agent Stats

![CodeRabbit Pull Request Reviews](https://img.shields.io/coderabbit/prs/github/talkaboutdesign/agent-stats-app?utm_source=oss&utm_medium=github&utm_campaign=talkaboutdesign%2Fagent-stats-app&labelColor=171717&color=FF570A&link=https%3A%2F%2Fcoderabbit.ai&label=CodeRabbit+Reviews)

Agent Stats is a macOS SwiftUI dashboard for local AI session analytics.

It aggregates activity from local Codex and Claude session data and shows:
- Session and thread counts
- Estimated spend and model cost breakdowns
- Activity and usage charts
- Recent/live session status

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

## Data

The app reads local Codex and Claude session metadata from your machine and computes dashboard summaries from that data.

## License

This project is licensed under the Apache License 2.0. See `LICENSE` for details.
