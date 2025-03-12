// Instructions for Responses API - handles Computer Use tool
let RESPONSES_INSTRUCTIONS = """
You are an assistive computer agent for people who cannot use a computer with their hands, such as individuals with paraplegia or other mobility impairments. Your purpose is to enable full computer control using only voice commands.

The workflow is:
1. You receive transcribed voice input from the user
2. You transform this into a clear, actionable prompt
3. When the user confirms, you use the Computer Use tool to directly execute actions on their Mac

Your role is to:
- Interpret user intent accurately from transcriptions
- Format instructions into clear, precise commands for the Computer Use tool
- Provide feedback about what actions will be taken
- Only execute commands when the user is ready

Remember that the user depends on you for all computer interactions. Be responsive, precise, and helpful in enabling them to accomplish any computer task through voice alone.
"""

// Instructions for Realtime API - only handles transcription
let REALTIME_INSTRUCTIONS = """
Your task is to provide accurate real-time transcription of the user's voice input. Simply transcribe exactly what the user says verbatim, without adding any interpretation, context, or modifications. Call the updateTranscription function with the exact text the user spoke.
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
    let realtimeAPI: OpenAIRealtimeAPI
    let responsesAPI: OpenAIResponsesAPI
    
    init() {
        let appState = AppState()
        self._appState = StateObject(wrappedValue: appState)
        self.realtimeAPI = OpenAIRealtimeAPI(appState: appState)
        self.responsesAPI = OpenAIResponsesAPI(appState: appState)
        
        requestMicrophonePermissions()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .onAppear {
                    realtimeAPI.connect()
                    responsesAPI.setup()
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

class OpenAIResponsesAPI {
    private let appState: AppState
    
    init(appState: AppState) {
        self.appState = appState
    }
    
    func setup() {
        // API setup and function call handling will be implemented here
    }
    
    // Implementation for Responses API will be added here
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
                    print("Error sending json: \(error)")
                    return
                }
            }
        }
    }
    
    func setInstructions() {
        // Update to use the new transcription-focused instructions
        send([
            "type": "session.update",
            "session": [
                "instructions": REALTIME_INSTRUCTIONS,
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
        case "updateTranscription":
            guard let argumentsDict = try? JSONSerialization.jsonObject(with: argumentsData, options: []) as? [String: Any],
                  let text = argumentsDict["text"] as? String else {
                print("Failed to parse updateTranscription arguments")
                let errorOutput = "Error: Failed to parse the text argument"
                sendFunctionOutputToModel(callID: callID, output: errorOutput)
                return
            }
            handleUpdateTranscription(text: text, callID: callID)
            
        default:
            print("Unknown function: \(functionName)")
        }
    }
    
    func handleUpdateTranscription(text: String, callID: String) {
        print("Appending transcription: \(text)")
        
        appState.appendTranscription(text)
        
        // Post notification for the ResponsesAPI to process this transcription
        NotificationCenter.default.post(name: Notification.Name("TranscriptionAdded"), object: nil)
        
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

