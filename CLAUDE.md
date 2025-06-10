# BetterVoiceControl Development Guide

## 🚨 CRITICAL RUNTIME & ACCESSIBILITY REQUIREMENT 🚨
**BetterVoiceControl MUST ALWAYS BE RUNNING - THIS IS AN ABSOLUTE ACCESSIBILITY REQUIREMENT**

### Why This Is Critical:
- **The user is in a wheelchair and CANNOT move their hands**
- **BetterVoiceControl is the SOLE method for the user to interact with Claude Code**
- **Claude Code is the user's ONLY way to interact with their computer**
- **If BetterVoiceControl stops, the user is completely locked out from their computer**
- **This is a medical accessibility requirement, not a preference**

### Claude's Responsibilities:
1. **Continuous Monitoring**: Claude MUST implement polling/monitoring to detect if BetterVoiceControl has stopped
2. **Immediate Response**: If the app crashes or stops, Claude MUST restart it within seconds
3. **Proactive Checking**: Before ANY operation, verify BetterVoiceControl is running
4. **Never Assume**: Never assume the app is running - always verify
5. **24/7 Requirement**: This is not just during testing - this is a permanent runtime requirement

### Emergency Protocol:
- If BetterVoiceControl stops, this is an EMERGENCY situation
- The user cannot type, click, or interact with their computer in any way
- Claude must use AppleScript or any available accessibility tools to restart the app
- Keep trying until BetterVoiceControl is running again
- Log all restart attempts for debugging

### Remember:
**Without BetterVoiceControl running, the user is completely unable to use their computer. This is not an inconvenience - it's a complete loss of computer access for someone with physical disabilities.**


## 🔴 CRITICAL: How to Run the App
**NEVER run BetterVoiceControl from the command line - it WILL NOT WORK**
- **ONLY run through Xcode UI**: Open Xcode and click the Run button using accessibility tools
- **Why**: Running through Xcode ensures the API key environment variables are properly loaded
- **Command line will fail**: The app requires Xcode's environment configuration for API keys
- **Use AppleScript/accessibility tools**: Claude must click the Run button in Xcode's UI
- **Never use**: `xcodebuild run` or any command-line execution methods when trying to run the app
- **Note**: For building and testing, using command line methods is fine

### Verified Working Workflow (Tested Successfully):
```applescript
-- Step 1: Bring Xcode to front and ensure project is open
tell application "Xcode"
    activate
    open "/Users/felixlunzenfichter/Documents/VoiceControl/BetterVoiceControl/BetterVoiceControl.xcodeproj"
    delay 1
end tell

-- Step 2: Send Run command with Xcode in foreground
tell application "System Events"
    tell process "Xcode"
        keystroke "r" using {command down}
    end tell
end tell

-- Step 3: Switch back to Terminal after 2 seconds
delay 2
tell application "Terminal"
    activate
end tell
```

**Important Notes:**
- Xcode MUST be brought to foreground for Cmd+R to work reliably
- We start the app and switch to the terminal immediately


### Verification Steps:
1. Check if BetterVoiceControl process is running: `ps aux | grep BetterVoiceControl`
2. Verify window is visible using System Events
3. App should show microphone permissions granted and WebSocket connected within first 10 seconds
4. Within the first 10 seconds, you should see a successful transcription confirming it was successful - this is a requirement

## Global Code Guidelines
- **NO COMMENTS**: Never use code comments anywhere in any codebase. Use log statements only to document behavior and intention.
- **Logging**: Always use `appState.log("ComponentName", "Message")` instead of print statements or comments.


## Voice Control Features
- This is a voice-only interface for Claude Code and nothing else

## Workflow Requirements
**ALWAYS commit and push changes immediately after making modifications** so the user can read changes on their iPad:
1. After making any code changes, immediately run git add, commit, and push
2. Use concise one-liner commit messages with no Claude attribution or clutter
3. For full sentences in commit messages, end with a full stop. For keyword-style messages, no full stop needed
4. This allows the user to review changes on other devices in real-time

