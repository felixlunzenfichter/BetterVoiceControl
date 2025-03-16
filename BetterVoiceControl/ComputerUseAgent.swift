import Foundation
import SwiftUI
import AppKit

class ComputerUseAgent {
    private let appState: AppState
    private let apiKey: String
    let p = "log into github through safari."
    private let startTime = Date()
    private var iterationCount = 0
    
    init(appState: AppState) {
        self.appState = appState
        self.apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ""
        print("[0.0s] Starting Computer Use agent")
        startSession(withFixedPrompt: p)
    }
    
    private func logWithTime(_ message: String) {
        let elapsed = Date().timeIntervalSince(startTime)
        print(String(format: "[%.1fs] %@", elapsed, message))
    }
    
    func startSession(withFixedPrompt prompt: String) {
        iterationCount = 0
        logWithTime("Starting new session with prompt: \(prompt)")
        
        guard !apiKey.isEmpty else {
            print("API key not found")
            return
        }
        
        // Capture a screenshot to start
        guard let screenshot = captureScreenshot(),
              let base64Screenshot = convertImageToBase64(screenshot) else {
            print("Failed to capture or convert screenshot")
            return
        }
        
        // Get screen dimensions and use half size
        guard let screen = NSScreen.main else {
            print("Cannot access screen for dimensions")
            return
        }
        let screenRect = screen.frame
        let halfWidth = Int(screenRect.width / 2)
        let halfHeight = Int(screenRect.height / 2)
        
        // Create and send the initial request
        let url = URL(string: "https://api.openai.com/v1/responses")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody: [String: Any] = [
            "model": "computer-use-preview",
            "tools": [
                [
                    "type": "computer_use_preview",
                    "display_width": halfWidth,
                    "display_height": halfHeight,
                    "environment": "mac"
                ]
            ],
            "input": [
                [
                    "role": "user",
                    "content": prompt
                ],
            ],
            "truncation": "auto"
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
            
            self.processResponse(data)
        }
        
        task.resume()
    }
    
    private func processResponse(_ data: Data) {
        iterationCount += 1
        logWithTime("Processing response (iteration #\(iterationCount))")
        
        guard let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            print("Failed to parse response data")
            return
        }
        
        // Get response ID for continuing the session
        let responseId = jsonObject["id"] as? String
        print("Response ID: \(responseId ?? "None")")
        
        // Check if there's a computer call action
        if let output = jsonObject["output"] as? [[String: Any]] {
            print("Output array found with \(output.count) items")
            
            for item in output {
                if let type = item["type"] as? String, type == "computer_call",
                   let callId = item["call_id"] as? String,
                   let action = item["action"] as? [String: Any] {
                    
                    print("Found computer_call with ID: \(callId)")
                    logWithTime("Computer Use Action: \(action)")
                    
                    // Handle the action based on its type
                    if let actionType = action["type"] as? String {
                        if actionType == "click" {
                            // Extract click coordinates and perform the click
                            if let x = action["x"] as? CGFloat,
                               let y = action["y"] as? CGFloat {
                                performClick(x: x, y: y)
                            }
                        } else if actionType == "wait" {
                            // Wait for a short period
                            performWait()
                        } else if actionType == "type" {
                            // Handle typing if text is provided
                            if let text = action["text"] as? String {
                                performTyping(text: text)
                            }
                        } else if actionType == "keypress" {
                            // Handle keypress actions
                            if let keys = action["keys"] as? [String] {
                                performKeypress(keys: keys)
                            }
                        }
                        
                        // Continue the session after handling the action
                        continueSession(responseId: responseId, callId: callId)
                        return
                    }
                }
            }
        } else {
            print("No 'output' array found in response or it's not the expected format")
        }
    }
    
    private func continueSession(responseId: String?, callId: String) {
        guard let responseId = responseId else {
            print("No response ID available to continue session")
            return
        }
        
        // Capture a new screenshot
        logWithTime("Capturing screenshot for next iteration")
        guard let screenshot = captureScreenshot(),
              let base64Screenshot = convertImageToBase64(screenshot) else {
            print("Failed to capture or convert screenshot")
            return
        }
        
        logWithTime("Screenshot captured, size: \(base64Screenshot.count / 1024) KB, sending to API")
        
        let url = URL(string: "https://api.openai.com/v1/responses")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Prepare the computer_call_output with the screenshot
        let requestBody: [String: Any] = [
            "model": "computer-use-preview",
            "previous_response_id": responseId,
            "tools": [
                [
                    "type": "computer_use_preview",
                    "display_width": 1280,
                    "display_height": 800,
                    "environment": "mac"
                ]
            ],
            "input": [
                [
                    "role": "user",
                    "content": p
                ],
                [
                    "type": "computer_call_output",
                    "call_id": callId,
                    "output": [
                        "type": "input_image",
                        "image_url": "data:image/png;base64,\(base64Screenshot)"
                    ]
                ]
            ],
            "truncation": "auto"
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            print("Failed to create JSON data for continuing session")
            return
        }
        
        request.httpBody = jsonData
        
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                print("API request failed when continuing session: \(error.localizedDescription)")
                return
            }
            
            guard let data = data else {
                print("No data received from API when continuing session")
                return
            }
            
            self.logWithTime("Received API response")
            
            // Process the next response
            self.processResponse(data)
        }
        
        task.resume()
    }
    
    private func captureScreenshot() -> NSImage? {
        guard let screen = NSScreen.main else { return nil }
        let screenRect = screen.frame
        
        // Use half the original screen size
        let halfWidth = Int(screenRect.width / 2)
        let halfHeight = Int(screenRect.height / 2)
        
        // Log the screen details
        logWithTime("Original screen: \(screenRect.width)x\(screenRect.height), Using: \(halfWidth)x\(halfHeight)")
        
        // Capture at half resolution
        guard let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: halfWidth,
            pixelsHigh: halfHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        
        guard let context = NSGraphicsContext(bitmapImageRep: bitmapRep) else { return nil }
        
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        
        guard let cgScreenID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            NSGraphicsContext.restoreGraphicsState()
            return nil
        }
        
        let screenID = cgScreenID.uint32Value
        let screenImage = CGDisplayCreateImage(screenID)
        
        if let screenImage = screenImage {
            let halfSize = NSSize(width: halfWidth, height: halfHeight)
            let imageRect = CGRect(x: 0, y: 0, width: halfWidth, height: halfHeight)
            let nsImage = NSImage(cgImage: screenImage, size: halfSize)
            nsImage.draw(in: imageRect)
        }
        
        NSGraphicsContext.restoreGraphicsState()
        
        let image = NSImage(size: NSSize(width: halfWidth, height: halfHeight))
        image.addRepresentation(bitmapRep)
        
        return image
    }
    
    private func convertImageToBase64(_ image: NSImage) -> String? {
        guard let tiffData = image.tiffRepresentation else { return nil }
        
        let bitmap = NSBitmapImageRep(data: tiffData)
        
        // Use PNG for highest quality
        guard let pngData = bitmap?.representation(using: .png, properties: [:]) else {
            return nil
        }
        
        let dimensions = image.size
        logWithTime("Image dimensions: \(dimensions.width)x\(dimensions.height), size: \(pngData.count / 1024) KB")
        return pngData.base64EncodedString()
    }
    
    private func performClick(x: CGFloat, y: CGFloat) {
        print("Performing click at coordinates: (\(x), \(y))")
        
        // Create a CGPoint for the click position
        let position = CGPoint(x: x, y: y)
        
        // Create a mouse event for mouse down
        let mouseDownEvent = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, 
                                    mouseCursorPosition: position, mouseButton: .left)
        
        // Create a mouse event for mouse up
        let mouseUpEvent = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, 
                                  mouseCursorPosition: position, mouseButton: .left)
        
        // Post the events to the system
        mouseDownEvent?.post(tap: .cghidEventTap)
        mouseUpEvent?.post(tap: .cghidEventTap)
    }
    
    private func performWait() {
        print("Performing wait action (2 seconds)")
        // Sleep for 2 seconds
        Thread.sleep(forTimeInterval: 2.0)
    }
    
    private func performTyping(text: String) {
        print("Typing text: \(text)")
        
        // Simple implementation using NSPasteboard and CMD+V
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        // Press and release command key
        let cmdKeyDown = CGEvent(keyboardEventSource: nil, virtualKey: 55, keyDown: true)
        cmdKeyDown?.post(tap: .cghidEventTap)
        
        // Press and release V key with command flag
        let vKeyDown = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true)
        vKeyDown?.flags = .maskCommand
        vKeyDown?.post(tap: .cghidEventTap)
        
        let vKeyUp = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: false)
        vKeyUp?.flags = .maskCommand
        vKeyUp?.post(tap: .cghidEventTap)
        
        // Release command key
        let cmdKeyUp = CGEvent(keyboardEventSource: nil, virtualKey: 55, keyDown: false)
        cmdKeyUp?.post(tap: .cghidEventTap)
        
        // Small delay to ensure the paste completes
        Thread.sleep(forTimeInterval: 0.1)
    }
    
    private func performKeypress(keys: [String]) {
        print("Performing keypress: \(keys)")
        
        // Define key code mappings
        let keyCodeMap: [String: CGKeyCode] = [
            "SPACE": 49,
            "RETURN": 36,
            "ENTER": 36,
            "TAB": 48,
            "ESC": 53,
            "CMD": 55,  // Left command key
            "COMMAND": 55,
            "SHIFT": 56, // Left shift key
            "OPTION": 58, // Left option key
            "ALT": 58,
            "CONTROL": 59, // Left control key
            "CTRL": 59,
            "A": 0,
            "B": 11,
            "C": 8,
            "D": 2,
            "E": 14,
            "F": 3,
            "G": 5,
            "H": 4,
            "I": 34,
            "J": 38,
            "K": 40,
            "L": 37,
            "M": 46,
            "N": 45,
            "O": 31,
            "P": 35,
            "Q": 12,
            "R": 15,
            "S": 1,
            "T": 17,
            "U": 32,
            "V": 9,
            "W": 13,
            "X": 7,
            "Y": 16,
            "Z": 6
        ]
        
        // Flags for modifier keys
        var flags: CGEventFlags = []
        var modifierKeyCodes: [CGKeyCode] = []
        
        // First, identify and prepare all modifier keys
        for key in keys {
            let upperKey = key.uppercased()
            
            // Check if it's a modifier key
            if ["CMD", "COMMAND", "SHIFT", "OPTION", "ALT", "CONTROL", "CTRL"].contains(upperKey),
               let keyCode = keyCodeMap[upperKey] {
                
                // Add the appropriate flag
                switch upperKey {
                case "CMD", "COMMAND":
                    flags.insert(.maskCommand)
                case "SHIFT":
                    flags.insert(.maskShift)
                case "OPTION", "ALT":
                    flags.insert(.maskAlternate)
                case "CONTROL", "CTRL":
                    flags.insert(.maskControl)
                default:
                    break
                }
                
                modifierKeyCodes.append(keyCode)
            }
        }
        
        // Press all modifier keys
        for keyCode in modifierKeyCodes {
            let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)
            keyDown?.post(tap: .cghidEventTap)
        }
        
        // Press all non-modifier keys
        for key in keys {
            let upperKey = key.uppercased()
            
            // Check if it's a non-modifier key
            if !["CMD", "COMMAND", "SHIFT", "OPTION", "ALT", "CONTROL", "CTRL"].contains(upperKey),
               let keyCode = keyCodeMap[upperKey] {
                
                // Press key with modifiers
                let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)
                keyDown?.flags = flags
                keyDown?.post(tap: .cghidEventTap)
                
                // Release key but keep modifiers
                let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
                keyUp?.flags = flags
                keyUp?.post(tap: .cghidEventTap)
                
                // Small pause between key presses
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
        
        // Release all modifier keys in reverse order
        for keyCode in modifierKeyCodes.reversed() {
            let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
            keyUp?.post(tap: .cghidEventTap)
        }
        
        // Small delay after keypress
        Thread.sleep(forTimeInterval: 0.1)
    }
}
