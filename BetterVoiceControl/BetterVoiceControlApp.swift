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
    
    // Playback properties
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
        webSocketTask?.resume()
        
        print("Connected to OpenAI Realtime API.")
        
        // Send session update to enable transcription
        let sessionUpdate: [String: Any] = [
            "type": "session.update",
            "session": [
                "input_audio_transcription": [
                    "model": "whisper-1"  // Enable real-time transcription with Whisper
                ]
            ]
        ]
        
        do {
            let sessionData = try JSONSerialization.data(withJSONObject: sessionUpdate, options: [])
            webSocketTask?.send(.string(String(data: sessionData, encoding: .utf8)!)) { error in
                if let error = error {
                    print("Error sending session update: \(error)")
                } else {
                    print("Session updated with real-time transcription enabled.")
                }
            }
        } catch {
            print("Error serializing session update: \(error)")
        }
        
        setupAudioEngine()  // Stream the audio to the API
    }
    
    func setupAudioEngine() {
        // Attach the audio player node
        audioEngine.attach(audioPlayer)
        
        // Get the input and output nodes
        let inputNode = audioEngine.inputNode
        
        // Define the desired sample rate
        let sampleRate: Double = 24000.0
        
        // Create format for capturing audio (input) with forced sample rate
        let inputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: 1, interleaved: true)!
        
        // Install a tap on the input node to capture audio
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { buffer, time in
            self.sendAudioChunk(buffer: buffer)
        }
        
        // Create format for playback (output) with the same sample rate
        let playbackFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
        
        // Connect the audio player node to the main mixer node with the forced sample rate
        audioEngine.connect(audioPlayer, to: audioEngine.mainMixerNode, format: playbackFormat)
        
        // Prepare and start the audio engine
        audioEngine.prepare()
        
        do {
            try audioEngine.start()
            print("Audio engine started.")
            receiveAudioResponse()  // Handle the responses
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
    var textDeltas: String = ""
    var audioTranscriptDeltas: String = ""

    func receiveAudioResponse() {
        webSocketTask?.receive { [self] result in
            switch result {
            case .failure(let error):
                print("Error receiving audio response: \(error)")
            case .success(let message):
                switch message {
                case .string(let text):
                    // Parse the JSON response
                    if let data = text.data(using: .utf8) {
                        do {
                            let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
                            // Check for delta event types
                            if let eventType = json?["type"] as? String {
                                switch eventType {
                                case "conversation.item.input_audio_transcription.completed":
                                    if let transcript = json?["transcript"] as? String {
                                        print("Transcription: \(transcript)")
                                        textDeltas += transcript  // Append or process the transcription as needed
                                    }

                                case "response.text.delta":
                                    if let delta = json?["delta"] as? String {
                                        print("Text Delta: \(delta)")
                                        textDeltas += delta  // Append delta to textDeltas
                                    }
                                case "response.audio_transcript.delta":
                                    if let delta = json?["delta"] as? String {
                                        print("Audio Transcript Delta: \(delta)")
                                        audioTranscriptDeltas += delta  // Append delta to audioTranscriptDeltas
                                    }
                                case "response.audio.delta":
                                    if let delta = json?["delta"] as? String {
//                                        print("Audio Delta: \(delta)")
                                        playReceivedAudio(base64String: delta)
                                    }
                                default:
                                    print("Unhandled event type: \(eventType)")
                                }
                            }
                        } catch {
                            print("Error parsing JSON: \(error)")
                        }
                    }
                    self.receiveAudioResponse()  // Continue receiving messages
                case .data(let data):
                    print("Received data message of size: \(data.count) bytes.")
                    self.receiveAudioResponse()
                @unknown default:
                    fatalError("Unknown message type received.")
                }
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
                }
            }
            
            self.audioPlayer.scheduleBuffer(audioBuffer, at: nil, options: [], completionHandler: nil)
            
            if !self.audioPlayer.isPlaying {
                self.audioPlayer.play()
                print("Audio playback started.")
            } else {
                print("Audio player is already playing.")
            }
        }
    }
    
    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        print("Disconnected from OpenAI Realtime API.")
    }
}

// Helper Functions

func base64ToAudioBuffer(base64String: String, sampleRate: Double = 24000, channels: AVAudioChannelCount = 1) -> AVAudioPCMBuffer? {
    // Step 1: Decode Base64 String
    guard let pcmData = Data(base64Encoded: base64String) else {
        print("Error decoding base64 string")
        return nil
    }
    
    // Step 2: Convert PCM16 data to Float32
    let float32Data = pcm16ToFloat32(pcmData: pcmData)
    
    // Step 3: Create an AVAudioPCMBuffer with the Float32 data
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: channels, interleaved: false)!
    let frameCapacity = AVAudioFrameCount(float32Data.count)
    
    guard let audioBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else {
        print("Error creating audio buffer")
        return nil
    }
    
    audioBuffer.frameLength = frameCapacity
    
    // Fill the buffer with the converted Float32 data
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
