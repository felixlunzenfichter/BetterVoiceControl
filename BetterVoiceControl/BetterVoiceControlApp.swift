let RESPONSES_INSTRUCTIONS = """
Your task is to convert a real-time transcription into a prompt that can be executed by a computer agent. Don't add anything, don't leave anything out, and make sure the prompt is well-structured and follows best practices when it comes to prompt engineering.
"""

let REALTIME_INSTRUCTIONS = """
Your task is to provide accurate real-time transcription of the user's voice input. Simply transcribe exactly what the user says verbatim, without adding any interpretation, context, or modifications. Call the updateTranscription function with the exact text the user spoke.
"""

import SwiftUI
import Cocoa
import ApplicationServices
import AVFoundation
import Foundation

class AppState: ObservableObject {
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
        let responsesAPI = OpenAIResponsesAPI(appState: appState)
        self.responsesAPI = responsesAPI
        self.realtimeAPI = OpenAIRealtimeAPI(appState: appState, responsesAPI: responsesAPI)
        
        requestMicrophonePermissions()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .onAppear {
                    realtimeAPI.connect()
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
    private let apiKey: String
    
    init(appState: AppState) {
        self.appState = appState
        self.apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ""
    }
    
    
    func generatePromptFromTranscriptions() {
        guard !appState.transcriptionHistory.isEmpty else { return }
        
        let transcriptionText = appState.transcriptionHistory.joined(separator: " ")
        callResponsesAPIForPromptGeneration(transcriptionText)
    }
    
    func callResponsesAPIForPromptGeneration(_ transcription: String) {
        let url = URL(string: "https://api.openai.com/v1/responses")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        let generatePromptFunction: [String: Any] = [
            "type": "function",
            "name": "generate_prompt",
            "description": "Generate a clean, structured prompt from user transcription",
            "parameters": [
                "type": "object",
                "properties": [
                    "prompt": [
                        "type": "string",
                        "description": "A clean, actionable prompt based on the user's transcription"
                    ]
                ],
                "required": ["prompt"],
                "additionalProperties": false
            ]
        ]
        
        let requestBody: [String: Any] = [
            "model": "o1",
            "input": [
                ["role": "user", "content": "Convert this transcription to a clean prompt: \(transcription)"]
            ],
            "tools": [generatePromptFunction],
            "tool_choice": "required"
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            print("Failed to create JSON data for request")
            return
        }
        
        request.httpBody = jsonData
        
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                print("API request failed: \(error.localizedDescription)")
                return
            }
            
            guard let data = data else {
                print("No data received from API")
                return
            }
            
            self.processPromptFunctionCallResponse(data)
        }
        
        task.resume()
    }
    
    private func processPromptFunctionCallResponse(_ data: Data) {
        guard let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
              let output = jsonObject["output"] as? [[String: Any]] else {
            print("Failed to parse response data")
            return
        }
        
        for item in output {
            if let type = item["type"] as? String, type == "function_call",
               let name = item["name"] as? String,
               let arguments = item["arguments"] as? String {
                
                print("Function called: \(name)")
                print("Arguments: \(arguments)")
                
                if let argumentsData = arguments.data(using: .utf8),
                   let argumentsObject = try? JSONSerialization.jsonObject(with: argumentsData, options: []) as? [String: Any],
                   let generatedPrompt = argumentsObject["prompt"] as? String {
                    
                    DispatchQueue.main.async {
                        self.appState.updateCurrentPrompt(generatedPrompt)
                    }
                    
                    print("Generated prompt: \(generatedPrompt)")
                }
            }
        }
    }
}

class OpenAIRealtimeAPI {
    private var webSocketTask: URLSessionWebSocketTask?
    private let audioEngine = AVAudioEngine()
    private let dispatchQueue = DispatchQueue(label: "com.openai.realtimeapi")
    private var appState: AppState
    private var responsesAPI: OpenAIResponsesAPI
    
    init(appState: AppState, responsesAPI: OpenAIResponsesAPI) {
        self.appState = appState
        self.responsesAPI = responsesAPI
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
                "instructions": REALTIME_INSTRUCTIONS,
                "tool_choice": "required"
            ]
        ])
    }
    
    func defineFunction() {
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
        
        let updateTranscriptionFunction: [String: Any] = [
            "type": "function",
            "name": "updateTranscription",
            "description": "Provides a verbatim, word-for-word transcription of exactly what the user said without adding any conversational context, interpretation, or modification.",
            "parameters": transcriptionParams
        ]
        
        let tools = [updateTranscriptionFunction]
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
            break
            
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
    }
    
    private func handleSpeechStarted() {
        print("User started speaking.")
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
        }
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
        
        let output = "Transcription appended"
        sendFunctionOutputToModel(callID: callID, output: output)
        
        responsesAPI.generatePromptFromTranscriptions()
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

