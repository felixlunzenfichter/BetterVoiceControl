let INSTRUCTIONS = """
Your task is to be a prompt generator in a coding application designed for hands-free computing. Listen to the user’s voice input, interpret it carefully, and transform it into a clear, context-rich natural language prompt targeted at a coding agent called Claude Code. Apply optimal prompt engineering techniques to refine the user’s instructions before sending the final prompt to Claude Code for execution. Don't leave anything out and don't add anything that hasn't been mentioned. Just optimize the structure.
"""

import SwiftUI
import Cocoa
import ApplicationServices
import AVFoundation
import Foundation

class AppState: ObservableObject {
    @Published var isRecording: Bool = false
    @Published var currentPrompt: String = ""
    
    func updateCurrentPrompt(_ prompt: String) {
        DispatchQueue.main.async {
            self.currentPrompt = prompt
        }
    }
}

@main
struct VoiceControlledMacApp: App {
    @StateObject private var appState = AppState()
    let api: OpenAIRealtimeAPI
    
    init() {
        let appState = AppState()
        self._appState = StateObject(wrappedValue: appState)
        self.api = OpenAIRealtimeAPI(appState: appState)
        
        requestMicrophonePermissions()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .onAppear {
                    api.connect()
                }
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
        VStack {
            Text(appState.isRecording ? "●" : "○")
            
            if !appState.currentPrompt.isEmpty {
                Text(appState.currentPrompt)
            }
        }
    }
}

class OpenAIRealtimeAPI {
    private var webSocketTask: URLSessionWebSocketTask?
    private let audioEngine = AVAudioEngine()
    private let dispatchQueue = DispatchQueue(label: "com.openai.realtimeapi")
    private let audioPlayer = AVAudioPlayerNode()
    private var appState: AppState
    
    init(appState: AppState) {
        self.appState = appState
    }
    
    func connect() {
        let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]!
        let urlString = "wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview-2024-10-01"
        
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
                    print("Error sending json: \(error)")
                    return
                }
            }
        }
    }
    
    func setInstructions() {
        send([
            "type": "session.update",
            "session": [
                "instructions": INSTRUCTIONS,
                "tool_choice": "required" // Force function calling only, disable automatic text responses
            ]
        ])
    }
    
    func defineFunction() {
        // Define the editPrompt function parameters
        let promptProperty: [String: String] = [
            "type": "string",
            "description": "The refined or new prompt to be displayed and eventually sent to Claude Code."
        ]
        
        let editPromptProperties: [String: [String: String]] = [
            "prompt": promptProperty
        ]
        
        let editPromptParams: [String: Any] = [
            "type": "object", 
            "properties": editPromptProperties,
            "required": ["prompt"]
        ]
        
        // Define the sendPrompt function parameters
        let sendPromptParams: [String: Any] = [
            "type": "object",
            "properties": [String: Any](),
            "required": [String]()
        ]
        
        // No parameters needed for the keystroke functions
        let emptyParams: [String: Any] = [
            "type": "object",
            "properties": [String: Any](),
            "required": [String]()
        ]
        
        // Create the function definitions
        let editPromptFunction: [String: Any] = [
            "type": "function",
            "name": "editPrompt",
            "description": "Refines or replaces the current prompt based on user input. The updated prompt is displayed on screen in real-time.",
            "parameters": editPromptParams
        ]
        
        let sendPromptFunction: [String: Any] = [
            "type": "function",
            "name": "sendPrompt",
            "description": "Transmits the final, refined prompt to the Claude Code coding agent for execution.",
            "parameters": sendPromptParams
        ]
        
        let acceptFunction: [String: Any] = [
            "type": "function",
            "name": "accept",
            "description": "Executes a return/enter key press in Terminal for accepting current action in Claude Code CLI. Triggered by keyword 'accept'.",
            "parameters": emptyParams
        ]
        
        let rejectFunction: [String: Any] = [
            "type": "function",
            "name": "reject",
            "description": "Executes a sequence for rejecting current action in Claude Code CLI. Triggered by keyword 'reject'.",
            "parameters": emptyParams
        ]
        
        let arrowUpFunction: [String: Any] = [
            "type": "function",
            "name": "arrowUp",
            "description": "Executes an up arrow key press in Terminal for navigating in Claude Code CLI. Triggered by keyword 'arrow up'.",
            "parameters": emptyParams
        ]
        
        let arrowDownFunction: [String: Any] = [
            "type": "function",
            "name": "arrowDown",
            "description": "Executes a down arrow key press in Terminal for navigating in Claude Code CLI. Triggered by keyword 'arrow down'.",
            "parameters": emptyParams
        ]
        
        let escapeFunction: [String: Any] = [
            "type": "function",
            "name": "escape",
            "description": "Executes an escape key press in Terminal for canceling actions in Claude Code CLI. Triggered by keyword 'escape'.",
            "parameters": emptyParams
        ]
        
        // Create the complete payload
        let tools = [editPromptFunction, sendPromptFunction, acceptFunction, rejectFunction, arrowUpFunction, arrowDownFunction, escapeFunction]
        let session: [String: Any] = ["tools": tools]
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
        audioEngine.attach(audioPlayer)
        let desiredSampleRate: Double = 24000.0
        
        let audioFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: desiredSampleRate, channels: 1, interleaved: true)!
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: audioFormat) { buffer, time in
            self.sendAudioChunk(buffer: buffer)
        }
        let playbackFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: desiredSampleRate, channels: 1, interleaved: false)!
        
        audioEngine.connect(audioPlayer, to: audioEngine.mainMixerNode, format: playbackFormat)
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
        
        DispatchQueue.main.async {
            self.appState.isRecording = true
        }
        
        webSocketTask?.send(.string(message)) { error in
            if let error = error {
                print("Error sending audio chunk: \(error)")
            }
        }
    }
    
    func receiveResponse() {
        webSocketTask?.receive { [self] result in
            switch result {
            case .failure(let error):
                print("Error receiving audio response: \(error)")
                // Try to reconnect or inform user
                DispatchQueue.main.async {
                    self.appState.isRecording = false
                }
            case .success(let message):
                switch message {
                case .string(let text):
                    if let data = text.data(using: .utf8) {
                        do {
                            guard let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
                                print("Error: JSON is not of expected format.")
                                self.receiveResponse()
                                return
                            }
                            
                            if let eventType = json["type"] as? String {
                                switch eventType {
                                case "response.done":
                                    DispatchQueue.main.async {
                                        self.appState.isRecording = false
                                    }
                                    if let response = json["response"] as? [String: Any],
                                       let status = response["status"] as? String, status == "failed" {
                                        print("Response failed: \(response["status_details"] ?? "Unknown error")")
                                    }
                                case "response.function_call_arguments.delta":
                                    break
                                case "response.function_call_arguments.done":
                                    break
                                case "input_audio_buffer.speech_started":
                                    print("User started speaking.")
                                    DispatchQueue.main.async {
                                        self.appState.isRecording = true
                                    }
                                    stopAudioPlayback()
                                case "input_audio_buffer.speech_ended":
                                    print("User stopped speaking.")
                                case "response.output_item.done":
                                    guard let item = json["item"] as? [String: Any] else { break }
                                    
                                    if let type = item["type"] as? String, type == "function_call",
                                       let callID = item["call_id"] as? String,
                                       let functionName = item["name"] as? String,
                                       let argumentsString = item["arguments"] as? String,
                                       let argumentsData = argumentsString.data(using: .utf8) {
                                        
                                        // Route to the appropriate function handler
                                        switch functionName {
                                        case "editPrompt":
                                            guard let argumentsDict = try? JSONSerialization.jsonObject(with: argumentsData, options: []) as? [String: Any],
                                                  let prompt = argumentsDict["prompt"] as? String else {
                                                print("Failed to parse editPrompt arguments")
                                                let errorOutput = "Error: Failed to parse the prompt argument"
                                                sendFunctionOutputToModel(callID: callID, output: errorOutput)
                                                self.receiveResponse()
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
                                        default:
                                            fatalError("Unknown function: \(functionName)")
                                        }
                                    } else if let contentArray = item["content"] as? [[String: Any]],
                                              let content = contentArray.first,
                                              let transcript = content["transcript"] as? String {
                                        print("[[Model Text Output]] \(transcript)")
                                    }
                                case "response.audio_transcript.delta":
                                    break
                                case "response.audio.delta":
                                    if let delta = json["delta"] as? String {
                                        playReceivedAudio(base64String: delta)
                                    }
                                case "conversation.item.created":
                                    break
                                case "error":
                                    print("Error: \(json)")
                                default:
                                    // print("Unhandled event type: \(eventType)")
                                    break
                                }
                            }
                            self.receiveResponse()
                        } catch {
                            print("Error parsing JSON: \(error)")
                            self.receiveResponse()
                        }
                    }
                case .data(let data):
                    print("Received data message of size: \(data.count) bytes.")
                    self.receiveResponse()
                @unknown default:
                    print("Unknown message type received.")
                    self.receiveResponse()
                }
            }
        }
    }
    
    func stopAudioPlayback() {
        dispatchQueue.async {
            if self.audioPlayer.isPlaying {
                self.audioPlayer.stop()
                print("Audio playback stopped and buffers cleared.")
            }
        }
    }

    func playReceivedAudio(base64String: String) {
        guard let audioBuffer = base64ToAudioBuffer(base64String: base64String) else {
            print("Failed to create audio buffer.")
            return
        }
        
        dispatchQueue.async {
            if !self.audioEngine.isRunning {
                do {
                    try self.audioEngine.start()
                    print("Playback engine restarted.")
                } catch {
                    print("Playback engine couldn't start: \(error)")
                    return
                }
            }
            
            self.audioPlayer.scheduleBuffer(audioBuffer, at: nil, options: [], completionHandler: nil)
            
            if !self.audioPlayer.isPlaying {
                self.audioPlayer.play()
                print("Audio playback started.")
            }
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
        
        // Check if the process exited successfully
        if process.terminationStatus != 0 {
            throw NSError(
                domain: "AppleScriptError",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "AppleScript execution failed with exit code: \(process.terminationStatus)"]
            )
        }
        
        print("Command sent to terminal: \(command)")
        // Clear the prompt after sending
        appState.updateCurrentPrompt("")
    }
    
    // Handle the editPrompt function call from the model
    func handleEditPrompt(prompt: String, callID: String) {
        print("Updating prompt: \(prompt)")
        
        // Update the prompt in the AppState
        appState.updateCurrentPrompt(prompt)
        
        // Send function output back to model
        let output = "Prompt updated successfully"
        sendFunctionOutputToModel(callID: callID, output: output)
    }
    
    // Handle the sendPrompt function call from the model
    func handleSendPrompt(callID: String) {
        if appState.currentPrompt.isEmpty {
            let output = "Error: No prompt available to send"
            sendFunctionOutputToModel(callID: callID, output: output)
            return
        }
        
        print("Sending prompt to Claude: \(appState.currentPrompt)")
        
        // Send the prompt directly to the terminal
        do {
            try sendCommandToClaudeTerminal(appState.currentPrompt)
            
            // Send success feedback to model
            let output = "Prompt sent to Claude"
            sendFunctionOutputToModel(callID: callID, output: output)
        } catch {
            // Send error feedback to model
            let errorOutput = "Error sending the prompt to Claude Code: \(error.localizedDescription)"
            sendFunctionOutputToModel(callID: callID, output: errorOutput)
            print("Error passed back to model: \(error)")
        }
    }
    
    // Helper method to execute keystrokes using AppleScript - handles all error management
    private func executeKeystrokesInTerminal(_ keystrokeCommands: String, actionName: String, callID: String) {
        print("Executing \(actionName) keystrokes")
        
        do {
            // Wrap the keystrokes in the complete AppleScript
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
    
    // Function to handle accept (return key press)
    func handleAccept(callID: String) {
        executeKeystrokesInTerminal("key code 36 -- return/enter key", actionName: "accept", callID: callID)
    }
    
    // Function to handle reject (down arrow twice then enter)
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
    
    // Function to handle arrow up
    func handleArrowUp(callID: String) {
        executeKeystrokesInTerminal("key code 126 -- up arrow key", actionName: "arrow up", callID: callID)
    }
    
    // Function to handle arrow down
    func handleArrowDown(callID: String) {
        executeKeystrokesInTerminal("key code 125 -- down arrow key", actionName: "arrow down", callID: callID)
    }
    
    // Function to handle escape
    func handleEscape(callID: String) {
        executeKeystrokesInTerminal("key code 53 -- escape key", actionName: "escape", callID: callID)
    }
    
    // Helper method to send function call outputs back to the model
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

// Audio Processing Functions
func base64ToAudioBuffer(base64String: String, sampleRate: Double = 24000, channels: AVAudioChannelCount = 1) -> AVAudioPCMBuffer? {
    guard let pcmData = Data(base64Encoded: base64String) else {
        print("Error decoding base64 string")
        return nil
    }
    
    let float32Data = pcm16ToFloat32(pcmData: pcmData)
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: channels, interleaved: false)!
    let frameCapacity = AVAudioFrameCount(float32Data.count)
    
    guard let audioBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else {
        print("Error creating audio buffer")
        return nil
    }
    
    audioBuffer.frameLength = frameCapacity
    for i in 0..<Int(audioBuffer.frameLength) {
        audioBuffer.floatChannelData?.pointee[i] = float32Data[i]
    }
    
    return audioBuffer
}

func pcm16ToFloat32(pcmData: Data) -> [Float] {
    return pcmData.withUnsafeBytes { rawBuffer -> [Float] in
        let ptr = rawBuffer.baseAddress!.assumingMemoryBound(to: Int16.self)
        let count = pcmData.count / MemoryLayout<Int16>.size
        return (0..<count).map { Float(ptr[$0]) / 32768.0 }
    }
}


// Build a complete list of problematic characters
let problematicCharacters: [Character] = {
    var chars = [Character]()
    // Include all ASCII control characters (U+0000 to U+001F)
    for code in 0..<32 {
        if let scalar = UnicodeScalar(code) {
            chars.append(Character(scalar))
        }
    }
 chars.append("\"")
    chars.append("\\")
    return chars
}()

// Function that escapes all problematic characters for AppleScript
extension String {
    func escapeForAppleScript() -> String {
        var escaped = self
        for char in problematicCharacters {
            let replacement: String
            switch char {
            case "\"":
                // AppleScript escapes double quotes by doubling them
                replacement = "\"\""
            case "\\":
                // Escape backslashes by doubling them
                replacement = "\\\\"
            default:
                // Escape control characters as Unicode escape sequences
                let code = char.unicodeScalars.first!.value
                replacement = String(format: "\\u{%02X}", code)
            }
            escaped = escaped.replacingOccurrences(of: String(char), with: replacement)
        }
        return escaped
    }
}
