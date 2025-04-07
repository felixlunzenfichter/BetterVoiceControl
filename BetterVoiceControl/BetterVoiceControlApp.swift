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

let SEARCH_QUERY_PROPERTY: [String: String] = [
    "type": "string",
    "description": "The web search query to execute"
]

let SEARCH_QUERY_PROPERTIES: [String: [String: String]] = [
    "query": SEARCH_QUERY_PROPERTY
]

let CREATE_SEARCH_QUERY_PARAMS: [String: Any] = [
    "type": "object", 
    "properties": SEARCH_QUERY_PROPERTIES,
    "required": ["query"]
]

let CREATE_SEARCH_QUERY_FUNCTION: [String: Any] = [
    "type": "function",
    "name": "createSearchQuery",
    "description": "Creates a web search query based on user input. The query is displayed on screen for user confirmation.",
    "parameters": CREATE_SEARCH_QUERY_PARAMS
]

let EXECUTE_WEB_SEARCH_FUNCTION: [String: Any] = [
    "type": "function",
    "name": "executeWebSearch",
    "description": "Executes a web search using the current query to find the latest information. Triggered by keyword 'search'.",
    "parameters": EMPTY_PARAMS
]

let ALL_FUNCTIONS = [EDIT_PROMPT_FUNCTION, SEND_PROMPT_FUNCTION, ACCEPT_FUNCTION, REJECT_FUNCTION, ARROW_UP_FUNCTION, ARROW_DOWN_FUNCTION, ESCAPE_FUNCTION, CLEAR_FUNCTION, CREATE_SEARCH_QUERY_FUNCTION, EXECUTE_WEB_SEARCH_FUNCTION]

let INSTRUCTIONS = """
Your task is to assist in hands-free voice control for coding using Claude Code CLI and web search.

You will receive a transcription of the user's speech. Based on this transcription, execute exactly ONE of these actions:
   - editPrompt: Optimize the transcribed input into a clear prompt for Claude Code. Consider everything the user has said, without leaving anything out or adding anything new. This is just an optimization step. Treat subsequent transcriptions as potential corrections to the current prompt, not as entirely new prompts.
   - sendPrompt: Send the current prompt to Claude Code
   - createSearchQuery: Create or update the web search query based on user input
   - executeWebSearch: Execute a web search using the current query to find latest information
   - accept/reject: Execute accept or reject actions in Claude Code CLI 
   - arrowUp/arrowDown: Navigate in the CLI
   - escape: Cancel current actions
   - clear: Reset the interface and clear the conversation context

Execute the most appropriate function based on the user's intent in the transcription.

Examples:
- If the transcription is "send this prompt to Claude" or just "send", use the sendPrompt function.
- If the transcription is "execute search" or "run search" or just "search", use the executeWebSearch function.
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
    @Published var searchQuery: String = ""
    @Published var searchResults: String = ""
    @Published var transcriptionItems: [TranscriptionItem] = []
    @Published var eventLogs: [String] = []
    let startTime = Date()
    private var currentDeltaTranscription: String = ""
    private var currentTranscriptionID: UUID? = nil
    
    func log(_ source: String, _ message: String) {
        let timeElapsed = Date().timeIntervalSince(startTime)
        let logEntry = "[\(String(format: "%.3f", timeElapsed))s] [\(source)] \(message)"
        
        print(logEntry)
        
        DispatchQueue.main.async {
            self.eventLogs.append(logEntry)
            
            // Keep only the last 100 events to prevent memory issues
            if self.eventLogs.count > 100 {
                self.eventLogs.removeFirst(self.eventLogs.count - 100)
            }
        }
    }
    
    func updateCurrentPrompt(_ prompt: String) {
        DispatchQueue.main.async {
            self.currentPrompt = prompt
        }
    }
    
    func updateSearchQuery(_ query: String) {
        DispatchQueue.main.async {
            self.searchQuery = query
        }
    }
    
    func updateSearchResults(_ results: String) {
        DispatchQueue.main.async {
            self.searchResults = results
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
        log(source, event)
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
        AVCaptureDevice.requestAccess(for: .audio) { [self] granted in
            if granted {
                self.appState.log("App", "Microphone permissions granted!")
            } else {
                self.appState.log("App", "Microphone permissions not granted.")
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
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Web Search:")
                            .font(.headline)
                        
                        HStack {
                            Text("Query: ")
                                .font(.subheadline)
                            
                            Text(appState.searchQuery.isEmpty ? "What's happening in tech today?" : appState.searchQuery)
                                .font(.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        
                        if !appState.searchResults.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Results:")
                                    .font(.subheadline)
                                
                                Text(appState.searchResults)
                                    .font(.body)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.top, 4)
                        }
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
        appState.log("FunctionCalling", "Processing transcription: \(transcript)")
        
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
        
        appState.log("FunctionCalling", "Sending request to Responses API")
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
            request.httpBody = jsonData
            
            let task = session.dataTask(with: request) { [weak self] data, response, error in
                guard let self = self else { return }
                
                if let error = error {
                    self.appState.log("FunctionCalling", "Error calling Responses API: \(error)")
                    return
                }
                
                guard let data = data else {
                    self.appState.log("FunctionCalling", "No data received from API")
                    return
                }
                
                self.appState.log("FunctionCalling", "Response received")
                self.handleResponsesAPIResult(data)
            }
            
            task.resume()
        } catch {
            appState.log("FunctionCalling", "Error creating request: \(error)")
        }
    }
    
    private func handleResponsesAPIResult(_ data: Data) {
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                appState.log("FunctionCalling", "Failed to parse API response")
                return
            }
            
            appState.log("FunctionCalling", "Responses API result received")
            
            // Extract function calls from the output
            if let output = json["output"] as? [[String: Any]] {
                appState.log("FunctionCalling", "Retrieved \(output.count) output items")
                
                for item in output {
                    if let type = item["type"] as? String, type == "function_call",
                       let callID = item["call_id"] as? String,
                       let functionName = item["name"] as? String,
                       let argumentsString = item["arguments"] as? String {
                        
                        appState.log("FunctionCalling", "Function call: \(functionName)")
                        
                        // Handle the function call
                        handleFunctionCall(functionName: functionName, 
                                         argumentsString: argumentsString, 
                                         callID: callID)
                        
                        // Add this call to our conversation
                        currentConversation.append(item)
                    } else {
                        appState.log("FunctionCalling", "Non-function output item: \(item["type"] as? String ?? "unknown")")
                    }
                }
            } else {
                appState.log("FunctionCalling", "No output items in response")
            }
        } catch {
            appState.log("FunctionCalling", "Error processing API response: \(error)")
        }
    }
    
    private func processEvent(eventType: String, json: [String: Any]) {
        switch eventType {
        case "response.done":
            handleResponseCompletion(json: json)
            
        case "response.output_item.done":
            handleOutputItemCompletion(json: json)
            
        case "error":
            appState.log("FunctionCalling", "Error event: \(json)")
            
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
            appState.log("FunctionCalling", "Response failed: \(response["status_details"] ?? "Unknown error")")
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
            appState.log("FunctionCalling", "Failed to convert arguments string to data")
            return
        }
        
        appState.appendAction(actionName: functionName)
        switch functionName {
        case "editPrompt":
            guard let argumentsDict = try? JSONSerialization.jsonObject(with: argumentsData, options: []) as? [String: Any],
                  let prompt = argumentsDict["prompt"] as? String else {
                appState.log("FunctionCalling", "Failed to parse editPrompt arguments")
                let errorOutput = "Error: Failed to parse the prompt argument"
                sendFunctionOutputToModel(callID: callID, output: errorOutput)
                return
            }
            handleEditPrompt(prompt: prompt, callID: callID)
            
        case "createSearchQuery":
            guard let argumentsDict = try? JSONSerialization.jsonObject(with: argumentsData, options: []) as? [String: Any],
                  let query = argumentsDict["query"] as? String else {
                appState.log("FunctionCalling", "Failed to parse createSearchQuery arguments")
                let errorOutput = "Error: Failed to parse the query argument"
                sendFunctionOutputToModel(callID: callID, output: errorOutput)
                return
            }
            handleCreateSearchQuery(query: query, callID: callID)
            
        case "executeWebSearch":
            handleExecuteWebSearch(callID: callID)
            
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
            appState.log("FunctionCalling", "Unknown function: \(functionName)")
        }
    }
    
    func sendCommandToClaudeTerminal(_ command: String) throws {
        appState.log("FunctionCalling", "Preparing to inject command into active terminal...")
        
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
        
        appState.log("FunctionCalling", "Command sent to terminal: \(command)")
        appState.updateCurrentPrompt("")
    }
    
    func handleEditPrompt(prompt: String, callID: String) {
        appState.log("FunctionCalling", "Updating prompt: \(prompt)")
        
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
        
        appState.log("FunctionCalling", "Sending prompt to Claude: \(appState.currentPrompt)")
        
        do {
            try sendCommandToClaudeTerminal(appState.currentPrompt)
            
            let output = "Prompt sent to Claude"
            sendFunctionOutputToModel(callID: callID, output: output)
        } catch {
            let errorOutput = "Error sending the prompt to Claude Code: \(error.localizedDescription)"
            sendFunctionOutputToModel(callID: callID, output: errorOutput)
            appState.log("FunctionCalling", "Error passed back to model: \(error)")
        }
    }
    
    private func executeKeystrokesInTerminal(_ keystrokeCommands: String, actionName: String, callID: String) {
        appState.log("FunctionCalling", "Executing \(actionName) keystrokes")
        
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
            
            appState.log("FunctionCalling", "\(actionName) keystrokes executed successfully")
            let output = "\(actionName) command executed successfully"
            sendFunctionOutputToModel(callID: callID, output: output)
        } catch {
            appState.log("FunctionCalling", "Error executing \(actionName) command: \(error)")
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
        
        // Clear the web search results file
        clearWebSearchResultsFile()
        
        // Clear UI elements
        appState.updateSearchQuery("")
        appState.updateSearchResults("")
        appState.clearTranscriptions()
        
        appState.log("FunctionCalling", "Cleared conversation context and search history")
        
        let output = "Interface, conversation context, and search history cleared"
        sendFunctionOutputToModel(callID: callID, output: output)
    }
    
    private func clearWebSearchResultsFile() {
        let fileManager = FileManager.default
        let baseDir = fileManager.homeDirectoryForCurrentUser.path
        let filePath = "\(baseDir)/Documents/BetterVoiceControl-dev/web_search_results"
        
        do {
            // Write an empty string to the file to clear it
            try "".write(toFile: filePath, atomically: true, encoding: .utf8)
            appState.log("WebSearch", "Search history file cleared")
        } catch {
            appState.log("WebSearch", "ERROR: Failed to clear search history file: \(error.localizedDescription)")
        }
    }
    
    func handleCreateSearchQuery(query: String, callID: String) {
        appState.log("FunctionCalling", "Creating search query: \(query)")
        
        appState.updateSearchQuery(query)
        
        let output = "Search query created successfully"
        sendFunctionOutputToModel(callID: callID, output: output)
    }
    
    func handleExecuteWebSearch(callID: String) {
        if appState.searchQuery.isEmpty {
            let output = "Error: No search query available to execute"
            sendFunctionOutputToModel(callID: callID, output: output)
            return
        }
        
        appState.log("FunctionCalling", "Executing web search: \(appState.searchQuery)")
        
        // Execute web search using the Responses API
        executeWebSearch(query: appState.searchQuery) { [weak self] results in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.appState.updateSearchResults(results)
                
                // Append search results to a file
                self.appendToSearchResultsFile(query: self.appState.searchQuery, results: results)
                
                let output = "Web search completed successfully"
                self.sendFunctionOutputToModel(callID: callID, output: output)
            }
        }
    }
    
    private func appendToSearchResultsFile(query: String, results: String) {
        let fileManager = FileManager.default
        let baseDir = fileManager.homeDirectoryForCurrentUser.path
        let filePath = "\(baseDir)/Documents/BetterVoiceControl-dev/web_search_results"
        
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let content = """
        
        --------- SEARCH: \(timestamp) ---------
        Query: \(query)
        
        Results:
        \(results)
        
        """
        
        self.appState.log("WebSearch", "Saving results to \(filePath)")
        
        if let fileHandle = FileHandle(forWritingAtPath: filePath) {
            do {
                fileHandle.seekToEndOfFile()
                if let data = content.data(using: .utf8) {
                    fileHandle.write(data)
                } else {
                    self.appState.log("WebSearch", "ERROR: Failed to convert content to data")
                }
                fileHandle.closeFile()
            } catch {
                self.appState.log("WebSearch", "ERROR: Failed to write to existing file: \(error.localizedDescription)")
            }
        } else {
            do {
                try content.write(toFile: filePath, atomically: true, encoding: .utf8)
            } catch {
                self.appState.log("WebSearch", "ERROR: Failed to create file: \(error.localizedDescription)")
            }
        }
    }
    
    private func executeWebSearch(query: String, completion: @escaping (String) -> Void) {
        let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]!
        let url = URL(string: "https://api.openai.com/v1/responses")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody: [String: Any] = [
            "model": "gpt-4o",
            "tools": [["type": "web_search_preview"]],
            "input": query
        ]
        
        appState.log("WebSearch", "Sending search request to API")
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
            request.httpBody = jsonData
            
            let task = session.dataTask(with: request) { [weak self] data, response, error in
                guard let self = self else { return }
                
                if let error = error {
                    self.appState.log("WebSearch", "API error: \(error)")
                    completion("Error: \(error.localizedDescription)")
                    return
                }
                
                guard let data = data else {
                    self.appState.log("WebSearch", "No data received")
                    completion("Error: No data received from search")
                    return
                }
                
                self.appState.log("WebSearch", "Search response received")
                
                do {
                    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        self.appState.log("WebSearch", "Failed to parse API response")
                        completion("Error: Failed to parse search results")
                        return
                    }
                    
                    // Extract the search results text
                    if let output = json["output"] as? [[String: Any]] {
                        for item in output {
                            if let type = item["type"] as? String, type == "message",
                               let content = item["content"] as? [[String: Any]],
                               let firstContent = content.first,
                               let resultText = firstContent["text"] as? String {
                                
                                completion(resultText)
                                return
                            }
                        }
                    }
                    
                    // If we couldn't extract the text
                    completion("Search completed, but couldn't extract results")
                } catch {
                    self.appState.log("WebSearch", "Error processing API response: \(error)")
                    completion("Error processing search results: \(error.localizedDescription)")
                }
            }
            
            task.resume()
        } catch {
            self.appState.log("WebSearch", "Error creating request: \(error)")
            completion("Error: \(error.localizedDescription)")
        }
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
        // First, replace double quotes with single quotes for Claude Code compatibility
        var cleaned = self.replacingOccurrences(of: "\"", with: "'")
        
        // Then do the regular AppleScript escaping
        var escaped = cleaned
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

extension UInt16 {
    var bytes: Data {
        var value = self.littleEndian
        return Data(bytes: &value, count: MemoryLayout<UInt16>.size)
    }
}

extension UInt32 {
    var bytes: Data {
        var value = self.littleEndian
        return Data(bytes: &value, count: MemoryLayout<UInt32>.size)
    }
}

class TranscriptionAPI {
    private var webSocketTask: URLSessionWebSocketTask?
    private let audioEngine = AVAudioEngine()
    private let dispatchQueue = DispatchQueue(label: "com.transcription.api")
    private var appState: AppState
    private var functionCalling: FunctionCalling
    private var clientSecret: String?
    private var audioBuffers: [Data] = []
    private var audioPlayer: AVAudioPlayer?
    private var isSpeaking: Bool = false
    private var enableAudioPlayback: Bool = false  // Set to true to enable audio playback
    
    // Alternative initializer that accepts an existing FunctionCalling instance
    init(appState: AppState, functionCalling: FunctionCalling) {
        self.appState = appState
        self.functionCalling = functionCalling
    }
    
    // Convert audio buffer to the target format (24000 Hz, 16-bit PCM, mono)
    private func convertToTargetAudioFormat(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        // Check if we can directly access the input buffer's channel data
        if buffer.format.commonFormat == .pcmFormatInt16 && buffer.int16ChannelData == nil {
            appState.log("AudioConverter", "WARNING: Buffer is in int16 format but channel data is nil")
        }
        
        // Target sample rate is 24000 Hz to match the recording format
        let targetSampleRate: Double = 24000.0
        
        // If already at 24000 Hz with accessible int16 channel data, return as is
        if buffer.format.sampleRate == targetSampleRate && 
           buffer.format.commonFormat == .pcmFormatInt16 && 
           buffer.int16ChannelData != nil {
            return buffer
        }
        
        // Create a two-step conversion if needed
        // If not already in a PCM format that's easily convertible to int16, first convert to float32
        var intermediateBuffer = buffer
        if buffer.format.commonFormat != .pcmFormatInt16 && buffer.format.commonFormat != .pcmFormatFloat32 {
            let floatFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, 
                                            sampleRate: buffer.format.sampleRate,
                                            channels: buffer.format.channelCount, 
                                            interleaved: false)!
            
            guard let floatConverter = AVAudioConverter(from: buffer.format, to: floatFormat) else {
                appState.log("AudioConverter", "ERROR: Failed to create intermediate converter, using original buffer")
                return buffer
            }
            
            guard let floatBuffer = AVAudioPCMBuffer(pcmFormat: floatFormat, frameCapacity: buffer.frameLength) else {
                appState.log("AudioConverter", "ERROR: Failed to create intermediate buffer, using original buffer")
                return buffer
            }
            
            var floatError: NSError?
            floatConverter.convert(to: floatBuffer, error: &floatError) { _, status in
                status.pointee = .haveData
                return buffer
            }
            
            if let error = floatError {
                appState.log("AudioConverter", "ERROR: Intermediate conversion failed: \(error), using original buffer")
                return buffer
            }
            
            intermediateBuffer = floatBuffer
        }
        
        // Create target format - 24000 Hz, mono, 16-bit PCM, interleaved
        let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, 
                                        sampleRate: targetSampleRate, 
                                        channels: 1, 
                                        interleaved: true)!
        
        // Create final converter
        guard let converter = AVAudioConverter(from: intermediateBuffer.format, to: targetFormat) else {
            appState.log("AudioConverter", "ERROR: Failed to create target converter, using original buffer")
            return buffer
        }
        
        // Calculate new buffer size based on ratio of sample rates and round up
        let ratio = targetSampleRate / intermediateBuffer.format.sampleRate
        let newFrameCapacity = AVAudioFrameCount(ceil(Double(intermediateBuffer.frameLength) * ratio))
        
        // Create output buffer
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: newFrameCapacity) else {
            appState.log("AudioConverter", "ERROR: Failed to create output buffer, using original buffer")
            return buffer
        }
        
        // Convert to target format
        var error: NSError?
        let finalConversion = converter.convert(to: outputBuffer, error: &error) { _, status in
            status.pointee = .haveData
            return intermediateBuffer
        }
        
        if error != nil {
            appState.log("AudioConverter", "ERROR: Final conversion failed: \(error?.localizedDescription ?? "unknown error"), using original buffer")
            return buffer
        }
        
        // Verify output buffer has data and int16 channel data is accessible
        if outputBuffer.frameLength == 0 {
            appState.log("AudioConverter", "ERROR: Output buffer has zero frames, using original buffer")
            return buffer
        }
        
        if outputBuffer.int16ChannelData == nil {
            appState.log("AudioConverter", "ERROR: Output buffer has nil int16ChannelData, using original buffer")
            return buffer
        }
        
        return outputBuffer
    }
    
    func connect() {
        let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]!
        let sessionsUrlString = "https://api.openai.com/v1/realtime/transcription_sessions"
        
        guard let url = URL(string: sessionsUrlString) else {
            appState.log("TranscriptionAPI", "Invalid sessions URL.")
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
                self.appState.log("TranscriptionAPI", "Error creating session: \(error)")
                return
            }
            
            if let data = data, let responseString = String(data: data, encoding: .utf8) {
                self.appState.log("TranscriptionAPI", "Session created response: \(responseString)")
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                        if let secretObj = json["client_secret"] as? [String: Any],
                           let secretValue = secretObj["value"] as? String {
                            self.clientSecret = secretValue
                            self.appState.log("TranscriptionAPI", "Client secret received")
                            self.connectWebSocket(clientSecret: secretValue)
                        } else {
                            self.appState.log("TranscriptionAPI", "No client_secret value in response")
                        }
                    } else {
                        self.appState.log("TranscriptionAPI", "Invalid JSON response")
                    }
                } catch {
                    self.appState.log("TranscriptionAPI", "Error parsing session response: \(error)")
                }
            }
        }.resume()
    }
    
    private func connectWebSocket(clientSecret: String) {
        let wsUrlString = "wss://api.openai.com/v1/realtime"
        
        guard let url = URL(string: wsUrlString) else {
            appState.log("TranscriptionAPI", "Invalid WebSocket URL")
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(clientSecret)", forHTTPHeaderField: "Authorization")
        request.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")
        webSocketTask = URLSession(configuration: .default).webSocketTask(with: request)
        webSocketTask!.resume()
        
        appState.log("TranscriptionAPI", "WebSocket connected")
        setupAudioEngine()
    }
    
    private func send(_ jsonObj: [String: Any]) {
        if let jsonData = try? JSONSerialization.data(withJSONObject: jsonObj),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            webSocketTask!.send(.string(jsonString)) { [weak self] error in
                guard let self = self else { return }
                if let error = error {
                    self.appState.log("TranscriptionAPI", "Error sending json: \(error)")
                }
            }
        }
    }
    
    private func setupAudioEngine() {
        let inputNode = audioEngine.inputNode
        
        // Use native input format - no format conversion during recording
        let inputFormat = inputNode.inputFormat(forBus: 0)
        appState.log("TranscriptionAPI", """
        Input format details:
        - Sample rate: \(inputFormat.sampleRate) Hz
        - Channels: \(inputFormat.channelCount)
        - Format ID: \(inputFormat.streamDescription.pointee.mFormatID)
        - Format flags: \(inputFormat.streamDescription.pointee.mFormatFlags)
        - Bytes per packet: \(inputFormat.streamDescription.pointee.mBytesPerPacket)
        - Frames per packet: \(inputFormat.streamDescription.pointee.mFramesPerPacket)
        - Bytes per frame: \(inputFormat.streamDescription.pointee.mBytesPerFrame)
        - Channels per frame: \(inputFormat.streamDescription.pointee.mChannelsPerFrame)
        - Bits per channel: \(inputFormat.streamDescription.pointee.mBitsPerChannel)
        """)
        
        // Install tap with native format
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { buffer, time in
            self.sendAudioChunk(buffer: buffer)
        }
        
        audioEngine.prepare()
        
        do {
            try audioEngine.start()
            appState.log("TranscriptionAPI", "Audio engine started.")
            receiveResponse()
        } catch {
            appState.log("TranscriptionAPI", "Audio engine couldn't start: \(error)")
        }
    }
    
    private func sendAudioChunk(buffer: AVAudioPCMBuffer) {
        // Convert input buffer to target format for API (24000 Hz, mono, 16-bit PCM)
        var buffer = convertToTargetAudioFormat(buffer)
        
        guard let channelData = buffer.int16ChannelData?[0] else {
            appState.log("AudioProcessing", "ERROR: Failed to get channel data from buffer")
            return
        }
        
        let dataSize = Int(buffer.frameLength * buffer.format.streamDescription.pointee.mBytesPerFrame)
        let data = Data(bytes: channelData, count: dataSize)
        
        // Store audio buffer for playback testing only when speaking is active and playback is enabled
        if isSpeaking && enableAudioPlayback {
            audioBuffers.append(data)
        }
        
        let base64Audio = data.base64EncodedString()
        
        let message = """
        {
            "type": "input_audio_buffer.append",
            "audio": "\(base64Audio)"
        }
        """
        
        webSocketTask?.send(.string(message)) { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                self.appState.log("AudioProcessing", "ERROR: Failed to send audio chunk: \(error)")
            }
        }
    }
    
    func receiveResponse() {
        webSocketTask?.receive { [self] result in
            defer { self.receiveResponse() }
            
            switch result {
            case .failure(let error):
                self.appState.log("TranscriptionAPI", "Error receiving response: \(error)")
                
            case .success(let message):
                guard case .string(let text) = message else {
                    if case .data(let data) = message {
                        self.appState.log("TranscriptionAPI", "Received data message of size: \(data.count) bytes.")
                    } else {
                        self.appState.log("TranscriptionAPI", "Unknown message type received.")
                    }
                    return
                }
                
                guard let data = text.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                      let eventType = json["type"] as? String else {
                    self.appState.log("TranscriptionAPI", "JSON is not of expected format.")
                    return
                }
                // Only log certain event types to avoid console spam
                if eventType != "conversation.item.input_audio_transcription.delta" {
                    self.appState.log("TranscriptionAPI", "Event type: \(eventType)")
                }
                
                switch eventType {
                case "input_audio_buffer.speech_started":
                    self.appState.log("TranscriptionAPI", "User started speaking")
                    // Set speaking flag to true
                    self.isSpeaking = true
                    // Start a new transcription for this speech segment
                    self.appState.startNewTranscription()
                    
                case "input_audio_buffer.speech_stopped":
                    self.appState.log("TranscriptionAPI", "User stopped speaking")
                    // Set speaking flag to false
                    self.isSpeaking = false
                    // Only call playback function if audio playback is enabled
                    if self.enableAudioPlayback {
                        self.playbackRecordedAudio()
                    }
                    
                case "conversation.item.input_audio_transcription.delta":
                    if let delta = json["delta"] as? String {
                       self.appState.appendDeltaTranscription(delta)
                    }
                    
                case "conversation.item.input_audio_transcription.completed":
                    if let transcript = json["transcript"] as? String {
                        self.appState.log("TranscriptionAPI", "Complete transcript: \(transcript)")
                        self.appState.appendCompleteTranscription(transcript)
                        self.functionCalling.processTranscription(transcript)
                    }
                    
                case "error":
                    self.appState.log("TranscriptionAPI", "Error event: \(json)")
                    
                default:
                    self.appState.log("TranscriptionAPI", "Unhandled event type: \(eventType)")
                }
            }
        }
    }
    
    private func playbackRecordedAudio() {
        guard !audioBuffers.isEmpty else {
            return
        }
        
        // Calculate total size
        let totalSize = audioBuffers.reduce(0) { $0 + $1.count }
        guard totalSize > 0 else {
            return
        }
        
        // Create a temporary WAV file for playback
        let fileManager = FileManager.default
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let tempFileURL = documentsPath.appendingPathComponent("playback_test.pcm")
        
        // Combine all audio data
        var combinedData = Data()
        for buffer in audioBuffers {
            combinedData.append(buffer)
        }
        
        do {
            // Write raw PCM data to file
            try combinedData.write(to: tempFileURL)
            
            // Create audio file with correct format
            let outputURL = documentsPath.appendingPathComponent("playback_test.wav")
            
            // Create WAV file header structure
            let sampleRate: UInt32 = 24000
            let channelCount: UInt16 = 1
            let bitsPerSample: UInt16 = 16
            let byteRate = sampleRate * UInt32(channelCount * bitsPerSample / 8)
            let blockAlign = channelCount * bitsPerSample / 8
            
            var header = Data()
            
            // RIFF chunk
            header.append(contentsOf: "RIFF".utf8)
            let fileSize = UInt32(combinedData.count + 36)
            header.append(fileSize.littleEndian.bytes)
            header.append(contentsOf: "WAVE".utf8)
            
            // fmt chunk
            header.append(contentsOf: "fmt ".utf8)
            header.append(UInt32(16).littleEndian.bytes)
            header.append(UInt16(1).littleEndian.bytes)  // PCM format
            header.append(channelCount.littleEndian.bytes)
            header.append(sampleRate.littleEndian.bytes)
            header.append(byteRate.littleEndian.bytes)
            header.append(blockAlign.littleEndian.bytes)
            header.append(bitsPerSample.littleEndian.bytes)
            
            // data chunk
            header.append(contentsOf: "data".utf8)
            header.append(UInt32(combinedData.count).littleEndian.bytes)
            
            // Combine header and PCM data
            var wavData = Data()
            wavData.append(header)
            wavData.append(combinedData)
            
            // Write WAV file
            try wavData.write(to: outputURL)
            
            // Play using AVAudioPlayer
            audioPlayer = try AVAudioPlayer(contentsOf: outputURL)
            if audioPlayer == nil {
                appState.log("AudioPlayback", "ERROR: Failed to create audio player")
                return
            }
            
            audioPlayer?.prepareToPlay()
            if !(audioPlayer?.play() ?? false) {
                appState.log("AudioPlayback", "ERROR: Failed to start audio playback")
                return
            }
            
        } catch {
            appState.log("AudioPlayback", "ERROR: Failed to create or play audio: \(error)")
            // Keep buffers if playback fails
            return
        }
        
        // Buffers successfully played, clear them
        audioBuffers.removeAll()
    }
    
    func disconnect() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        webSocketTask?.cancel()
        appState.log("TranscriptionAPI", "Disconnected")
    }
}
