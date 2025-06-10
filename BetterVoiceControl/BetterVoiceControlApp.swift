let PROMPT_PROPERTY: [String: String] = [
    "type": "string",
    "description": "The verbatim prompt to be displayed and eventually sent to Claude Code."
]
let SET_PROMPT_PROPERTIES: [String: [String: String]] = [
    "prompt": PROMPT_PROPERTY
]
let SET_PROMPT_PARAMS: [String: Any] = [
    "type": "object", 
    "properties": SET_PROMPT_PROPERTIES,
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
    "description": "Sets the prompt from user speech with minimal editing - only fix spelling mistakes and basic errors while preserving the user's exact words and phrasing. Handle corrections from subsequent speech.",
    "parameters": SET_PROMPT_PARAMS
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
let SET_CONTEXT_FUNCTION: [String: Any] = [
    "type": "function",
    "name": "setContextBoundary",
    "description": "Sets context to include last N transcriptions. Triggered by phrases like 'include last 5', 'include up to number 7', or 'include all'.",
    "parameters": [
        "type": "object",
        "properties": [
            "boundary": [
                "type": "integer",
                "description": "The number of recent transcriptions to include. Use 999 for 'all'."
            ]
        ],
        "required": ["boundary"]
    ]
]
let ALL_FUNCTIONS = [EDIT_PROMPT_FUNCTION, SEND_PROMPT_FUNCTION, ACCEPT_FUNCTION, REJECT_FUNCTION, ARROW_UP_FUNCTION, ARROW_DOWN_FUNCTION, ESCAPE_FUNCTION, SET_CONTEXT_FUNCTION]
let INSTRUCTIONS = """
You are the voice control interface for Claude Code CLI, a powerful AI coding assistant. The user can ONLY communicate through speech - no keyboard or mouse input is available. You are their sole control window to interact with Claude Code.

CONTEXT: Claude Code is an AI assistant that helps with software engineering tasks. It can read files, write code, run commands, create commits, and manage entire codebases. The user directs Claude Code through prompts that you help compose and send.

Your role is to execute exactly ONE action based on speech transcription:

PROMPT MANAGEMENT:
- editPrompt: Convert speech to prompts with minimal editing. Preserve exact user intent and technical terminology. Handle corrections like "I meant X instead of Y".
- sendPrompt: Transmit the completed prompt to Claude Code for execution.

CLAUDE CODE NAVIGATION:
- accept: Confirm Claude Code's proposed actions (user says "accept", never "except")
- reject: Decline Claude Code's proposals and request alternatives
- arrowUp/arrowDown: Navigate through Claude Code's interface options
- escape: Cancel current Claude Code operations

CONTEXT MANAGEMENT:
- setContextBoundary: Control how many recent transcriptions are included in prompts
- "Include last 5" → Sets context to include only the 5 most recent transcriptions
- "Include up to number 10" → Includes transcriptions 1-10
- "Include all" → Includes all transcriptions (boundary = 999)

EXECUTION PRINCIPLES:
- The user has no other way to control their system - you are their complete interface
- Preserve technical accuracy in prompts (file paths, function names, commands)
- Recognize coding context and terminology
- Respond immediately to navigation commands
- Maintain conversation flow with Claude Code

Examples:
- "Edit the main function in app.py" → editPrompt with exact technical details
- "Send this to Claude" → sendPrompt
- "Accept that change" → accept
- "Go up" or "arrow up" → arrowUp
- "Include last 5" → setContextBoundary
"""
import SwiftUI
import Cocoa
import ApplicationServices
import AVFoundation
import Foundation
import CoreAudio
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
    @Published var contextBoundary: Int = Int.max
    @Published var currentOperation: String? = nil
    @Published var currentOperationStatus: String = ""
    let startTime = Date()
    private var currentDeltaTranscription: String = ""
    private var currentTranscriptionID: UUID? = nil
    private var isEvaluatingContext: Bool = false
    
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
    
    
    func appendCompleteTranscription(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        DispatchQueue.main.async {
            if let id = self.currentTranscriptionID, 
               let index = self.transcriptionItems.firstIndex(where: { $0.id == id }) {
                // Replace it with the complete version
                self.transcriptionItems[index].transcription = text
                self.transcriptionItems[index].isComplete = true
            } else {
                // Just add a new complete transcription
                self.transcriptionItems.append(TranscriptionItem(transcription: text, isComplete: true))
            }
            
            // Reset the current delta tracking
            self.currentDeltaTranscription = ""
            self.currentTranscriptionID = nil
            
            // Don't update context here - let action completion handle it
        }
    }
    
    func updateContextAfterAction() {
        DispatchQueue.main.async {
            // Just trigger context evaluation - no need to update numbers as they're computed dynamically
            self.triggerContextEvaluation()
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
                    // Direct update to avoid conflicts with context management
                    self.transcriptionItems[index].transcription = self.currentDeltaTranscription
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
    
    
    func keepLastEventLogs(_ count: Int) {
        DispatchQueue.main.async {
            if self.eventLogs.count > count {
                let lastLogs = Array(self.eventLogs.suffix(count))
                self.eventLogs = lastLogs
            }
        }
    }
    
    func getContextNumber(for item: TranscriptionItem) -> Int {
        guard let index = transcriptionItems.firstIndex(where: { $0.id == item.id }) else { return 1 }
        // Newest (last in array) gets number 1, oldest gets highest number
        return transcriptionItems.count - index
    }
    
    func isIncludedInContext(_ item: TranscriptionItem) -> Bool {
        let contextNumber = getContextNumber(for: item)
        return contextNumber <= contextBoundary
    }
    
    func getIncludedTranscriptions() -> [TranscriptionItem] {
        // Return included transcriptions sorted oldest first for conversation building
        return transcriptionItems
            .filter { isIncludedInContext($0) }
            .sorted { getContextNumber(for: $0) > getContextNumber(for: $1) }
    }
    
    func getDisplayTranscriptions() -> [TranscriptionItem] {
        // Create items with their context numbers for display
        let itemsWithNumbers = transcriptionItems.map { item in
            (item: item, number: getContextNumber(for: item), included: isIncludedInContext(item))
        }
        
        // Sort by context number (ascending = newest first)
        let sorted = itemsWithNumbers.sorted { $0.number < $1.number }
        
        let included = sorted.filter { $0.included }.map { $0.item }
        let excluded = sorted.filter { !$0.included }.map { $0.item }
        
        // Take only the 3 most recent excluded
        let recentExcluded = Array(excluded.prefix(3))
        
        return included + recentExcluded
    }
    
    func setContextBoundary(_ boundary: Int) {
        DispatchQueue.main.async {
            self.contextBoundary = boundary
            self.log("ContextManager", "Context boundary manually set to \(boundary)")
        }
    }
    
    func setCurrentOperation(_ operation: String, status: String = "processing") {
        DispatchQueue.main.async {
            self.currentOperation = operation
            self.currentOperationStatus = status
        }
    }
    
    func clearCurrentOperation() {
        DispatchQueue.main.async {
            self.currentOperation = nil
            self.currentOperationStatus = ""
        }
    }
    
    func triggerContextEvaluation() {
        guard !isEvaluatingContext else { return }
        
        Task {
            await evaluateContextBoundary()
        }
    }
    
    private func evaluateContextBoundary() async {
        isEvaluatingContext = true
        defer { isEvaluatingContext = false }
        
        guard transcriptionItems.count > 5 else { return }
        
        await MainActor.run {
            self.setCurrentOperation("Evaluating context boundary", status: "analyzing")
        }
        
        let included = getIncludedTranscriptions()
        let excluded = transcriptionItems.filter { !isIncludedInContext($0) }
        let additionalContext = Array(excluded.prefix(3))
        
        let contextToEvaluate = included + additionalContext
        
        do {
            let newBoundary = try await callContextEvaluationAPI(transcriptions: contextToEvaluate)
            await MainActor.run {
                self.contextBoundary = newBoundary
                self.log("ContextManager", "Context boundary automatically updated to \(newBoundary)")
                self.setCurrentOperation("Context boundary updated", status: "complete")
            }
        } catch {
            log("ContextManager", "Error evaluating context: \(error)")
            await MainActor.run {
                self.setCurrentOperation("Context evaluation failed", status: "error")
            }
        }
        
        // Clear operation after a short delay
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        await MainActor.run {
            self.clearCurrentOperation()
        }
    }
    
    private func callContextEvaluationAPI(transcriptions: [TranscriptionItem]) async throws -> Int {
        let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]!
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let transcriptionTexts = transcriptions.map { item in
            let number = getContextNumber(for: item)
            return "[\(number)] \(item.transcription)"
        }.joined(separator: "\n")
        
        let systemPrompt = """
        You are a context management system. Given a numbered list of transcriptions (newest = 1), determine the optimal cutoff point for including context.
        Consider conversation flow, topic changes, and relevance. Return ONLY a single number indicating the highest number to include.
        For example, if transcriptions 1-7 should be included, return "7".
        """
        
        let requestBody: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": transcriptionTexts]
            ],
            "temperature": 0.3,
            "max_tokens": 10
        ]
        
        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
        request.httpBody = jsonData
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String,
              let boundary = Int(content.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw NSError(domain: "ContextEvaluation", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse API response"])
        }
        
        return boundary
    }
    
}
class AppManager: ObservableObject {
    @Published var appState = AppState()
    var transcriptionApi: TranscriptionAPI!
    private var functionCalling: FunctionCalling!
    private var isRestarting = false
    
    init() {
        setupComponents()
    }
    
    private func setupComponents() {
        functionCalling = FunctionCalling(appState: appState)
        transcriptionApi = TranscriptionAPI(appState: appState, functionCalling: functionCalling)
        
        // Set the restart handler to restart components
        functionCalling.setRestartHandler { [weak self] in
            self?.restartComponents()
        }
        
        transcriptionApi.connect()
    }
    
    func restartComponents() {
        guard !isRestarting else {
            appState.log("AppManager", "Restart already in progress, ignoring request")
            return
        }
        
        isRestarting = true
        appState.log("AppManager", "Performing complete internal restart due to issues")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.appState.log("AppManager", "Stopping all components...")
            
            // Stop and cleanup TranscriptionAPI
            self.transcriptionApi.disconnect()
            
            // Reset function calling state
            self.functionCalling.resetConversation()
            
            // Keep last 10 event logs
            self.appState.keepLastEventLogs(10)
            self.appState.updateCurrentPrompt("")
            
            // Wait a moment then restart everything
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                self.appState.log("AppManager", "Restarting all components...")
                self.setupComponents()
                self.isRestarting = false
            }
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
@main
struct VoiceControlledMacApp: App {
    @StateObject private var appManager = AppManager()
    
    init() {
        let manager = AppManager()
        self._appManager = StateObject(wrappedValue: manager)
        manager.requestMicrophonePermissions()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appManager.appState)
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
                            
                            let visibleTranscriptions = appState.getDisplayTranscriptions()
                            
                            ForEach(visibleTranscriptions.indices, id: \.self) { index in
                                let item = visibleTranscriptions[index]
                                let contextNumber = appState.getContextNumber(for: item)
                                let isIncluded = appState.isIncludedInContext(item)
                                
                                HStack(alignment: .top, spacing: 6) {
                                    Circle()
                                        .fill(isIncluded ? Color.green : Color.red)
                                        .frame(width: 8, height: 8)
                                        .padding(.top, 4)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 4) {
                                            Text("[\(contextNumber)]")
                                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                                .foregroundColor(isIncluded ? .green : .red)
                                            
                                            Text(item.transcription)
                                                .font(.caption)
                                                .foregroundColor(isIncluded ? .primary : .secondary)
                                        }
                                        
                                        if let action = item.action {
                                            Text("   ↳ Action: \(action)")
                                                .font(.caption)
                                                .foregroundColor(.blue)
                                        }
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                    
                    if appState.currentOperation != nil {
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Current Operation:")
                                .font(.headline)
                            
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .frame(width: 16, height: 16)
                                
                                Text(appState.currentOperation ?? "")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.blue)
                                
                                Text("(\(appState.currentOperationStatus))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
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
    var restartHandler: (() -> Void)?
    
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
    
    func setRestartHandler(_ handler: @escaping () -> Void) {
        self.restartHandler = handler
    }
    
    func resetConversation() {
        appState.log("FunctionCalling", "Resetting conversation state")
        currentConversation.removeAll()
        
        // Cancel any ongoing URL session tasks
        session.invalidateAndCancel()
        session = URLSession(configuration: .default)
        
        // Re-add the system instructions
        let systemMessage: [String: Any] = [
            "role": "system",
            "content": INSTRUCTIONS
        ]
        currentConversation.append(systemMessage)
    }
    
    func processTranscription(_ transcript: String) {
        appState.log("FunctionCalling", "Processing transcription: \(transcript)")
        
        // Rebuild conversation from included transcriptions only
        rebuildConversationFromIncludedTranscriptions()
        
        // Add the current user message
        let userMessage: [String: Any] = [
            "role": "user",
            "content": transcript
        ]
        currentConversation.append(userMessage)
        
        // Call the responses API with our defined functions
        callResponsesAPI(input: currentConversation)
    }
    
    private func rebuildConversationFromIncludedTranscriptions() {
        // Start fresh with system message
        currentConversation = []
        
        let systemMessage: [String: Any] = [
            "role": "system",
            "content": INSTRUCTIONS
        ]
        currentConversation.append(systemMessage)
        
        // Add only included transcriptions
        let includedTranscriptions = appState.getIncludedTranscriptions()
        
        for item in includedTranscriptions.reversed() {
            let userMessage: [String: Any] = [
                "role": "user",
                "content": item.transcription
            ]
            currentConversation.append(userMessage)
            
            if let action = item.action {
                let assistantMessage: [String: Any] = [
                    "role": "assistant",
                    "content": "Executed: \(action)"
                ]
                currentConversation.append(assistantMessage)
            }
        }
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
                    self.restartHandler?()
                    return
                }
                
                guard let data = data else {
                    self.appState.log("FunctionCalling", "No data received from API")
                    self.restartHandler?()
                    return
                }
                
                self.appState.log("FunctionCalling", "Response received")
                self.handleResponsesAPIResult(data)
            }
            
            task.resume()
        } catch {
            appState.log("FunctionCalling", "Error creating request: \(error)")
            restartHandler?()
        }
    }
    
    private func handleResponsesAPIResult(_ data: Data) {
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                appState.log("FunctionCalling", "Failed to parse API response")
                restartHandler?()
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
            restartHandler?()
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
        appState.setCurrentOperation(functionName, status: "executing")
        
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
            
        case "setContextBoundary":
            guard let argumentsDict = try? JSONSerialization.jsonObject(with: argumentsData, options: []) as? [String: Any],
                  let boundary = argumentsDict["boundary"] as? Int else {
                appState.log("FunctionCalling", "Failed to parse setContextBoundary arguments")
                let errorOutput = "Error: Failed to parse the boundary argument"
                sendFunctionOutputToModel(callID: callID, output: errorOutput)
                return
            }
            handleSetContextBoundary(boundary: boundary, callID: callID)
            
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
            restartHandler?()
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
            restartHandler?()
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
    
    func handleSetContextBoundary(boundary: Int, callID: String) {
        let actualBoundary = boundary >= 999 ? Int.max : boundary
        appState.setContextBoundary(actualBoundary)
        
        let output = actualBoundary == Int.max ? 
            "Context set to include all transcriptions" : 
            "Context set to include last \(actualBoundary) transcriptions"
        
        sendFunctionOutputToModel(callID: callID, output: output)
    }
    
    func sendFunctionOutputToModel(callID: String, output: String) {
        let functionCallOutput: [String: Any] = [
            "type": "function_call_output",
            "call_id": callID,
            "output": output
        ]
        
        // Just add the output to our conversation history
        currentConversation.append(functionCallOutput)
        
        // Update operation status
        appState.setCurrentOperation(appState.currentOperation ?? "", status: "completed")
        
        // Clear operation after a short delay and update context
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.appState.clearCurrentOperation()
            self.appState.updateContextAfterAction()
        }
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
        let cleaned = self.replacingOccurrences(of: "\"", with: "'")
        
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
    private var currentInputDevice: AudioDeviceID?
    private var audioSessionObserver: NSObjectProtocol?
    
    // Alternative initializer that accepts an existing FunctionCalling instance
    init(appState: AppState, functionCalling: FunctionCalling) {
        self.appState = appState
        self.functionCalling = functionCalling
        setupAudioSessionObserver()
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
                appState.log("AudioConverter", "ERROR: Failed to create intermediate converter - restarting app")
                restartApplication()
                return buffer
            }
            
            guard let floatBuffer = AVAudioPCMBuffer(pcmFormat: floatFormat, frameCapacity: buffer.frameLength) else {
                appState.log("AudioConverter", "ERROR: Failed to create intermediate buffer - restarting app")
                restartApplication()
                return buffer
            }
            
            var floatError: NSError?
            floatConverter.convert(to: floatBuffer, error: &floatError) { _, status in
                status.pointee = .haveData
                return buffer
            }
            
            if let error = floatError {
                appState.log("AudioConverter", "ERROR: Intermediate conversion failed: \(error) - restarting app")
                restartApplication()
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
            appState.log("AudioConverter", "ERROR: Failed to create target converter - restarting app")
            restartApplication()
            return buffer
        }
        
        // Calculate new buffer size based on ratio of sample rates and round up
        let ratio = targetSampleRate / intermediateBuffer.format.sampleRate
        let newFrameCapacity = AVAudioFrameCount(ceil(Double(intermediateBuffer.frameLength) * ratio))
        
        // Create output buffer
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: newFrameCapacity) else {
            appState.log("AudioConverter", "ERROR: Failed to create output buffer - restarting app")
            restartApplication()
            return buffer
        }
        
        // Convert to target format
        var error: NSError?
        _ = converter.convert(to: outputBuffer, error: &error) { _, status in
            status.pointee = .haveData
            return intermediateBuffer
        }
        
        if error != nil {
            appState.log("AudioConverter", "ERROR: Final conversion failed: \(error?.localizedDescription ?? "unknown error") - restarting app")
            restartApplication()
            return buffer
        }
        
        // Verify output buffer has data and int16 channel data is accessible
        if outputBuffer.frameLength == 0 {
            appState.log("AudioConverter", "ERROR: Output buffer has zero frames - restarting app")
            restartApplication()
            return buffer
        }
        
        if outputBuffer.int16ChannelData == nil {
            appState.log("AudioConverter", "ERROR: Output buffer has nil int16ChannelData - restarting app")
            restartApplication()
            return buffer
        }
        
        return outputBuffer
    }
    
    private func setupAudioSessionObserver() {
        audioSessionObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: audioEngine,
            queue: .main
        ) { [weak self] notification in
            self?.handleAudioEngineConfigurationChange()
        }
        
        getCurrentInputDevice()
        
        let propertyListenerProc: AudioObjectPropertyListenerProc = { _, _, _, userData in
            guard let userData = userData else { return noErr }
            let transcriptionAPI = Unmanaged<TranscriptionAPI>.fromOpaque(userData).takeUnretainedValue()
            transcriptionAPI.handleAudioDeviceChange()
            return noErr
        }
        
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        AudioObjectAddPropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            propertyListenerProc,
            Unmanaged.passUnretained(self).toOpaque()
        )
    }
    
    private func getCurrentInputDevice() {
        var deviceID: AudioDeviceID = 0
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &deviceID
        )
        
        if status == noErr {
            currentInputDevice = deviceID
            appState.log("AudioSession", "Current input device ID: \(deviceID)")
        }
    }
    
    private func handleAudioEngineConfigurationChange() {
        appState.log("AudioEngine", "Audio engine configuration changed - restarting app")
        restartApplication()
    }
    
    private func handleAudioDeviceChange() {
        let previousDevice = currentInputDevice
        getCurrentInputDevice()
        
        if let previous = previousDevice, let current = currentInputDevice, previous != current {
            appState.log("AudioSession", "Input device changed from \(previous) to \(current) - restarting app")
            restartApplication()
        } else if previousDevice == nil && currentInputDevice != nil {
            appState.log("AudioSession", "Input device became available - restarting app")
            restartApplication()
        }
    }
    
    private func restartApplication() {
        appState.log("TranscriptionAPI", "Triggering complete internal restart")
        functionCalling.restartHandler?()
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
            "model": "gpt-4o-transcribe",
            "language": "en",
            "prompt": "Voice commands for Claude Code: accept, reject, send prompt, clear, arrow up, arrow down, escape. User says 'accept' to confirm actions, never 'except'."
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
        
        do {
            try setupAudioEngine()
        } catch {
            appState.log("TranscriptionAPI", "Failed to setup audio engine: \(error)")
            restartApplication()
        }
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
    
    private func setupAudioEngine() throws {
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
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, time in
            guard let self = self else { return }
            self.sendAudioChunk(buffer: buffer)
        }
        
        audioEngine.prepare()
        
        do {
            try audioEngine.start()
            appState.log("TranscriptionAPI", "Audio engine started.")
            receiveResponse()
        } catch {
            appState.log("TranscriptionAPI", "Audio engine couldn't start: \(error)")
            throw error
        }
    }
    
    private func sendAudioChunk(buffer: AVAudioPCMBuffer) {
        // Convert input buffer to target format for API (24000 Hz, mono, 16-bit PCM)
        let buffer = convertToTargetAudioFormat(buffer)
        
        guard let channelData = buffer.int16ChannelData?[0] else {
            appState.log("AudioProcessing", "ERROR: Failed to get channel data from buffer - restarting app")
            restartApplication()
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
                self.appState.log("AudioProcessing", "WebSocket error detected - restarting app")
                self.restartApplication()
            }
        }
    }
    
    func receiveResponse() {
        webSocketTask?.receive { [self] result in
            defer { self.receiveResponse() }
            
            switch result {
            case .failure(let error):
                self.appState.log("TranscriptionAPI", "Error receiving response: \(error)")
                self.appState.log("TranscriptionAPI", "WebSocket connection lost - restarting app")
                self.restartApplication()
                return
                
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
                if eventType != "conversation.item.input_audio_transcription.delta" && 
                   eventType != "input_audio_buffer.append" {
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
                        // Don't log deltas - too much clutter
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
                    self.restartApplication()
                    
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
        appState.log("TranscriptionAPI", "Disconnecting and cleaning up state")
        
        if let observer = audioSessionObserver {
            NotificationCenter.default.removeObserver(observer)
            audioSessionObserver = nil
        }
        
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        AudioObjectRemovePropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            { _, _, _, _ in return noErr },
            Unmanaged.passUnretained(self).toOpaque()
        )
        
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        
        webSocketTask?.cancel()
        webSocketTask = nil
        
        // Reset all internal state
        resetInternalState()
        
        appState.log("TranscriptionAPI", "Disconnected and state cleared")
    }
    
    private func resetInternalState() {
        appState.log("TranscriptionAPI", "Resetting internal state")
        
        // Clear audio state
        audioBuffers.removeAll()
        audioPlayer = nil
        isSpeaking = false
        currentInputDevice = nil
        clientSecret = nil
        
        // Reset the audio engine completely
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.reset()
    }
}
