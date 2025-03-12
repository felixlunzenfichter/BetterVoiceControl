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
    @Published var transcriptionHistory: [String] = []
    @Published var isProcessingPrompt: Bool = false
    
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
    
    func clearTranscriptions() {
        DispatchQueue.main.async {
            self.transcriptionHistory = []
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
        VStack(spacing: 8) {
            HStack {
                Text(appState.isRecording ? "●" : "○")
                    .font(.system(size: 18))
                    .foregroundColor(appState.isRecording ? .red : .gray)
                
                Text("Recording")
                    .font(.caption)
                    .foregroundColor(appState.isRecording ? .red : .gray)
                
                Spacer()
                
                if appState.isProcessingPrompt {
                    Text("Processing")
                        .font(.caption)
                        .foregroundColor(.blue)
                    
                    Text("●")
                        .font(.system(size: 18))
                        .foregroundColor(.blue)
                }
            }
            
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
    private let audioPlayer = AVAudioPlayerNode()
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
                "tool_choice": "required"
            ]
        ])
    }
    
    func defineFunction() {
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
        
        let sendPromptParams: [String: Any] = [
            "type": "object",
            "properties": [String: Any](),
            "required": [String]()
        ]
        
        let emptyParams: [String: Any] = [
            "type": "object",
            "properties": [String: Any](),
            "required": [String]()
        ]
        
        let transcriptionProperty: [String: String] = [
            "type": "string",
            "description": "The exact verbatim transcription of what the user said, word-for-word, without any added context or interpretation."
        ]
        
        let transcriptionProperties: [String: [String: String]] = [
            "text": transcriptionProperty
        ]
        
        let transcriptionParams: [String: Any] = [
            "type": "object", 
            "properties": transcriptionProperties,
            "required": ["text"]
        ]
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
        
        let updateTranscriptionFunction: [String: Any] = [
            "type": "function",
            "name": "updateTranscription",
            "description": "Provides a verbatim, word-for-word transcription of exactly what the user said without adding any conversational context, interpretation, or modification.",
            "parameters": transcriptionParams
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
        
        let clearFunction: [String: Any] = [
            "type": "function",
            "name": "clear",
            "description": "Clears the current interface and resets the state. Triggered by keyword 'clear'.",
            "parameters": emptyParams
        ]
        
        let tools = [editPromptFunction, sendPromptFunction, updateTranscriptionFunction, acceptFunction, rejectFunction, arrowUpFunction, arrowDownFunction, escapeFunction, clearFunction]
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
            defer { self.receiveResponse() }
            
            switch result {
            case .failure(let error):
                print("Error receiving audio response: \(error)")
                DispatchQueue.main.async {
                    self.appState.isRecording = false
                }
                return
                
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
            
        case "input_audio_buffer.speech_ended":
            handleSpeechEnded()
            
        case "response.output_item.done":
            handleOutputItemCompletion(json: json)
            
        case "response.audio_transcript.delta":
            if let transcript = json["text"] as? String {
                captureTranscript(transcript)
            }
            
        case "response.audio.delta":
            if let delta = json["delta"] as? String {
                playReceivedAudio(base64String: delta)
            }
            
        case "error":
            print("Error event: \(json)")
            
        case "response.function_call_arguments.delta",
             "response.function_call_arguments.done",
             "conversation.item.created":
            break
            
        default:
            break
        }
    }
    
    private func handleResponseCompletion(json: [String: Any]) {
        DispatchQueue.main.async {
            self.appState.isProcessingPrompt = false
        }
        
        if let response = json["response"] as? [String: Any],
           let status = response["status"] as? String, status == "failed" {
            print("Response failed: \(response["status_details"] ?? "Unknown error")")
        }
        
        if !appState.transcriptionHistory.isEmpty {
            considerGeneratingPromptWithO1()
        }
    }
    
    private func handleSpeechStarted() {
        print("User started speaking.")
        DispatchQueue.main.async {
            self.appState.isRecording = true
        }
        stopAudioPlayback()
    }
    
    private func handleSpeechEnded() {
        print("User speech ended. Processing transcription...")
    }
    
    private func captureTranscript(_ transcript: String) {
        print("Transcript delta: \(transcript)")
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
    
    private func considerGeneratingPromptWithO1() {
        guard !appState.isProcessingPrompt, !appState.transcriptionHistory.isEmpty else { return }
        
        DispatchQueue.main.async {
            self.appState.isProcessingPrompt = true
        }
        
        let context = appState.transcriptionHistory.joined(separator: "\n")
        
        DispatchQueue.global(qos: .userInitiated).async {
            self.generatePromptWithO1(fromTranscriptions: context) { result in
                DispatchQueue.main.async {
                    self.appState.isProcessingPrompt = false
                    
                    switch result {
                    case .success(let generatedPrompt):
                        self.appState.updateCurrentPrompt(generatedPrompt)
                    case .failure(let error):
                        print("Error generating prompt with O1: \(error)")
                    }
                }
            }
        }
    }
    
    private func generatePromptWithO1(fromTranscriptions transcriptions: String, completion: @escaping (Result<String, Error>) -> Void) {
        completion(.success(transcriptions))
    }
    
    private func handleFunctionCall(functionName: String, argumentsString: String, callID: String) {
        guard let argumentsData = argumentsString.data(using: .utf8) else {
            print("Failed to convert arguments string to data")
            return
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
            handleUpdateTranscription(text: text, callID: callID)
            
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
        
        appState.clearTranscriptions()
        
        executeKeystrokesInTerminal(clearSequence, actionName: "clear", callID: callID)
    }
    
    func handleUpdateTranscription(text: String, callID: String) {
        print("Appending transcription: \(text)")
        
        appState.appendTranscription(text)
        
        considerGeneratingPromptWithO1()
        
        let output = "Transcription appended"
        sendFunctionOutputToModel(callID: callID, output: output)
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
