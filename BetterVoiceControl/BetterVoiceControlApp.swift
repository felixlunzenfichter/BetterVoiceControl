let INSTRUCTIONS = """
Instructions for Better Voice Control Assistants

You are operating within the Better Voice Control application, an accessibility tool designed for users who cannot use a mouse or keyboard and rely on hands-free operation.

In this role, you will execute all tasks through terminal commands or macOS functions, including document management and AppleScript actions. You have full access to the macOS Accessibility API and terminal, allowing you to handle all requests independently.

Please remember:

	•	Never suggest that the user perform any action themselves. This would always be highly inappropriate and offensive.
	•	Speech output is limited to a maximum length of one sentence.
	•	If additional information is needed that is longer than a sentence, provide it through text output. Be aware that all terminal commands, function calls, and their outputs can be seen by the user and do not need to be repeated through voice. Voice is extremely costly, so anything beyond one sentence must be communicated via text for the user to read. This ensures a quick experience, delivering concise answers without delay.
Your goal is to ensure a respectful, efficient, and fully hands-free experience.
"""

import SwiftUI
import Cocoa
import ApplicationServices
import AVFoundation

@main
struct VoiceControlledMacApp: App {
    let api = OpenAIRealtimeAPI()
    
    init() {
        requestMicrophonePermissions()
        api.connect()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
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
    var body: some View {
        VStack {
            Text("Voice-Controlled Mac App")
                .font(.largeTitle)
                .padding()
            Text("Grant Microphone and Accessibility permissions to control the UI.")
                .padding()
        }
        .frame(width: 400, height: 300)
    }
}

class OpenAIRealtimeAPI {
    private var webSocketTask: URLSessionWebSocketTask?
    private let audioEngine = AVAudioEngine()
    private let dispatchQueue = DispatchQueue(label: "com.openai.realtimeapi")
    private let audioPlayer = AVAudioPlayerNode()
    
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
                    fatalError("Error sending json: \(error)")
                }
            }}
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
    let functionPayload: [String: Any] = [
        "type": "session.update",
        "session": [
            "max_response_output_tokens": 10, // Set the maximum token limit to 10 for testing
            "tools": [
                [
                    "type": "function",
                    "name": "executeCommandOnTerminal",
                    "description": "Executes a terminal command and returns the output.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "command": [
                                "type": "string",
                                "description": "The terminal command to execute."
                                ]
                            ],
                            "required": ["command"]
                        ]
                    ]
                ]
            ]
        ]
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
                fatalError("Error receiving audio response: \(error)")
            case .success(let message):
                switch message {
                case .string(let text):
                    if let data = text.data(using: .utf8) {
                        do {
                            guard let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
                                fatalError("Error: JSON is not of expected format.")
                            }
                            
                            if let eventType = json["type"] as? String {
                                switch eventType {
                                case "response.done":
                                    if let response = json["response"] as? [String: Any],
                                       let status = response["status"] as? String, status == "failed" {
                                        fatalError("response failed\n\(response["status_details"]!)")
                                    }
                                case "response.function_call_arguments.delta":
                                    break
                                case "response.function_call_arguments.done":
                                    break
                                case "input_audio_buffer.speech_started":
                                    print("User started speaking.")
                                    stopAudioPlayback()
                                case "response.output_item.done":
                                    guard let item = json["item"] as? [String: Any] else { break }
                                    
                                    if let type = item["type"] as? String, type == "function_call",
                                       let callID = item["call_id"] as? String,
                                       let argumentsString = item["arguments"] as? String,
                                       let argumentsData = argumentsString.data(using: .utf8),
                                       let argumentsDict = try? JSONSerialization.jsonObject(with: argumentsData, options: []) as? [String: Any],
                                       let command = argumentsDict["command"] as? String {
                                        executeTerminalCommand(command, callID: callID)
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
                                    print("Unhandled event type: \(eventType)")
                                }
                            }
                            self.receiveResponse()
                        } catch {
                            fatalError("Error parsing JSON: \(error)")
                        }
                    }
                case .data(let data):
                    print("Received data message of size: \(data.count) bytes.")
                    self.receiveResponse()
                @unknown default:
                    fatalError("Unknown message type received.")
                }
            }
        }
    }

    func executeTerminalCommand(_ command: String, callID: String) {
        print("[[Executing Command]] \(command)")
        
        let process = Process()
        process.launchPath = "/bin/bash"
        process.arguments = ["-c", command]
        
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
            fatalError("Failed to create audio buffer.")
        }
        
        dispatchQueue.async {
            if !self.audioEngine.isRunning {
                do {
                    try self.audioEngine.start()
                    print("Playback engine restarted.")
                } catch {
                    fatalError("Playback engine couldn't start: \(error)")
                }
            }
            
            self.audioPlayer.scheduleBuffer(audioBuffer, at: nil, options: [], completionHandler: nil)
            
            if !self.audioPlayer.isPlaying {
                self.audioPlayer.play()
                print("Audio playback started.")
            }
        }
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
    return pcmData.withUnsafeBytes { (ptr: UnsafePointer<Int16>) in
        let count = pcmData.count / MemoryLayout<Int16>.size
        return (0..<count).map { Float(ptr[$0]) / 32768.0 }
    }
}
