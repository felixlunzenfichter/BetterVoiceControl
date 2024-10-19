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
        webSocketTask?.resume()
        
        print("Connected to OpenAI Realtime API.")
        setupAudioEngine()
    }
    
    func setupAudioEngine() {
        audioEngine.attach(audioPlayer)
        let inputNode = audioEngine.inputNode
        let sampleRate: Double = 24000.0
        let inputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: 1, interleaved: true)!
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { buffer, time in
            self.sendAudioChunk(buffer: buffer)
        }
        
        let playbackFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
        audioEngine.connect(audioPlayer, to: audioEngine.mainMixerNode, format: playbackFormat)
        audioEngine.prepare()
        
        do {
            try audioEngine.start()
            print("Audio engine started.")
            receiveAudioResponse()
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
    
    func receiveAudioResponse() {
        webSocketTask?.receive { [self] result in
            switch result {
            case .failure(let error):
                fatalError("Error receiving audio response: \(error)")
            case .success(let message):
                switch message {
                case .string(let text):
                    if let data = text.data(using: .utf8) {
                        do {
                            let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
                            if let eventType = json?["type"] as? String {
                                switch eventType {
                                case "response.text.delta":
                                    if let delta = json?["delta"] as? String {
                                        print("Text Delta: \(delta)")
                                    }
                                case "response.audio_transcript.delta":
                                    if let delta = json?["delta"] as? String {
                                        print("Audio Transcript Delta: \(delta)")
                                    }
                                case "response.audio.delta":
                                    if let delta = json?["delta"] as? String {
                                        playReceivedAudio(base64String: delta)
                                    }
                                default:
                                    print("Unhandled event type: \(eventType)")
                                }
                            }
                            self.receiveAudioResponse()
                        } catch {
                            fatalError("Error parsing JSON: \(error)")
                        }
                    }
                case .data(let data):
                    print("Received data message of size: \(data.count) bytes.")
                @unknown default:
                    fatalError("Unknown message type received.")
                }
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
            } else {
                print("Audio player is already playing.")
            }
        }
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
    return pcmData.withUnsafeBytes { (ptr: UnsafePointer<Int16>) in
        let count = pcmData.count / MemoryLayout<Int16>.size
        return (0..<count).map { Float(ptr[$0]) / 32768.0 }
    }
}
