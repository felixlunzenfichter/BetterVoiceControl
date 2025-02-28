let INSTRUCTIONS = """
Your task is to be a prompt generator in a coding application designed for hands-free computing. Listen to the user’s voice input, interpret it carefully, and transform it into a clear, context-rich natural language prompt targeted at a coding agent called Claude Code. Apply optimal prompt engineering techniques to refine the user’s instructions before sending the final prompt to Claude Code for execution.
"""

import SwiftUI
import Cocoa
import ApplicationServices
import AVFoundation
import Foundation

class AppState: ObservableObject {
    @Published var transcript: String = ""
    @Published var isRecording: Bool = false
    @Published var modelOutputText: String = ""
    @Published var currentPrompt: String = ""
    @Published var promptStatus: String = "Ready"
    @Published var claudeResponse: String = ""
    
    func updateModelOutput(_ text: String) {
        DispatchQueue.main.async {
            self.modelOutputText = text
        }
    }
    
    func updateCurrentPrompt(_ prompt: String) {
        DispatchQueue.main.async {
            self.currentPrompt = prompt
        }
    }
    
    func updatePromptStatus(_ status: String) {
        DispatchQueue.main.async {
            self.promptStatus = status
        }
    }
    
    func updateClaudeResponse(_ response: String) {
        DispatchQueue.main.async {
            self.claudeResponse = response
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
                    // Initialize with a welcome message
                    appState.updateCurrentPrompt("Ready to receive voice input...")
                    appState.updatePromptStatus("Listening for commands")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        api.startClaudeTerminal()
                    }
                }
                .frame(width: 700, height: 500)
                .fixedSize()
        }
        .windowStyle(HiddenTitleBarWindowStyle())
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
        VStack(spacing: 12) {
            // Status indicator
            HStack {
                Circle()
                    .fill(appState.isRecording ? Color.red : Color.gray)
                    .frame(width: 12, height: 12)
                Text(appState.isRecording ? "Listening..." : "Idle")
                    .font(.headline)
                Spacer()
                Text("Status: \(appState.promptStatus)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 8)
            
            // Current prompt display
            VStack(alignment: .leading, spacing: 4) {
                Text("Current Prompt:")
                    .font(.headline)
                
                ScrollView {
                    Text(appState.currentPrompt)
                        .font(.system(.body, design: .monospaced))
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color(.textBackgroundColor).opacity(0.3))
                .cornerRadius(8)
                .frame(height: 120)
            }
            
            // Claude's response display
            VStack(alignment: .leading, spacing: 4) {
                Text("Claude Response:")
                    .font(.headline)
                
                ScrollView {
                    Text(appState.claudeResponse)
                        .font(.system(.body, design: .monospaced))
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color(.textBackgroundColor).opacity(0.3))
                .cornerRadius(8)
                .frame(height: 180)
            }
            
            // Voice recognition at bottom
            VStack(alignment: .leading, spacing: 4) {
                Text("Voice Recognition:")
                    .font(.caption)
                    .fontWeight(.bold)
                
                Text(appState.transcript)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 4)
        }
        .padding()
        .frame(width: 700, height: 500)
    }
}

class OpenAIRealtimeAPI {
    private var webSocketTask: URLSessionWebSocketTask?
    private let audioEngine = AVAudioEngine()
    private let dispatchQueue = DispatchQueue(label: "com.openai.realtimeapi")
    private let audioPlayer = AVAudioPlayerNode()
    private var persistentTerminalProcess: Process?
    private var terminalPipe: Pipe?
    private var appState: AppState
    private var terminalOutputQueue: [String] = []
    
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
    
    func startClaudeTerminal() {
        DispatchQueue.global(qos: .userInitiated).async {
            print("Starting persistent Claude terminal session...")
            
            // Get the current working directory
            let currentDirectory = FileManager.default.currentDirectoryPath
            print("Current directory: \(currentDirectory)")
            
            // Start persistent Claude CLI in the current working directory
            self.startPersistentClaudeSession(in: currentDirectory)
        }
    }
    
    func startPersistentClaudeSession(in directory: String) {
        // Create a persistent process for Claude CLI
        persistentTerminalProcess = Process()
        persistentTerminalProcess?.launchPath = "/bin/bash"
        
        // Change to the specified directory and start Claude in interactive mode
        persistentTerminalProcess?.arguments = ["-c", "cd \(directory) && /opt/homebrew/bin/claude"]
        
        // Set up environment variables
        var env = ProcessInfo.processInfo.environment
        let path = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = path
        persistentTerminalProcess?.environment = env
        
        // Create pipes for input and output
        let outputPipe = Pipe()
        let inputPipe = Pipe()
        
        persistentTerminalProcess?.standardOutput = outputPipe
        persistentTerminalProcess?.standardError = outputPipe
        persistentTerminalProcess?.standardInput = inputPipe
        
        // Store the pipes for later use
        terminalPipe = inputPipe
        
        // Set up continuous reading from the output pipe
        let outputHandle = outputPipe.fileHandleForReading
        outputHandle.readabilityHandler = { [weak self] handle in
            guard let self = self else { return }
            
            let data = handle.availableData
            if !data.isEmpty, let output = String(data: data, encoding: .utf8) {
                print("Claude output: \(output)")
                
                // Process and update UI with Claude's output
                self.processClaudeOutput(output)
            }
        }
        
        // Launch the process
        do {
            try persistentTerminalProcess?.run()
            print("Claude terminal session started successfully")
        } catch {
            print("Failed to start Claude terminal session: \(error)")
        }
    }
    
    func processClaudeOutput(_ output: String) {
        // Add the output to the queue
        terminalOutputQueue.append(output)
        
        // Combine all outputs for display
        let combinedOutput = terminalOutputQueue.joined()
        
        // Update the UI with Claude's response
        appState.updateClaudeResponse(combinedOutput)
        
        // Also log the output
        print("Claude Response Update: \(output.prefix(100))...")
    }
    
    func sendCommandToClaudeTerminal(_ command: String) {
        guard let inputPipe = terminalPipe, 
              persistentTerminalProcess?.isRunning == true else {
            print("Cannot send command: Claude terminal not running")
            return
        }
        
        // Add newline to ensure command is executed
        let fullCommand = command + "\n"
        
        if let data = fullCommand.data(using: .utf8) {
            do {
                try inputPipe.fileHandleForWriting.write(contentsOf: data)
                print("Sent command to Claude: \(command)")
            } catch {
                print("Failed to send command to Claude: \(error)")
            }
        }
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
                "instructions": INSTRUCTIONS
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
        
        // Create the complete payload
        let tools = [editPromptFunction, sendPromptFunction]
        let session: [String: Any] = ["tools": tools]
        let functionPayload: [String: Any] = [
            "type": "session.update",
            "session": session
        ]
        
        send(functionPayload)
    }
    
    func setupAudioEngine() {
        let inputNode = audioEngine.inputNode
//        let outputNode = audioEngine.outputNode
        
        let inputFormat = inputNode.inputFormat(forBus: 0)
        print(inputFormat)
        audioEngine.attach(audioPlayer)
        let desiredSampleRate: Double = 24000.0
        
        if inputFormat.sampleRate == desiredSampleRate {
            let inputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: desiredSampleRate, channels: 1, interleaved: true)!
            
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { buffer, time in
                self.sendAudioChunk(buffer: buffer)
            }
            
        } else {
            // Create a new format with the desired sample rate
            guard let desiredFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: desiredSampleRate, channels: 1, interleaved: true) else {
                print("Error creating desired format.")
                return
            }
            
            // Install a tap on the input node
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { buffer, time in
                self.convertAndSendAudio(buffer: buffer, inputFormat: inputFormat, outputFormat: desiredFormat)
            }
            
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
    
    func convertAndSendAudio(buffer: AVAudioPCMBuffer, inputFormat: AVAudioFormat, outputFormat: AVAudioFormat) {
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            print("Error creating audio converter.")
            return
        }
        
        let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: AVAudioFrameCount(outputFormat.sampleRate * Double(buffer.frameLength) / inputFormat.sampleRate))!
        
        var error: NSError? = nil
        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        
        converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
        
        if let error = error {
            print("Error during conversion: \(error)")
        } else {
            // Call your function to handle the converted buffer
            self.sendAudioChunk(buffer: outputBuffer)
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
                                    if let delta = json["delta"] as? String {
                                        // Update UI with function call delta
                                    }
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
                                                fatalError("Failed to parse editPrompt arguments")
                                            }
                                            handleEditPrompt(prompt: prompt, callID: callID)
                                        case "sendPrompt":
                                            handleSendPrompt(callID: callID)
                                        default:
                                            fatalError("Unknown function: \(functionName)")
                                        }
                                    } else if let contentArray = item["content"] as? [[String: Any]],
                                              let content = contentArray.first,
                                              let transcript = content["transcript"] as? String {
                                        print("[[Model Text Output]] \(transcript)")
                                        self.appState.updateModelOutput(transcript)
                                    }
                                case "response.audio_transcript.delta":
                                    if let delta = json["delta"] as? String {
                                        DispatchQueue.main.async {
                                            self.appState.transcript += delta
                                        }
                                    }
                                case "response.audio.delta":
                                    if let delta = json["delta"] as? String {
                                        playReceivedAudio(base64String: delta)
                                    }
                                case "conversation.item.created":
                                    break
                                case "error":
                                    print("Error: \(json)")
                                default:
                                    print("Unhandled event type: \(eventType)")
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

    func executeTerminalCommand(_ command: String, callID: String) {
        print("[[Executing Command]] \(command)")
        
        let process = Process()
        process.launchPath = "/bin/bash"
        process.arguments = ["-c", command]
        
        // Set the proper environment variables to ensure binaries like node can be found
        var env = ProcessInfo.processInfo.environment
        let path = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = path
        process.environment = env
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        process.launch()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        
        if let output = String(data: data, encoding: .utf8) {
            let result = "exit code: \(process.terminationStatus)\n" + "output: \(output)"
            print("[[Command Output]] \(result)")
            
            sendTerminalOutputToModel(callID: callID, output: result)
        }
    }
    
    func sendTerminalOutputToModel(callID: String, output: String) {
        let payload: [String: Any] = [
            "type": "conversation.item.create",
            "item": [
                "type": "function_call_output",
                "call_id": callID,
                "output": output
            ]
        ]
        
        send(payload)
        send(["type": "response.create"])
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
    
    // Handle the editPrompt function call from the model
    func handleEditPrompt(prompt: String, callID: String) {
        print("Updating prompt: \(prompt)")
        
        // Update the prompt in the AppState
        appState.updateCurrentPrompt(prompt)
        appState.updatePromptStatus("Prompt updated")
        
        // Send function output back to model
        let output = "Prompt updated successfully"
        sendFunctionOutputToModel(callID: callID, output: output)
    }
    
    // Handle the sendPrompt function call from the model
    func handleSendPrompt(callID: String) {
        if appState.currentPrompt.isEmpty {
            let output = "Error: No prompt available to send"
            appState.updatePromptStatus("Error: No prompt to send")
            sendFunctionOutputToModel(callID: callID, output: output)
            return
        }
        
        print("Sending prompt to Claude: \(appState.currentPrompt)")
        appState.updatePromptStatus("Sending to Claude...")
        
        // Send the prompt directly to the persistent Claude terminal session
        sendCommandToClaudeTerminal(appState.currentPrompt)
        
        // Reset current prompt after sending
        appState.updateCurrentPrompt("")
        appState.updatePromptStatus("Prompt sent to Claude")
        
        // Send function output back to model
        let output = "Prompt sent to Claude"
        sendFunctionOutputToModel(callID: callID, output: output)
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

/* Auxiliary Functions */
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
