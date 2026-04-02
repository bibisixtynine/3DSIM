//
//  InputController.swift
//  3DSIM
//
//  Keyboard and Mouse Input Handler for Flight Controls
//  AZERTY Keyboard Layout Support
//

import SwiftUI
import Combine
import GameController
import AppKit

/// Handles keyboard and game controller input for flight simulation
/// Uses AZERTY keyboard layout
class InputController: ObservableObject {
    
    // Control state
    @Published var throttleInput: Float = 0      // -1 to 1 (decrease/increase)
    @Published var pitchInput: Float = 0         // -1 to 1 (down/up)
    @Published var rollInput: Float = 0          // -1 to 1 (left/right)
    @Published var rudderInput: Float = 0        // -1 to 1 (left/right)
    @Published var flapsInput: Float = 0         // -1 to 1 (retract/extend)
    @Published var brakesInput: Float = 0        // 0 to 1
    
    // Virtual control inputs (from UI)
    @Published var virtualThrottle: Float = 0
    @Published var virtualPitch: Float = 0
    @Published var virtualRoll: Float = 0
    @Published var virtualRudder: Float = 0
    
    // Key states
    private var pressedKeys: Set<UInt16> = []
    
    // AZERTY Key codes
    // Z = up (was W on QWERTY)
    // S = down
    // Q = left (was A on QWERTY)
    // D = right
    private let keyZ: UInt16 = 6       // Throttle up (AZERTY: Z)
    private let keyS: UInt16 = 1       // Throttle down
    private let keyQ: UInt16 = 12      // Rudder left (AZERTY: Q)
    private let keyD: UInt16 = 2       // Rudder right
    private let keyF: UInt16 = 3       // Flaps
    private let keyB: UInt16 = 11      // Brakes
    private let keyC: UInt16 = 8       // Camera
    private let keyV: UInt16 = 9       // View toggle
    private let keyP: UInt16 = 35      // Pause
    private let keyR: UInt16 = 15      // Reset
    private let keyUp: UInt16 = 126    // Pitch up
    private let keyDown: UInt16 = 125  // Pitch down
    private let keyLeft: UInt16 = 123  // Roll left
    private let keyRight: UInt16 = 124 // Roll right
    private let keySpace: UInt16 = 49  // Brakes
    
    // Also support QWERTY for compatibility
    private let keyW: UInt16 = 13      // Throttle up (QWERTY: W)
    private let keyA: UInt16 = 0       // Rudder left (QWERTY: A)
    
    // Callbacks
    var onCycleCamera: (() -> Void)?
    var onToggleCockpitChase: (() -> Void)?
    var onTogglePause: (() -> Void)?
    var onReset: (() -> Void)?
    
    // Game controller
    private var gameController: GCController?
    
    init() {
        setupGameControllerObservers()
    }
    
    /// Handle key down event
    func keyDown(keyCode: UInt16) {
        pressedKeys.insert(keyCode)
        
        // One-shot actions
        switch keyCode {
        case keyC:
            onCycleCamera?()
        case keyV:
            onToggleCockpitChase?()
        case keyP:
            onTogglePause?()
        case keyR:
            onReset?()
        default:
            break
        }
        
        updateInputsFromKeys()
    }
    
    /// Handle key up event
    func keyUp(keyCode: UInt16) {
        pressedKeys.remove(keyCode)
        updateInputsFromKeys()
    }
    
    /// Update input values from current key states
    private func updateInputsFromKeys() {
        // Throttle (Z/S for AZERTY, also W/S for QWERTY)
        throttleInput = 0
        if pressedKeys.contains(keyZ) || pressedKeys.contains(keyW) { throttleInput += 1 }
        if pressedKeys.contains(keyS) { throttleInput -= 1 }
        
        // Pitch (Up/Down arrows)
        pitchInput = 0
        if pressedKeys.contains(keyUp) { pitchInput += 1 }
        if pressedKeys.contains(keyDown) { pitchInput -= 1 }
        
        // Roll (Left/Right arrows)
        rollInput = 0
        if pressedKeys.contains(keyRight) { rollInput += 1 }
        if pressedKeys.contains(keyLeft) { rollInput -= 1 }
        
        // Rudder (Q/D for AZERTY, also A/D for QWERTY)
        rudderInput = 0
        if pressedKeys.contains(keyD) { rudderInput += 1 }
        if pressedKeys.contains(keyQ) || pressedKeys.contains(keyA) { rudderInput -= 1 }
        
        // Flaps (F to toggle)
        flapsInput = pressedKeys.contains(keyF) ? 1 : 0
        
        // Brakes (B or Space)
        brakesInput = (pressedKeys.contains(keyB) || pressedKeys.contains(keySpace)) ? 1 : 0
    }
    
    /// Apply inputs to flight physics (combines keyboard, virtual controls, and gamepad)
    func applyInputs(to physics: FlightPhysics, deltaTime: Float) {
        // Check if virtual controls are being used (joystick position != 0)
        let usingVirtualJoystick = virtualPitch != 0 || virtualRoll != 0
        let usingVirtualRudder = virtualRudder != 0
        let usingVirtualThrottle = virtualThrottle > 0
        
        // THROTTLE
        if usingVirtualThrottle {
            // Virtual throttle: direct position control
            physics.throttle = virtualThrottle
        } else if throttleInput != 0 {
            // Keyboard: incremental control
            let throttleRate: Float = 0.5
            physics.throttle += throttleInput * throttleRate * deltaTime
            physics.throttle = max(0, min(1, physics.throttle))
        }
        
        // A320 FBW NORMAL LAW
        // Pitch: stick commands pitch rate / load factor. Releasing stick holds current attitude.
        // Roll:  stick commands roll rate. Releasing stick returns to wings level.
        
        var pitchCmd: Float = 0
        var rollCmd: Float = 0
        
        if usingVirtualJoystick {
            pitchCmd = virtualPitch
            rollCmd = virtualRoll
        } else {
            pitchCmd = pitchInput
            rollCmd = rollInput
        }
        
        let hasStickInput = abs(pitchCmd) > 0.02 || abs(rollCmd) > 0.02
        
        if hasStickInput {
            // Pilot commanding — disengage autotrim
            physics.autotrimActive = false
            
            // PITCH: stick deflection commands pitch rate (like A320 normal law)
            // Full stick = ~4°/s pitch rate → converted to elevator proportionally
            physics.elevator = pitchCmd * 0.8
            
            // ROLL: stick deflection commands roll rate (like A320 normal law)
            // Full stick = ~15°/s roll rate, FBW limits bank to 67°
            physics.aileron = rollCmd * 0.8
            
        } else {
            // Stick released — engage FBW attitude hold
            if !physics.autotrimActive && physics.autotrimEnabled && !physics.isOnGround {
                // Capture current pitch as trim target
                physics.autotrimPitch = physics.orientation.x
                // A320 normal law: bank angles < 33° → return to wings level
                // Bank angles > 33° → hold current bank (pilot intended it)
                if abs(physics.orientation.z) < 0.58 { // ~33°
                    physics.autotrimRoll = 0
                } else {
                    physics.autotrimRoll = physics.orientation.z
                }
                physics.autotrimActive = true
            }
            
            // Neutralize surfaces — autotrim handles stability
            physics.elevator *= 0.8
            if abs(physics.elevator) < 0.005 { physics.elevator = 0 }
            physics.aileron *= 0.8
            if abs(physics.aileron) < 0.005 { physics.aileron = 0 }
        }
        
        // RUDDER
        if usingVirtualRudder {
            // Virtual rudder: DIRECT position control
            physics.rudder = virtualRudder
        } else if rudderInput != 0 {
            // Keyboard: direct control while held
            physics.rudder = rudderInput
        } else {
            // No input: return to neutral gradually
            physics.rudder *= 0.9
            if abs(physics.rudder) < 0.01 { physics.rudder = 0 }
        }
        
        // Flaps (toggle steps)
        if flapsInput > 0 {
            physics.flaps += 0.5 * deltaTime
            if physics.flaps > 1 { physics.flaps = 0 }
        }
        
        // Brakes
        physics.brakes = brakesInput
        
        // Clamp all control surfaces
        physics.elevator = max(-1, min(1, physics.elevator))
        physics.aileron = max(-1, min(1, physics.aileron))
        physics.rudder = max(-1, min(1, physics.rudder))
        
        // Apply game controller input if connected
        applyGameControllerInput(to: physics, deltaTime: deltaTime)
    }
    
    // MARK: - Game Controller Support
    
    private func setupGameControllerObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(controllerConnected),
            name: .GCControllerDidConnect,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(controllerDisconnected),
            name: .GCControllerDidDisconnect,
            object: nil
        )
        
        // Check for already connected controllers
        if let controller = GCController.controllers().first {
            gameController = controller
            setupControllerHandlers(controller)
        }
    }
    
    @objc private func controllerConnected(_ notification: Notification) {
        if let controller = notification.object as? GCController {
            gameController = controller
            setupControllerHandlers(controller)
        }
    }
    
    @objc private func controllerDisconnected(_ notification: Notification) {
        if let controller = notification.object as? GCController,
           controller == gameController {
            gameController = nil
        }
    }
    
    private func setupControllerHandlers(_ controller: GCController) {
        controller.extendedGamepad?.buttonA.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { self?.onToggleCockpitChase?() }
        }
        
        controller.extendedGamepad?.buttonB.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { self?.onCycleCamera?() }
        }
        
        controller.extendedGamepad?.buttonMenu.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { self?.onTogglePause?() }
        }
    }
    
    private func applyGameControllerInput(to physics: FlightPhysics, deltaTime: Float) {
        guard let gamepad = gameController?.extendedGamepad else { return }
        
        let pitch = -gamepad.leftThumbstick.yAxis.value
        let roll = gamepad.leftThumbstick.xAxis.value
        let rudder = gamepad.rightThumbstick.xAxis.value
        let throttleUp = gamepad.rightTrigger.value
        let throttleDown = gamepad.leftTrigger.value
        
        let deadzone: Float = 0.1
        
        if abs(pitch) > deadzone {
            physics.elevator = pitch
        }
        if abs(roll) > deadzone {
            physics.aileron = roll
        }
        if abs(rudder) > deadzone {
            physics.rudder = rudder
        }
        
        physics.throttle += (throttleUp - throttleDown) * 0.5 * deltaTime
        physics.throttle = max(0, min(1, physics.throttle))
        
        if gamepad.leftShoulder.isPressed {
            physics.flaps = max(0, physics.flaps - deltaTime)
        }
        if gamepad.rightShoulder.isPressed {
            physics.flaps = min(1, physics.flaps + deltaTime)
        }
        
        if gamepad.buttonX.isPressed {
            physics.brakes = 1
        }
    }
}

/// SwiftUI view modifier for keyboard handling
struct KeyboardInputModifier: ViewModifier {
    let inputController: InputController
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    inputController.keyDown(keyCode: event.keyCode)
                    return event
                }
                NSEvent.addLocalMonitorForEvents(matching: .keyUp) { event in
                    inputController.keyUp(keyCode: event.keyCode)
                    return event
                }
            }
    }
}

extension View {
    func handleKeyboardInput(with controller: InputController) -> some View {
        modifier(KeyboardInputModifier(inputController: controller))
    }
}
