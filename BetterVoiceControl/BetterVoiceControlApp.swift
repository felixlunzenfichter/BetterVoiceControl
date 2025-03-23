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

let TRANSCRIPTION_PROPERTY: [String: String] = [
    "type": "string",
    "description": "The exact verbatim transcription of what the user said, word-for-word, without any added context or interpretation."
]

let TRANSCRIPTION_PROPERTIES: [String: [String: String]] = [
    "text": TRANSCRIPTION_PROPERTY
]

let TRANSCRIPTION_PARAMS: [String: Any] = [
    "type": "object", 
    "properties": TRANSCRIPTION_PROPERTIES,
    "required": ["text"]
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

let UPDATE_TRANSCRIPTION_FUNCTION: [String: Any] = [
    "type": "function",
    "name": "updateTranscription",
    "description": "Provides a verbatim, word-for-word transcription of exactly what the user said without adding any conversational context, interpretation, or modification.",
    "parameters": TRANSCRIPTION_PARAMS
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

let ALL_FUNCTIONS = [EDIT_PROMPT_FUNCTION, SEND_PROMPT_FUNCTION, UPDATE_TRANSCRIPTION_FUNCTION, ACCEPT_FUNCTION, REJECT_FUNCTION, ARROW_UP_FUNCTION, ARROW_DOWN_FUNCTION, ESCAPE_FUNCTION, CLEAR_FUNCTION]

let INSTRUCTIONS = """
Your task is to assist in hands-free voice control for coding using Claude Code CLI. Follow this strict workflow:

1. First, ALWAYS provide a verbatim transcription of what the user said using the updateTranscription function, so the user can verify you understood correctly.

2. After the transcription is confirmed, execute ONE of these actions based on the user's intent:
   - editPrompt: Optimize the voice input into a clear, contextual prompt for Claude Code
   - sendPrompt: Send the current prompt to Claude Code
   - accept/reject: Execute accept or reject actions in Claude Code CLI 
   - arrowUp/arrowDown: Navigate in the CLI
   - escape: Cancel current actions
   - clear: Reset the interface

Never respond with text - only use the available functions. Always transcribe first, then execute exactly one action.
"""

import SwiftUI
import Cocoa
import ApplicationServices
import AVFoundation
import Foundation


class AppState: ObservableObject {
    @Published var currentPrompt: String = ""
    @Published var transcriptionHistory: [String] = []
    
    func updateCurrentPrompt(_ prompt: String) {
        DispatchQueue.main.async {
            self.currentPrompt = prompt
        }
    }
    
    func appendTranscription(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        DispatchQueue.main.async {
            self.transcriptionHistory.append(text)
        }
    }
    
    func appendDeltaTranscription(_ deltaText: String) {
        DispatchQueue.main.async {
            if self.transcriptionHistory.isEmpty {
                self.transcriptionHistory.append(deltaText)
            } else {
                let lastIndex = self.transcriptionHistory.count - 1
                let currentText = self.transcriptionHistory[lastIndex]
                self.transcriptionHistory[lastIndex] = currentText + deltaText
            }
        }
    }
    
    func appendAction(actionName: String) {
        DispatchQueue.main.async {
            if !self.transcriptionHistory.isEmpty {
                let lastIndex = self.transcriptionHistory.count - 1
                let currentTranscription = self.transcriptionHistory[lastIndex]
                self.transcriptionHistory[lastIndex] = "\(currentTranscription) → \(actionName)"
            }
        }
    }
    
    func clearTranscriptions() {
        DispatchQueue.main.async {
            self.transcriptionHistory = []
        }
    }
    
}

@main
struct VoiceControlledMacApp: App {
    @StateObject private var appState = AppState()
    var transcriptionApi: TranscriptionAPI!
    
    init() {
        let appState = AppState()
        self._appState = StateObject(wrappedValue: appState)
        
        requestMicrophonePermissions()
        
        transcriptionApi = TranscriptionAPI(appState: appState)
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
                    
                    if !appState.transcriptionHistory.isEmpty {
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Recent Transcriptions:")
                                .font(.headline)
                            
                            ForEach(appState.transcriptionHistory.indices, id: \.self) { index in
                                Text("\(index + 1). \(appState.transcriptionHistory[index])")
                                    .font(.caption)
                                    .padding(.vertical, 2)
                            }
                        }
                    }
                    
                }
                .padding(.vertical, 4)
            }
        }
        .padding(12)
        .frame(minWidth: 700, minHeight: 500)
    }
}

class OpenAIRealtimeAPI {
    private var webSocketTask: URLSessionWebSocketTask?
    private let audioEngine = AVAudioEngine()
    private let dispatchQueue = DispatchQueue(label: "com.openai.realtimeapi")
    private var appState: AppState
    
    init(appState: AppState) {
        self.appState = appState
    }
    
    func connect() {
        let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]!
        let urlString = "wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview-2024-12-17"
        
        guard let url = URL(string: urlString) else {
            print("Invalid URL.")
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")
        
        webSocketTask = URLSession(configuration: .default).webSocketTask(with: request)
        webSocketTask!.resume()
        defineFunction()
        setInstructions()
        
        print("Connected to OpenAI Realtime API.")
        setupAudioEngine()
    }
    
    
    func send(_ jsonObj: [String: Any]) {
        if let jsonData = try? JSONSerialization.data(withJSONObject: jsonObj),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            webSocketTask!.send(.string(jsonString)) { error in
                if let error = error {
                    fatalError("Error sending json: \(error)")
                }
            }
        }
    }
    
    func setInstructions() {
        send([
            "type": "session.update",
            "session": [
                "instructions": INSTRUCTIONS,
                "turn_detection": [
                         "type": "server_vad",
                         "threshold": 0.5,
                         "prefix_padding_ms": 300,
                         "silence_duration_ms": 500,
                         "create_response": false
                     ],
            ]
        ])
    }
    
    func defineFunction() {
        let session: [String: Any] = [
            "tools": ALL_FUNCTIONS,
            "tool_choice": "required"
        ]
        
        let functionPayload: [String: Any] = [
            "type": "session.update",
            "session": session
        ]
        
        send(functionPayload)
    }
    
    func setupAudioEngine() {
        let inputNode = audioEngine.inputNode
        
        let inputFormat = inputNode.inputFormat(forBus: 0)
        print(inputFormat)
        let desiredSampleRate: Double = 24000.0
        
        let audioFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: desiredSampleRate, channels: 1, interleaved: true)!
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: audioFormat) { buffer, time in
            self.sendAudioChunk(buffer: buffer)
        }
        
        audioEngine.prepare()
        
        do {
            try audioEngine.start()
            print("Audio engine started.")
            receiveResponse()
        } catch {
            print("Audio engine couldn't start: \(error)")
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
                print("Error sending audio chunk: \(error)")
            }
        }
    }
    
    func receiveResponse() {
        webSocketTask?.receive { [self] result in
            defer { self.receiveResponse() }
            
            switch result {
            case .failure(let error):
                fatalError("Error receiving response: \(error)")
                
            case .success(let message):
                guard case .string(let text) = message else {
                    if case .data(let data) = message {
                        print("Received data message of size: \(data.count) bytes.")
                    } else {
                        print("Unknown message type received.")
                    }
                    return
                }
                
                guard let data = text.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                      let eventType = json["type"] as? String else {
                    print("Error: JSON is not of expected format.")
                    return
                }
                print("event type: \(eventType)")
                
                processEvent(eventType: eventType, json: json)
            }
        }
    }
    
    private func processEvent(eventType: String, json: [String: Any]) {
        switch eventType {
        case "response.done":
            handleResponseCompletion(json: json)
            
        case "input_audio_buffer.speech_started":
            handleSpeechStarted()
            
        case "input_audio_buffer.speech_stopped":
            handleSpeechEnded()
            
        case "response.output_item.done":
            handleOutputItemCompletion(json: json)
            
        case "response.audio_transcript.delta":
            if let transcript = json["text"] as? String {
                print("Transcript delta: \(transcript)")
            }
            
        case "response.audio.delta":
            fatalError("this should not happen")
            
        case "error":
            resetConnection()
            print("Error event: \(json)")
            
        case "response.function_call_arguments.done":
            if let name = json["name"] as? String, name == "updateTranscription" {
                executeAction()
            }
            
        case "response.function_call_arguments.delta",
             "conversation.item.created":
            break
            
        default:
            break
        }
    }
    
    private func executeAction() {
        print("executeAction has been called")
        
        let availableFunctions = [EDIT_PROMPT_FUNCTION, SEND_PROMPT_FUNCTION, ACCEPT_FUNCTION, REJECT_FUNCTION, ARROW_UP_FUNCTION, ARROW_DOWN_FUNCTION, ESCAPE_FUNCTION, CLEAR_FUNCTION]
        
        self.send([
            "event_id": UUID().uuidString,
            "type": "response.create",
            "response": [
                "tools": availableFunctions,
                "tool_choice": "required",
            ]
        ])
    }
    
    private func handleResponseCompletion(json: [String: Any]) {
        if let response = json["response"] as? [String: Any],
           let status = response["status"] as? String, status == "failed" {
            print("Response failed: \(response["status_details"] ?? "Unknown error")")
        }
    }
    
    private func handleSpeechStarted() {
        print("User started speaking.")
    }
    
    private func handleSpeechEnded() {
        print("User speech ended. Processing transcription...")
        
        send([
            "event_id": UUID().uuidString,
            "type": "response.create",
            "response": [
                "tools": [UPDATE_TRANSCRIPTION_FUNCTION],
                "tool_choice": "required"
            ]
        ])
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
        } else if let contentArray = item["content"] as? [[String: Any]],
                  let content = contentArray.first,
                  let transcript = content["transcript"] as? String {
            print("Complete transcript: \(transcript)")
            appState.appendTranscription(transcript)
        }
    }

    private func handleFunctionCall(functionName: String, argumentsString: String, callID: String) {
        guard let argumentsData = argumentsString.data(using: .utf8) else {
            print("Failed to convert arguments string to data")
            return
        }
        
        if functionName != "updateTranscription" {
            appState.appendAction(actionName: functionName)
        }
        
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
            
        case "updateTranscription":
            guard let argumentsDict = try? JSONSerialization.jsonObject(with: argumentsData, options: []) as? [String: Any],
                  let text = argumentsDict["text"] as? String else {
                print("Failed to parse updateTranscription arguments")
                let errorOutput = "Error: Failed to parse the text argument"
                sendFunctionOutputToModel(callID: callID, output: errorOutput)
                return
            }
            let output = "Transcription appended"
            appState.appendTranscription(text)
            sendFunctionOutputToModel(callID: callID, output: output)

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
        
        executeKeystrokesInTerminal(clearSequence, actionName: "clear", callID: callID)
    }
    
    private func resetConnection() {
            if self.audioEngine.isRunning {
                self.audioEngine.inputNode.removeTap(onBus: 0)
                self.audioEngine.stop()
            }
        webSocketTask?.cancel()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.appState.clearTranscriptions()
                self.appState.updateCurrentPrompt("")
                self.connect()
                print("Connection reset complete")
            }
    }
    
    func sendFunctionOutputToModel(callID: String, output: String) {
        let payload: [String: Any] = [
            "type": "conversation.item.create",
            "item": [
                "type": "function_call_output",
                "call_id": callID,
                "output": output
            ]
        ]
        
        send(payload)
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
    
    private var clientSecret: String?
    
    init(appState: AppState) {
        self.appState = appState
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
            print("Transcription API: Invalid WebSocket URL.")
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
                    
                case "input_audio_buffer.speech_stopped":
                    print("Transcription API: User stopped speaking.")
                    
                case "conversation.item.input_audio_transcription.delta":
                    if let delta = json["delta"] as? String {
                       print("Transcription API: Delta transcript: \(delta)")
                        self.appState.appendDeltaTranscription(delta)
                    }
                    
                case "conversation.item.input_audio_transcription.completed":
                    if let transcript = json["transcript"] as? String {
                        print("Transcription API: Complete transcript: \(transcript)")
                    }
                    
                case "error":
                    print("Transcription API: Error event: \(json)")
                    
                default:
                    print("Transcription API: Unhandled event type: \(eventType)")
                }
            }
        }
    }
    
    func disconnect() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        webSocketTask?.cancel()
        print("Transcription API: Disconnected.")
    }
}
