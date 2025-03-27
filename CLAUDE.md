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

## Web Search Integration
- Use the Responses API with web_search_preview tool
- Sample query to display below the prompt in UI: "What's happening in tech today?"
- Enable web search using the following function call:
```swift
client.responses.create(
    model: "gpt-4o",
    tools: [["type": "web_search_preview"]],
    input: userQuery
)
```