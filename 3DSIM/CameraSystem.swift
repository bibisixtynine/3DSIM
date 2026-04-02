//
//  CameraSystem.swift
//  3DSIM
//
//  Camera System with Cockpit and Chase Views
//

import SwiftUI
import RealityKit
import simd

/// Camera view modes
enum CameraMode {
    case cockpit    // First person view from cockpit
    case chase      // Third person view from behind
    case tower      // Fixed tower view
    case free       // Free camera (orbit)
}

/// Manages camera positioning and transitions for flight simulator
class CameraSystem {
    
    /// Current camera mode
    var currentMode: CameraMode = .chase
    
    /// Camera entity reference
    var cameraEntity: Entity?
    
    /// Reference to flight physics for position/orientation
    weak var flightPhysics: FlightPhysics?
    
    // Camera offsets
    let cockpitOffset: SIMD3<Float> = SIMD3<Float>(0, 1.0, 2.0)  // Pilot eye position
    let chaseOffset: SIMD3<Float> = SIMD3<Float>(0, 5, -20)       // Behind and above
    let chaseDistance: Float = 20.0
    let chaseHeight: Float = 5.0
    
    // Tower camera position
    let towerPosition: SIMD3<Float> = SIMD3<Float>(100, 30, -50)
    
    // Smooth camera interpolation
    private var currentCameraPosition: SIMD3<Float> = .zero
    private var currentCameraTarget: SIMD3<Float> = .zero
    private let smoothingFactor: Float = 0.1
    
    // Free camera state
    var freeCameraYaw: Float = 0
    var freeCameraPitch: Float = 0.3
    var freeCameraDistance: Float = 30
    var freeCameraTarget: SIMD3<Float> = .zero
    
    init() {}
    
    /// Setup camera entity
    func setupCamera(in content: any RealityViewContentProtocol) -> Entity {
        let camera = Entity()
        camera.name = "MainCamera"
        camera.components.set(PerspectiveCameraComponent())
        content.add(camera)
        cameraEntity = camera
        return camera
    }
    
    /// Update camera position based on current mode
    func update(deltaTime: Float) {
        guard let camera = cameraEntity,
              let physics = flightPhysics else { return }
        
        var targetPosition: SIMD3<Float>
        var lookAtTarget: SIMD3<Float>
        
        switch currentMode {
        case .cockpit:
            (targetPosition, lookAtTarget) = calculateCockpitView(physics: physics)
            
        case .chase:
            (targetPosition, lookAtTarget) = calculateChaseView(physics: physics)
            
        case .tower:
            targetPosition = towerPosition
            lookAtTarget = physics.position
            
        case .free:
            (targetPosition, lookAtTarget) = calculateFreeView(physics: physics)
        }
        
        // Smooth camera movement (except cockpit which should be rigid)
        if currentMode == .cockpit {
            // Cockpit: camera is rigidly attached to aircraft — inherits full orientation
            // so the horizon tilts when the aircraft banks (like a real cockpit)
            camera.position = targetPosition
            let aircraftQuat = physics.getRotationQuaternion()
            // Rotate 180° around Y because camera looks toward -Z but aircraft forward is +Z
            let flipToCamera = simd_quatf(angle: .pi, axis: SIMD3<Float>(0, 1, 0))
            camera.orientation = aircraftQuat * flipToCamera
        } else {
            currentCameraPosition = mix(currentCameraPosition, targetPosition, t: smoothingFactor)
            currentCameraTarget = mix(currentCameraTarget, lookAtTarget, t: smoothingFactor)
            
            // Apply camera transform
            camera.position = currentCameraPosition
            camera.look(at: currentCameraTarget, from: currentCameraPosition, relativeTo: nil)
        }
    }
    
    /// Calculate cockpit view position and orientation
    private func calculateCockpitView(physics: FlightPhysics) -> (position: SIMD3<Float>, target: SIMD3<Float>) {
        // Transform cockpit offset to world coordinates
        let worldOffset = physics.bodyToWorld(cockpitOffset)
        let position = physics.position + worldOffset
        
        // Look forward along aircraft heading
        let forwardDir = physics.bodyToWorld(SIMD3<Float>(0, 0, 10))
        let target = position + forwardDir
        
        return (position, target)
    }
    
    /// Calculate chase view position and orientation
    private func calculateChaseView(physics: FlightPhysics) -> (position: SIMD3<Float>, target: SIMD3<Float>) {
        // Chase camera follows behind the aircraft
        let backOffset = physics.bodyToWorld(SIMD3<Float>(0, chaseHeight, -chaseDistance))
        var position = physics.position + backOffset
        
        // Keep camera above ground
        position.y = max(position.y, physics.position.y + 3)
        
        // Look at aircraft
        let target = physics.position + SIMD3<Float>(0, 1, 0)
        
        return (position, target)
    }
    
    /// Calculate free camera view (orbit around target)
    private func calculateFreeView(physics: FlightPhysics) -> (position: SIMD3<Float>, target: SIMD3<Float>) {
        // Update target to follow aircraft loosely
        freeCameraTarget = mix(freeCameraTarget, physics.position, t: 0.02)
        
        // Calculate orbit position
        let x = cos(freeCameraYaw) * cos(freeCameraPitch) * freeCameraDistance
        let y = sin(freeCameraPitch) * freeCameraDistance
        let z = sin(freeCameraYaw) * cos(freeCameraPitch) * freeCameraDistance
        
        let position = freeCameraTarget + SIMD3<Float>(x, y, z)
        
        return (position, freeCameraTarget)
    }
    
    /// Cycle to next camera mode
    func cycleMode() {
        switch currentMode {
        case .chase:
            currentMode = .cockpit
        case .cockpit:
            currentMode = .tower
        case .tower:
            currentMode = .free
        case .free:
            currentMode = .chase
        }
    }
    
    /// Set specific camera mode
    func setMode(_ mode: CameraMode) {
        currentMode = mode
        
        // Reset smooth positions to avoid jumps
        if let physics = flightPhysics {
            switch mode {
            case .cockpit:
                let (pos, target) = calculateCockpitView(physics: physics)
                currentCameraPosition = pos
                currentCameraTarget = target
            case .chase:
                let (pos, target) = calculateChaseView(physics: physics)
                currentCameraPosition = pos
                currentCameraTarget = target
            case .tower:
                currentCameraPosition = towerPosition
                currentCameraTarget = physics.position
            case .free:
                freeCameraTarget = physics.position
                freeCameraDistance = 50
                freeCameraYaw = physics.orientation.y + .pi
                freeCameraPitch = 0.2
            }
        }
    }
    
    /// Adjust free camera with mouse/trackpad
    func adjustFreeCamera(deltaYaw: Float, deltaPitch: Float) {
        freeCameraYaw += deltaYaw
        freeCameraPitch = max(-0.8, min(1.4, freeCameraPitch + deltaPitch))
    }
    
    /// Zoom free camera
    func zoomFreeCamera(delta: Float) {
        freeCameraDistance = max(10, min(200, freeCameraDistance + delta))
    }
    
    /// Get camera mode display name
    var modeName: String {
        switch currentMode {
        case .cockpit: return "Cockpit"
        case .chase: return "Chase"
        case .tower: return "Tower"
        case .free: return "Free"
        }
    }
}

/// Linear interpolation helper
func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, t: Float) -> SIMD3<Float> {
    return a + (b - a) * t
}
