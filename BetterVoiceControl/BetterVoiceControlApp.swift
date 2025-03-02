let INSTRUCTIONS = "Your task is to provide a zero-touch interface for browser usage by converting user instructions into prompts that can be executed by a browser agent. Transform natural language instructions into succinct, optimal commands. For direct execution, refine the prompt with no additional commentary."

import SwiftUI
import Cocoa
import ApplicationServices
import AVFoundation

@main
struct VoiceControlledMacApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @StateObject var viewModel = ViewModel()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Listening:")
                Spacer()
                Text(viewModel.isListening ? "Yes" : "No")
                    .foregroundColor(viewModel.isListening ? .green : .red)
            }
            
            HStack {
                Text("Executing:")
                Spacer()
                Text(viewModel.isExecuting ? "Yes" : "No")
                    .foregroundColor(viewModel.isExecuting ? .green : .red)
            }
            
            Text("Current Prompt:")
                .font(.headline)
            
            ZStack {
                Text(viewModel.prompt)
                    .padding()
                    .id(viewModel.prompt)
                    .transition(.opacity)
            }
            .animation(.easeInOut, value: viewModel.prompt)
            
            Button(action: viewModel.startListening) {
                Text("Start Listening")
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            
            ScrollView {
                ForEach(viewModel.modelResponses.reversed(), id: \.self) { response in
                    Text(response)
                }
            }
            
            Spacer()
        }
        .padding()
    }
}

class ViewModel: ObservableObject {
    @Published var modelResponses: [String] = []
    @Published var prompt: String = "Initial prompt text."
    @Published var isListening: Bool = false
    @Published var isExecuting: Bool = false

    func startListening() {
        // Implementation goes here.
    }

    private var webSocketTask: URLSessionWebSocketTask?
    private let audioEngine = AVAudioEngine()
    private let dispatchQueue = DispatchQueue(label: "com.openai.realtimeapi")
    private let audioPlayer = AVAudioPlayerNode()
    
    init() {
        requestMicrophonePermissions()

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
    
    func requestMicrophonePermissions() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            if granted {
                print("Microphone permissions granted!")
            } else {
                print("Microphone permissions not granted.")
            }
        }
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
                "modalities": ["text"],
                "instructions": INSTRUCTIONS,
            ]
        ])
    }
    
    func defineFunction() {
        let functionPayload: [String: Any] = [
            "type": "session.update",
            "session": [
                "tools": [
                    [
                        "type": "function",
                        "name": "updatePrompt",
                        "description": "Updates the prompt text based on user input.",
                        "parameters": [
                            "type": "object",
                            "properties": [
                                "prompt": [
                                    "type": "string",
                                    "description": "The new prompt text."
                                ]
                            ],
                            "required": ["prompt"]
                        ]
                    ],
                    [
                        "type": "function",
                        "name": "sendPrompt",
                        "description": "Sends the current prompt to the browser operator to execute the task.",
                        "parameters": [
                            "type": "object",
                            "properties": [:],
                            "required": []
                        ]
                    ],
                    [
                        "type": "function",
                        "name": "stopTask",
                        "description": "Stops the currently executing task.",
                        "parameters": [
                            "type": "object",
                            "properties": [:],
                            "required": []
                        ]
                    ],
                    [
                        "type": "function",
                        "name": "stopListening",
                        "description": "Stops listening to the user.",
                        "parameters": [
                            "type": "object",
                            "properties": [:],
                            "required": []
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
                                       let name = item["name"] as? String,
                                       let argumentsString = item["arguments"] as? String,
                                       let argumentsData = argumentsString.data(using: .utf8),
                                       let argumentsDict = try? JSONSerialization.jsonObject(with: argumentsData, options: []) as? [String: Any] {
                                        switch name {
                                        case "updatePrompt":
                                            if let prompt = argumentsDict["prompt"] as? String {
                                                DispatchQueue.main.async {
                                                    self.prompt = prompt
                                                }
                                            }
                                        case "sendPrompt":
                                            DispatchQueue.main.async {
                                                self.isExecuting = true
                                            }
                                        case "stopTask":
                                            DispatchQueue.main.async {
                                                self.isExecuting = false
                                                self.prompt = "Task stopped."
                                            }
                                        case "stopListening":
                                            DispatchQueue.main.async {
                                                self.isListening = false
                                                self.prompt = "Stopped listening."
                                            }
                                        default:
                                            print("Unhandled function: \(name)")
                                        }
                                    } else if let contentArray = item["content"] as? [[String: Any]],
                                              let content = contentArray.first,
                                              let transcript = content["transcript"] as? String {
                                        print("[[Model Audio Transcript]] \(transcript)")
                                    }
                                case "response.audio_transcript.delta":
                                    break
                                case "response.audio.delta":
                                    if let delta = json["delta"] as? String {
                                        playReceivedAudio(base64String: delta)
                                    }
                                case "conversation.item.created":
                                    break
                                case "response.text.delta":
                                    break
                                case "response.text.done":
                                    if let text = json["text"] as? String {
                                        print("[[Model Text Output]] \(text)")
                                        DispatchQueue.main.async {
                                            self.modelResponses.append(text)
                                        }
                                    }
                                case "error":
                                    print("Error: \(json)")
                                default:
                                    print("Unhandled event type: \(eventType)")
                                }
                            }
                            receiveResponse()
                        } catch {
                            fatalError("Error parsing JSON: \(error)")
                        }
                    }
                case .data(let data):
                    print("Received data message of size: \(data.count) bytes.")
                    receiveResponse()
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
//        send(["type": "response.create"])
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
