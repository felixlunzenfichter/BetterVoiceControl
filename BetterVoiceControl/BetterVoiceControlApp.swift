let INSTRUCTIONS = """
Your task is to be a prompt generator in a coding application designed for hands-free computing. Listen to the user’s voice input, interpret it carefully, and transform it into a clear, context-rich natural language prompt targeted at a coding agent called Claude Code. Apply optimal prompt engineering techniques to refine the user’s instructions before sending the final prompt to Claude Code for execution.
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
                                                return
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
    
    func sendCommandToClaudeTerminal(_ command: String) {

        
        do {
            print("Preparing to inject command into active terminal...")
            
            // Use AppleScript to send the command to the active Terminal window
            let escapedCommand = command.replacingOccurrences(of: "\\", with: "\\\\")
                                       .replacingOccurrences(of: "\"", with: "\\\"")
                                       .replacingOccurrences(of: "'", with: "\\'")
            
            let script = """
            tell application "Terminal"
                activate
                delay 0.5
                tell application "System Events"
                    keystroke "\(escapedCommand)"
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
            
            print("Command sent to terminal: \(command)")
            // Clear the prompt after sending
            appState.updateCurrentPrompt("")
        } catch {
            print("Error sending command via AppleScript: \(error)")
        }
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
        sendCommandToClaudeTerminal(appState.currentPrompt)
        
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
