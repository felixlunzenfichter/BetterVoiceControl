let PROMPT_PROPERTY: [String: String] = [
    "type": "string",
    "description": "The refined or new prompt to be displayed and eventually sent to Claude Code."
]

let EDIT_PROMPT_PROPERTIES: [String: [String: String]] = [
    "prompt": PROMPT_PROPERTY
]

let EDIT_PROMPT_PARAMS: [String: Any] = [
    "type": "object", 
    "properties": EDIT_PROMPT_PROPERTIES,
    "required": ["prompt"]
]

let SEND_PROMPT_PARAMS: [String: Any] = [
    "type": "object",
    "properties": [String: Any](),
    "required": [String]()
]

let EMPTY_PARAMS: [String: Any] = [
    "type": "object",
    "properties": [String: Any](),
    "required": [String]()
]

let EDIT_PROMPT_FUNCTION: [String: Any] = [
    "type": "function",
    "name": "editPrompt",
    "description": "Refines or replaces the current prompt based on user input. The updated prompt is displayed on screen in real-time.",
    "parameters": EDIT_PROMPT_PARAMS
]

let SEND_PROMPT_FUNCTION: [String: Any] = [
    "type": "function",
    "name": "sendPrompt",
    "description": "Transmits the final, refined prompt to the Claude Code coding agent for execution.",
    "parameters": SEND_PROMPT_PARAMS
]

let ACCEPT_FUNCTION: [String: Any] = [
    "type": "function",
    "name": "accept",
    "description": "Executes a return/enter key press in Terminal for accepting current action in Claude Code CLI. Triggered by keyword 'accept'.",
    "parameters": EMPTY_PARAMS
]

let REJECT_FUNCTION: [String: Any] = [
    "type": "function",
    "name": "reject",
    "description": "Executes a sequence for rejecting current action in Claude Code CLI. Triggered by keyword 'reject'.",
    "parameters": EMPTY_PARAMS
]

let ARROW_UP_FUNCTION: [String: Any] = [
    "type": "function",
    "name": "arrowUp",
    "description": "Executes an up arrow key press in Terminal for navigating in Claude Code CLI. Triggered by keyword 'arrow up'.",
    "parameters": EMPTY_PARAMS
]

let ARROW_DOWN_FUNCTION: [String: Any] = [
    "type": "function",
    "name": "arrowDown",
    "description": "Executes a down arrow key press in Terminal for navigating in Claude Code CLI. Triggered by keyword 'arrow down'.",
    "parameters": EMPTY_PARAMS
]

let ESCAPE_FUNCTION: [String: Any] = [
    "type": "function",
    "name": "escape",
    "description": "Executes an escape key press in Terminal for canceling actions in Claude Code CLI. Triggered by keyword 'escape'.",
    "parameters": EMPTY_PARAMS
]

let CLEAR_FUNCTION: [String: Any] = [
    "type": "function",
    "name": "clear",
    "description": "Clears the current interface and resets the state. Triggered by keyword 'clear'.",
    "parameters": EMPTY_PARAMS
]

let ALL_FUNCTIONS = [EDIT_PROMPT_FUNCTION, SEND_PROMPT_FUNCTION, ACCEPT_FUNCTION, REJECT_FUNCTION, ARROW_UP_FUNCTION, ARROW_DOWN_FUNCTION, ESCAPE_FUNCTION, CLEAR_FUNCTION]

let INSTRUCTIONS = """
Your task is to assist in hands-free voice control for coding using Claude Code CLI.

You will receive a transcription of the user's speech. Based on this transcription, execute exactly ONE of these actions:
   - editPrompt: Optimize the transcribed input into a clear prompt for Claude Code. Consider everything the user has said, without leaving anything out or adding anything new. This is just an optimization step. Treat subsequent transcriptions as potential corrections to the current prompt, not as entirely new prompts.
   - sendPrompt: Send the current prompt to Claude Code
   - accept/reject: Execute accept or reject actions in Claude Code CLI 
   - arrowUp/arrowDown: Navigate in the CLI
   - escape: Cancel current actions
   - clear: Reset the interface and clear the conversation context

Execute the most appropriate function based on the user's intent in the transcription.

Example: If the transcription is "send this prompt to Claude" or just "send", use the sendPrompt function.
"""

import SwiftUI
import Cocoa
import ApplicationServices
import AVFoundation
import Foundation

// Define a structure to hold transcription and action information
struct TranscriptionItem: Identifiable, Hashable {
    var id = UUID()
    var transcription: String
    var action: String?
    var isComplete: Bool = false
    
    static func == (lhs: TranscriptionItem, rhs: TranscriptionItem) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

class AppState: ObservableObject {
    @Published var currentPrompt: String = ""
    @Published var transcriptionItems: [TranscriptionItem] = []
    @Published var eventLogs: [String] = []
    let startTime = Date()
    private var currentDeltaTranscription: String = ""
    private var currentTranscriptionID: UUID? = nil
    
    func updateCurrentPrompt(_ prompt: String) {
        DispatchQueue.main.async {
            self.currentPrompt = prompt
        }
    }
    
    // For complete transcriptions
    func appendCompleteTranscription(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        DispatchQueue.main.async {
            // If we have a current delta transcription in progress with matching ID
            if let id = self.currentTranscriptionID, 
               let index = self.transcriptionItems.firstIndex(where: { $0.id == id }) {
                // Replace it with the complete version
                var item = self.transcriptionItems[index]
                item.transcription = text
                item.isComplete = true
                self.transcriptionItems[index] = item
            } else {
                // Just add a new complete transcription
                self.transcriptionItems.append(TranscriptionItem(transcription: text, isComplete: true))
            }
            
            // Reset the current delta tracking
            self.currentDeltaTranscription = ""
            self.currentTranscriptionID = nil
        }
    }
    
    // For delta transcriptions (partial)
    func appendDeltaTranscription(_ deltaText: String) {
        DispatchQueue.main.async {
            // If we're starting a new transcription
            if self.currentTranscriptionID == nil {
                let newItem = TranscriptionItem(transcription: deltaText, isComplete: false)
                self.currentTranscriptionID = newItem.id
                self.currentDeltaTranscription = deltaText
                self.transcriptionItems.append(newItem)
            } else {
                // We're continuing an existing transcription
                self.currentDeltaTranscription += deltaText
                
                // Find and update the item with the matching ID
                if let id = self.currentTranscriptionID,
                   let index = self.transcriptionItems.firstIndex(where: { $0.id == id }) {
                    var item = self.transcriptionItems[index]
                    item.transcription = self.currentDeltaTranscription
                    self.transcriptionItems[index] = item
                }
            }
        }
    }
    
    // Start a new transcription session (call this when speech starts)
    func startNewTranscription() {
        self.currentDeltaTranscription = ""
        self.currentTranscriptionID = nil
    }
    
    // Add an action to a transcription
    func appendAction(actionName: String) {
        DispatchQueue.main.async {
            // If we have a current transcription ID, use that
            if let id = self.currentTranscriptionID,
               let index = self.transcriptionItems.firstIndex(where: { $0.id == id }) {
                var item = self.transcriptionItems[index]
                item.action = actionName
                self.transcriptionItems[index] = item
            } else if !self.transcriptionItems.isEmpty {
                // Otherwise use the last complete item
                let lastIndex = self.transcriptionItems.count - 1
                var item = self.transcriptionItems[lastIndex]
                item.action = actionName
                self.transcriptionItems[lastIndex] = item
            }
        }
    }
    
    func logEvent(_ source: String, _ event: String) {
        let timeElapsed = Date().timeIntervalSince(startTime)
        let logEntry = "[\(String(format: "%.3f", timeElapsed))s] [\(source)] \(event)"
        
        DispatchQueue.main.async {
            self.eventLogs.append(logEntry)
            
            // Keep only the last 100 events to prevent memory issues
            if self.eventLogs.count > 100 {
                self.eventLogs.removeFirst(self.eventLogs.count - 100)
            }
        }
    }
    
    func clearTranscriptions() {
        DispatchQueue.main.async {
            self.transcriptionItems = []
            self.currentDeltaTranscription = ""
            self.currentTranscriptionID = nil
            self.eventLogs = []
        }
    }
    
}

@main
struct VoiceControlledMacApp: App {
    @StateObject private var appState = AppState()
    var transcriptionApi: TranscriptionAPI!
    var functionCalling: FunctionCalling!
    
    init() {
        let appState = AppState()
        self._appState = StateObject(wrappedValue: appState)
        
        requestMicrophonePermissions()
        
        functionCalling = FunctionCalling(appState: appState)
        transcriptionApi = TranscriptionAPI(appState: appState, functionCalling: functionCalling)
        transcriptionApi.connect()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
    }
    
    func requestMicrophonePermissions() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            if granted {
                print("Microphone permissions granted!")
            } else {
                print("Microphone permissions not granted.")
            }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(spacing: 8) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Prompt:")
                            .font(.headline)
                        
                        Text(appState.currentPrompt.isEmpty ? "(No prompt yet)" : appState.currentPrompt)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    if !appState.transcriptionItems.isEmpty {
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Recent Transcriptions:")
                                .font(.headline)
                            
                            ForEach(appState.transcriptionItems.indices, id: \.self) { index in
                                let item = appState.transcriptionItems[index]
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(index + 1). \(item.transcription)")
                                        .font(.caption)
                                        .padding(.bottom, 1)
                                    
                                    if let action = item.action {
                                        Text("   ↳ Action: \(action)")
                                            .font(.caption)
                                            .foregroundColor(.blue)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Event Logs:")
                            .font(.headline)
                        
                        ScrollView {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(appState.eventLogs.reversed(), id: \.self) { logEntry in
                                    Text(logEntry)
                                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(12)
        .frame(minWidth: 700, minHeight: 600)
    }
}

class FunctionCalling {
    private var appState: AppState
    private var session: URLSession
    private var currentConversation: [[String: Any]] = []
    
    init(appState: AppState) {
        self.appState = appState
        self.session = URLSession(configuration: .default)
        
        // Initialize the conversation with the system instructions
        let systemMessage: [String: Any] = [
            "role": "system",
            "content": INSTRUCTIONS
        ]
        currentConversation.append(systemMessage)
    }
    
    func processTranscription(_ transcript: String) {
        print("Processing transcription for function calling: \(transcript)")
        
        // Add the user's message to the conversation
        let userMessage: [String: Any] = [
            "role": "user",
            "content": transcript
        ]
        currentConversation.append(userMessage)
        
        // Call the responses API with our defined functions
        callResponsesAPI(input: currentConversation)
    }
    
    private func callResponsesAPI(input: [[String: Any]]) {
        let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]!
        let url = URL(string: "https://api.openai.com/v1/responses")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody: [String: Any] = [
            "model": "gpt-4o",
            "input": input,
            "tools": ALL_FUNCTIONS,
            "tool_choice": "required"
        ]
        
        appState.logEvent("FunctionCalling", "Sending request to Responses API")
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
            request.httpBody = jsonData
            
            let task = session.dataTask(with: request) { [weak self] data, response, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("Error calling Responses API: \(error)")
                    self.appState.logEvent("FunctionCalling", "API error: \(error)")
                    return
                }
                
                guard let data = data else {
                    print("No data received from API")
                    self.appState.logEvent("FunctionCalling", "No data received")
                    return
                }
                
                self.appState.logEvent("FunctionCalling", "Response received")
                self.handleResponsesAPIResult(data)
            }
            
            task.resume()
        } catch {
            print("Error creating request: \(error)")
            appState.logEvent("FunctionCalling", "Error creating request: \(error)")
        }
    }
    
    private func handleResponsesAPIResult(_ data: Data) {
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("Failed to parse API response")
                appState.logEvent("FunctionCalling", "Failed to parse API response")
                return
            }
            
            print("Responses API result: \(json)")
            
            // Extract function calls from the output
            if let output = json["output"] as? [[String: Any]] {
                appState.logEvent("FunctionCalling", "Retrieved \(output.count) output items")
                
                for item in output {
                    if let type = item["type"] as? String, type == "function_call",
                       let callID = item["call_id"] as? String,
                       let functionName = item["name"] as? String,
                       let argumentsString = item["arguments"] as? String {
                        
                        appState.logEvent("FunctionCalling", "Function call: \(functionName)")
                        
                        // Handle the function call
                        handleFunctionCall(functionName: functionName, 
                                         argumentsString: argumentsString, 
                                         callID: callID)
                        
                        // Add this call to our conversation
                        currentConversation.append(item)
                    } else {
                        appState.logEvent("FunctionCalling", "Non-function output item: \(item["type"] as? String ?? "unknown")")
                    }
                }
            } else {
                appState.logEvent("FunctionCalling", "No output items in response")
            }
        } catch {
            print("Error processing API response: \(error)")
            appState.logEvent("FunctionCalling", "Error processing API response: \(error)")
        }
    }
    
    private func processEvent(eventType: String, json: [String: Any]) {
        switch eventType {
        case "response.done":
            handleResponseCompletion(json: json)
            
        case "response.output_item.done":
            handleOutputItemCompletion(json: json)
            
        case "error":
            print("Error event: \(json)")
            
        case "response.function_call_arguments.done",
             "response.function_call_arguments.delta",
            "conversation.item.created":
            break
             default:
            break
        }
    }
    
    private func handleResponseCompletion(json: [String: Any]) {
        if let response = json["response"] as? [String: Any],
           let status = response["status"] as? String, status == "failed" {
            print("Response failed: \(response["status_details"] ?? "Unknown error")")
        }
    }
    
    private func handleOutputItemCompletion(json: [String: Any]) {
        guard let item = json["item"] as? [String: Any] else { return }
        
        if let type = item["type"] as? String, type == "function_call",
           let callID = item["call_id"] as? String,
           let functionName = item["name"] as? String,
           let argumentsString = item["arguments"] as? String {
            handleFunctionCall(functionName: functionName, 
                             argumentsString: argumentsString, 
                             callID: callID)
        }
    }

    private func handleFunctionCall(functionName: String, argumentsString: String, callID: String) {
        guard let argumentsData = argumentsString.data(using: .utf8) else {
            print("Failed to convert arguments string to data")
            return
        }
        
        appState.appendAction(actionName: functionName)
        switch functionName {
        case "editPrompt":
            guard let argumentsDict = try? JSONSerialization.jsonObject(with: argumentsData, options: []) as? [String: Any],
                  let prompt = argumentsDict["prompt"] as? String else {
                print("Failed to parse editPrompt arguments")
                let errorOutput = "Error: Failed to parse the prompt argument"
                sendFunctionOutputToModel(callID: callID, output: errorOutput)
                return
            }
            handleEditPrompt(prompt: prompt, callID: callID)
            
        case "sendPrompt":
            handleSendPrompt(callID: callID)
            
        case "accept":
            handleAccept(callID: callID)
            
        case "reject":
            handleReject(callID: callID)
            
        case "arrowUp":
            handleArrowUp(callID: callID)
            
        case "arrowDown":
            handleArrowDown(callID: callID)
            
        case "escape":
            handleEscape(callID: callID)
            
        case "clear":
            handleClear(callID: callID)
            
        default:
            print("Unknown function: \(functionName)")
        }
    }
    
    func sendCommandToClaudeTerminal(_ command: String) throws {
        print("Preparing to inject command into active terminal...")
        
        let script = """
        tell application "Terminal"
            activate
            delay 0.5
            tell application "System Events"
                keystroke "\(command.escapeForAppleScript())"
                delay 0.5
                keystroke return
            end tell
        end tell
        """
        
        let process = Process()
        process.launchPath = "/usr/bin/osascript"
        process.arguments = ["-e", script]
        
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            throw NSError(
                domain: "AppleScriptError",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "AppleScript execution failed with exit code: \(process.terminationStatus)"]
            )
        }
        
        print("Command sent to terminal: \(command)")
        appState.updateCurrentPrompt("")
    }
    
    func handleEditPrompt(prompt: String, callID: String) {
        print("Updating prompt: \(prompt)")
        
        appState.updateCurrentPrompt(prompt)
        
        let output = "Prompt updated successfully"
        sendFunctionOutputToModel(callID: callID, output: output)
    }
    
    func handleSendPrompt(callID: String) {
        if appState.currentPrompt.isEmpty {
            let output = "Error: No prompt available to send"
            sendFunctionOutputToModel(callID: callID, output: output)
            return
        }
        
        print("Sending prompt to Claude: \(appState.currentPrompt)")
        
        do {
            try sendCommandToClaudeTerminal(appState.currentPrompt)
            
            let output = "Prompt sent to Claude"
            sendFunctionOutputToModel(callID: callID, output: output)
        } catch {
            let errorOutput = "Error sending the prompt to Claude Code: \(error.localizedDescription)"
            sendFunctionOutputToModel(callID: callID, output: errorOutput)
            print("Error passed back to model: \(error)")
        }
    }
    
    private func executeKeystrokesInTerminal(_ keystrokeCommands: String, actionName: String, callID: String) {
        print("Executing \(actionName) keystrokes")
        
        do {
            let fullScript = """
            tell application "Terminal"
                activate
                tell application "System Events"
                    \(keystrokeCommands)
                end tell
            end tell
            """
            
            let process = Process()
            process.launchPath = "/usr/bin/osascript"
            process.arguments = ["-e", fullScript]
            
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus != 0 {
                throw NSError(
                    domain: "AppleScriptError",
                    code: Int(process.terminationStatus),
                    userInfo: [NSLocalizedDescriptionKey: "AppleScript execution failed with exit code: \(process.terminationStatus)"]
                )
            }
            
            print("\(actionName) keystrokes executed successfully")
            let output = "\(actionName) command executed successfully"
            sendFunctionOutputToModel(callID: callID, output: output)
        } catch {
            print("Error executing \(actionName) command: \(error)")
            let output = "Error executing \(actionName) command: \(error.localizedDescription)"
            sendFunctionOutputToModel(callID: callID, output: output)
        }
    }
    
    func handleAccept(callID: String) {
        executeKeystrokesInTerminal("key code 36 -- return/enter key", actionName: "accept", callID: callID)
    }
    
    func handleReject(callID: String) {
        let rejectSequence = """
        key code 125 -- down arrow
        delay 0.1
        key code 125 -- down arrow
        delay 0.1
        key code 36 -- return/enter key
        """
        
        executeKeystrokesInTerminal(rejectSequence, actionName: "reject", callID: callID)
    }
    
    func handleArrowUp(callID: String) {
        executeKeystrokesInTerminal("key code 126 -- up arrow key", actionName: "arrow up", callID: callID)
    }
    
    func handleArrowDown(callID: String) {
        executeKeystrokesInTerminal("key code 125 -- down arrow key", actionName: "arrow down", callID: callID)
    }
    
    func handleEscape(callID: String) {
        executeKeystrokesInTerminal("key code 53 -- escape key", actionName: "escape", callID: callID)
    }
    
    func handleClear(callID: String) {
        let clearSequence = """
        key code 53 -- escape key
        delay 0.1
        key code 53 -- escape key
        """
        
        // Clear the conversation context but maintain the system instructions
        currentConversation = []
        
        // Re-add the system instructions
        let systemMessage: [String: Any] = [
            "role": "system",
            "content": INSTRUCTIONS
        ]
        currentConversation.append(systemMessage)
        
        appState.clearTranscriptions()
        appState.logEvent("FunctionCalling", "Cleared conversation context")
        
        executeKeystrokesInTerminal(clearSequence, actionName: "clear", callID: callID)
    }
    
    func sendFunctionOutputToModel(callID: String, output: String) {
        let functionCallOutput: [String: Any] = [
            "type": "function_call_output",
            "call_id": callID,
            "output": output
        ]
        
        // Just add the output to our conversation history
        currentConversation.append(functionCallOutput)
    }
}


let problematicCharacters: [Character] = {
    var chars = [Character]()
    for code in 0..<32 {
        if let scalar = UnicodeScalar(code) {
            chars.append(Character(scalar))
        }
    }
    chars.append("\"")
    chars.append("\\")
    return chars
}()

extension String {
    func escapeForAppleScript() -> String {
        var escaped = self
        for char in problematicCharacters {
            let replacement: String
            switch char {
            case "\"":
                replacement = "\"\""
            case "\\":
                replacement = "\\\\"
            default:
                let code = char.unicodeScalars.first!.value
                replacement = String(format: "\\u{%02X}", code)
            }
            escaped = escaped.replacingOccurrences(of: String(char), with: replacement)
        }
        return escaped
    }
}

class TranscriptionAPI {
    private var webSocketTask: URLSessionWebSocketTask?
    private let audioEngine = AVAudioEngine()
    private let dispatchQueue = DispatchQueue(label: "com.transcription.api")
    private var appState: AppState
    private var functionCalling: FunctionCalling
    private var clientSecret: String?
    
    
    // Alternative initializer that accepts an existing FunctionCalling instance
    init(appState: AppState, functionCalling: FunctionCalling) {
        self.appState = appState
        self.functionCalling = functionCalling
    }
    
    func connect() {
        let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]!
        let sessionsUrlString = "https://api.openai.com/v1/realtime/transcription_sessions"
        
        guard let url = URL(string: sessionsUrlString) else {
            print("Transcription API: Invalid sessions URL.")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody = """
        {
          "input_audio_transcription": {
            "model": "gpt-4o-transcribe"
          },
          "turn_detection": {
            "type": "server_vad",
            "threshold": 0.5,
            "prefix_padding_ms": 300,
            "silence_duration_ms": 500
          },
          "input_audio_noise_reduction": {
            "type": "near_field"
          }
        }
        """
        request.httpBody = requestBody.data(using: .utf8)
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                print("Transcription API: Error creating session: \(error)")
                return
            }
            
            if let data = data, let responseString = String(data: data, encoding: .utf8) {
                print("Transcription API: Session created response: \(responseString)")
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                        if let secretObj = json["client_secret"] as? [String: Any],
                           let secretValue = secretObj["value"] as? String {
                            self.clientSecret = secretValue
                            print("Transcription API: Client secret received")
                            self.connectWebSocket(clientSecret: secretValue)
                        } else {
                            print("Transcription API: No client_secret value in response")
                        }
                    } else {
                        print("Transcription API: Invalid JSON response")
                    }
                } catch {
                    print("Transcription API: Error parsing session response: \(error)")
                }
            }
        }.resume()
    }
    
    private func connectWebSocket(clientSecret: String) {
        let wsUrlString = "wss://api.openai.com/v1/realtime"
        
        guard let url = URL(string: wsUrlString) else {
            print("Transcription API: Invalid WebSocket URL")
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(clientSecret)", forHTTPHeaderField: "Authorization")
        request.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")
        webSocketTask = URLSession(configuration: .default).webSocketTask(with: request)
        webSocketTask!.resume()
        
        print("Transcription API: WebSocket connected")
        setupAudioEngine()
    }
    
    private func send(_ jsonObj: [String: Any]) {
        if let jsonData = try? JSONSerialization.data(withJSONObject: jsonObj),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            webSocketTask!.send(.string(jsonString)) { error in
                if let error = error {
                    print("Transcription API: Error sending json: \(error)")
                }
            }
        }
    }
    
    private func setupAudioEngine() {
        let inputNode = audioEngine.inputNode
        
        let inputFormat = inputNode.inputFormat(forBus: 0)
        print("Transcription API: Input format - \(inputFormat)")
        let desiredSampleRate: Double = 24000.0
        
        let audioFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: desiredSampleRate, channels: 1, interleaved: true)!
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: audioFormat) { buffer, time in
            self.sendAudioChunk(buffer: buffer)
        }
        
        audioEngine.prepare()
        
        do {
            try audioEngine.start()
            print("Transcription API: Audio engine started.")
            receiveResponse()
        } catch {
            print("Transcription API: Audio engine couldn't start: \(error)")
        }
    }
    
    private func sendAudioChunk(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.int16ChannelData?[0] else { return }
        let data = Data(bytes: channelData, count: Int(buffer.frameLength * buffer.format.streamDescription.pointee.mBytesPerFrame))
        let base64Audio = data.base64EncodedString()
        
        let message = """
        {
            "type": "input_audio_buffer.append",
            "audio": "\(base64Audio)"
        }
        """
        
        webSocketTask?.send(.string(message)) { error in
            if let error = error {
                print("Transcription API: Error sending audio chunk: \(error)")
            }
        }
    }
    
    func receiveResponse() {
        webSocketTask?.receive { [self] result in
            defer { self.receiveResponse() }
            
            switch result {
            case .failure(let error):
                print("Transcription API: Error receiving response: \(error)")
                
            case .success(let message):
                guard case .string(let text) = message else {
                    if case .data(let data) = message {
                        print("Transcription API: Received data message of size: \(data.count) bytes.")
                    } else {
                        print("Transcription API: Unknown message type received.")
                    }
                    return
                }
                
                guard let data = text.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                      let eventType = json["type"] as? String else {
                    print("Transcription API: JSON is not of expected format.")
                    return
                }
                print("Transcription API: Event type: \(eventType)")
                print("Transcription API: Full response: \(json)")
                
                switch eventType {
                case "input_audio_buffer.speech_started":
                    print("Transcription API: User started speaking.")
                    self.appState.logEvent("TranscriptionAPI", "User started speaking")
                    // Start a new transcription for this speech segment
                    self.appState.startNewTranscription()
                    
                case "input_audio_buffer.speech_stopped":
                    print("Transcription API: User stopped speaking.")
                    self.appState.logEvent("TranscriptionAPI", "User stopped speaking")
                    
                case "conversation.item.input_audio_transcription.delta":
                    if let delta = json["delta"] as? String {
                       print("Transcription API: Delta transcript: \(delta)")
                       self.appState.appendDeltaTranscription(delta)
                    }
                    
                case "conversation.item.input_audio_transcription.completed":
                    if let transcript = json["transcript"] as? String {
                        print("Transcription API: Complete transcript: \(transcript)")
                        self.appState.logEvent("TranscriptionAPI", "Complete transcript: \(transcript)")
                        self.appState.appendCompleteTranscription(transcript)
                        self.functionCalling.processTranscription(transcript)
                    }
                    
                case "error":
                    print("Transcription API: Error event: \(json)")
                    self.appState.logEvent("TranscriptionAPI", "Error event: \(String(describing: json))")
                    
                default:
                    print("Transcription API: Unhandled event type: \(eventType)")
                    self.appState.logEvent("TranscriptionAPI", "Unhandled event type: \(eventType)")
                }
            }
        }
    }
    
    func disconnect() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        webSocketTask?.cancel()
        print("Transcription API: Disconnected")
    }
}
