# BetterVoiceControl Development Guide

## Build Commands
- Build: `xcodebuild -project BetterVoiceControl.xcodeproj -scheme BetterVoiceControl build`
- Run: Open project in Xcode and click Run or press ⌘+R
- Clean: `xcodebuild clean -project BetterVoiceControl.xcodeproj`
- Test: `xcodebuild test -project BetterVoiceControl.xcodeproj -scheme BetterVoiceControl`

## Code Style Guidelines
- **NO COMMENTS**: Never use code comments. Use the log function to document code behavior and intention.
- **Logging**: Always use `appState.log("ComponentName", "Message")` instead of print statements or comments.
- **UI Updates**: Ensure all UI-related updates happen on the main thread using DispatchQueue.main.async.
- **Formatting**: 4-space indentation, consistent line breaks after function signatures.
- **Naming**: camelCase for functions/variables, PascalCase for types/protocols, ALL_CAPS for constants.
- **Error Handling**: Use Swift's Result type or try/catch with meaningful error messages.
- **Concurrency**: Use async/await or DispatchQueue for asynchronous operations.
- **Memory Management**: Always use [weak self] in closures to prevent retain cycles.
- **UI Components**: Follow SwiftUI conventions with previews for visual components.

## API Keys
- Store OpenAI API key in environment variables or Xcode build configuration
- Never commit API keys to the repository

## Voice Control Features
- Real-time voice transcription using OpenAI Realtime API
- Voice commands for Claude Code CLI navigation
- Hands-free prompt editing and sending
- Terminal control integration via AppleScript
- Automatic internal restart on any error (microphone issues, API failures, etc.)

## Workflow Requirements
**ALWAYS commit and push changes immediately after making modifications** so the user can read changes on their iPad:
1. After making any code changes, immediately run git add, commit, and push
2. Use concise one-liner commit messages with no Claude attribution or clutter
3. For full sentences in commit messages, end with a full stop. For keyword-style messages, no full stop needed
4. This allows the user to review changes on other devices in real-time