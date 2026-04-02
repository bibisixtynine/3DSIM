//
//  FlightPhysics.swift
//  3DSIM
//
//  Realistic Flight Physics — A320 Fly-By-Wire Normal Law
//  Proper Euler kinematic coupling, sideslip forces, coordinated turns
//

import Foundation
import simd

/// Realistic flight physics engine with A320 FBW control laws
class FlightPhysics {
    
    // MARK: - Aircraft State
    
    /// Position in world coordinates (meters)
    var position: SIMD3<Float> = SIMD3<Float>(0, 2, -150)
    
    /// Velocity in world coordinates (m/s)
    var velocity: SIMD3<Float> = .zero
    
    /// Aircraft orientation (pitch, yaw, roll in radians)
    var orientation: SIMD3<Float> = .zero  // (pitch, yaw, roll)
    
    /// Angular velocity in body frame (p=roll rate, q=pitch rate, r=yaw rate)
    var angularVelocity: SIMD3<Float> = .zero  // (p, q, r) in body frame
    
    // MARK: - Control Inputs (normalized -1 to 1)
    
    var throttle: Float = 0.0       // 0 to 1
    var elevator: Float = 0.0       // -1 (nose down) to 1 (nose up)
    var aileron: Float = 0.0        // -1 (roll left) to 1 (roll right)
    var rudder: Float = 0.0         // -1 (yaw left) to 1 (yaw right)
    var flaps: Float = 0.0          // 0 to 1 (extended)
    var brakes: Float = 0.0         // 0 to 1
    
    // MARK: - Aircraft Parameters
    
    let mass: Float = 1200.0              // kg (light aircraft)
    let wingArea: Float = 16.0            // m²
    let wingSpan: Float = 10.0            // m
    let aspectRatio: Float = 6.25         // wingspan² / area
    
    // Engine
    let maxThrust: Float = 5250.0         // Newtons (turbocharged)
    
    // Aerodynamic coefficients
    let cl0: Float = 0.25                 // Base lift coefficient
    let clAlpha: Float = 5.5              // Lift curve slope (per radian)
    let clFlaps: Float = 0.4              // Additional lift from full flaps
    
    let cd0: Float = 0.027                // Parasitic drag coefficient
    let cdFlaps: Float = 0.02             // Additional drag from full flaps
    
    // Sideslip drag coefficient (fuselage side area effect)
    let sideForceCoeff: Float = 4.0       // Lateral force from sideslip
    
    // Control surface effectiveness
    let elevatorEffectiveness: Float = 0.5
    let aileronEffectiveness: Float = 0.35
    let rudderEffectiveness: Float = 0.3
    
    // Stall parameters
    let stallAngleRadians: Float = 0.28   // ~16 degrees
    let criticalAngle: Float = 0.35       // ~20 degrees - full stall
    
    // Moments of inertia (kg·m²)
    let inertiaX: Float = 1400.0          // Roll
    let inertiaY: Float = 1800.0          // Pitch
    let inertiaZ: Float = 2600.0          // Yaw
    
    // MARK: - Physical Constants
    
    let airDensity: Float = 1.225         // kg/m³ at sea level
    let gravity: Float = 9.81             // m/s²
    
    // MARK: - State Flags
    
    var isOnGround: Bool = true
    var isStalling: Bool = false
    var stallWarning: Bool = false
    
    // MARK: - A320 Fly-By-Wire Normal Law
    
    /// FBW enabled
    var autotrimEnabled: Bool = true
    /// Target pitch attitude captured at stick release (radians)
    var autotrimPitch: Float = 0.0
    /// Target bank angle (0 = wings level on release)
    var autotrimRoll: Float = 0.0
    /// Whether autotrim is currently actively holding attitude
    var autotrimActive: Bool = false
    /// Autotrim gains
    let autotrimPitchGain: Float = 3.0
    let autotrimRollGain: Float = 4.0
    
    // Terrain reference for ground collision
    var terrainGenerator: TerrainGenerator?
    
    // MARK: - Computed Properties
    
    /// Current airspeed in m/s
    var airspeed: Float {
        return length(velocity)
    }
    
    /// Current airspeed in knots
    var airspeedKnots: Float {
        return airspeed * 1.94384
    }
    
    /// Dynamic pressure
    var dynamicPressure: Float {
        return 0.5 * airDensity * airspeed * airspeed
    }
    
    /// Angle of attack in radians
    var angleOfAttack: Float {
        if airspeed < 1.0 { return 0 }
        let bodyVelocity = worldToBody(velocity)
        if abs(bodyVelocity.z) < 0.001 { return 0 }
        return atan2(-bodyVelocity.y, bodyVelocity.z)
    }
    
    /// Sideslip angle in radians (positive = wind from right)
    var sideslipAngle: Float {
        if airspeed < 1.0 { return 0 }
        let bodyVelocity = worldToBody(velocity)
        if abs(bodyVelocity.z) < 0.001 { return 0 }
        return atan2(bodyVelocity.x, bodyVelocity.z)
    }
    
    /// Altitude above ground level
    var altitudeAGL: Float {
        let groundHeight = terrainGenerator?.getHeightAt(x: position.x, z: position.z) ?? 0
        return max(0, position.y - groundHeight)
    }
    
    /// Vertical speed in m/s (positive = climbing)
    var verticalSpeed: Float {
        return velocity.y
    }
    
    /// Heading in degrees (0-360)
    var heading: Float {
        var hdg = orientation.y * 180.0 / .pi
        while hdg < 0 { hdg += 360 }
        while hdg >= 360 { hdg -= 360 }
        return hdg
    }
    
    // MARK: - Physics Update
    
    /// Update physics simulation
    func update(deltaTime: Float) {
        let dt = min(deltaTime, 0.05) // Cap delta time for stability
        
        // Calculate forces and moments
        let (totalForce, totalMoment) = calculateForces()
        
        // Update velocity (F = ma) in world frame
        let acceleration = totalForce / mass
        velocity += acceleration * dt
        
        // Update position
        position += velocity * dt
        
        // Update angular velocity in body frame (M = Iα)
        let angularAcceleration = SIMD3<Float>(
            totalMoment.x / inertiaX,
            totalMoment.y / inertiaY,
            totalMoment.z / inertiaZ
        )
        angularVelocity += angularAcceleration * dt
        
        // Angular damping
        angularVelocity *= 0.95
        
        // --- Orientation update ---
        // Apply angular velocity for pitch and roll (control surfaces)
        orientation.x += angularVelocity.x * dt  // pitch
        orientation.z += angularVelocity.z * dt  // roll
        
        // --- YAW: Track the velocity vector (weathervane) ---
        // In a real aircraft, the nose follows the flight path because of
        // aerodynamic stability. Rather than relying on weak yaw moments,
        // we directly blend the heading toward the velocity heading.
        // This is physically correct: the horizontal lift component curves
        // the velocity, and the fuselage weathervanes into the relative wind.
        if airspeed > 5.0 && !isOnGround {
            // Compute the velocity heading in the horizontal plane
            let vx = velocity.x
            let vz = velocity.z
            let groundSpeed = sqrt(vx * vx + vz * vz)
            
            if groundSpeed > 3.0 {
                let velocityHeading = atan2(vx, vz)
                
                // Compute shortest angular difference
                var headingError = velocityHeading - orientation.y
                while headingError > .pi { headingError -= 2 * .pi }
                while headingError < -.pi { headingError += 2 * .pi }
                
                // Blend rate: how fast the nose tracks the velocity vector
                // Higher = tighter coupling (less slip), lower = more floaty
                // Real aircraft: nearly instant at high speed, lazy at low speed
                let trackingRate: Float = 8.0 * min(airspeed / 25.0, 1.0)
                
                // Also add direct yaw moment contribution (rudder, etc.)
                let momentYawRate = angularVelocity.y * dt
                
                orientation.y += headingError * trackingRate * dt + momentYawRate
            }
        } else {
            // On ground or very slow: use direct angular velocity
            orientation.y += angularVelocity.y * dt
        }
        
        // Normalize angles
        normalizeOrientation()
        
        // Ground collision detection
        handleGroundCollision()
        
        // Update stall status
        updateStallStatus()
    }
    
    /// Calculate all forces and moments acting on the aircraft
    private func calculateForces() -> (force: SIMD3<Float>, moment: SIMD3<Float>) {
        var totalForce: SIMD3<Float> = .zero
        var totalMoment: SIMD3<Float> = .zero
        
        // 1. Gravity (always world-down)
        totalForce += SIMD3<Float>(0, -mass * gravity, 0)
        
        // 2. Thrust (along aircraft forward axis)
        let thrustMagnitude = throttle * maxThrust
        let thrustDirection = bodyToWorld(SIMD3<Float>(0, 0, 1))
        totalForce += thrustDirection * thrustMagnitude
        
        // Skip aerodynamic forces if nearly stationary
        if airspeed > 1.0 {
            // 3. Lift
            let (liftForce, liftMoment) = calculateLift()
            totalForce += liftForce
            totalMoment += liftMoment
            
            // 4. Drag
            totalForce += calculateDrag()
            
            // 5. Side force from sideslip (weathervane effect)
            //    This is critical: it prevents crab flight by pushing the
            //    aircraft sideways back into coordinated flight
            totalForce += calculateSideForce()
            
            // 6. Control surface moments
            totalMoment += calculateControlMoments()
            
            // 7. Stability damping moments
            totalMoment += calculateStabilityMoments()
            
            // 8. A320 FBW autotrim
            if autotrimEnabled && autotrimActive && !isOnGround && !isStalling {
                totalMoment += calculateAutotrimMoments()
            }
        }
        
        // 9. Ground forces
        if isOnGround {
            totalForce += calculateGroundForces()
        }
        
        return (totalForce, totalMoment)
    }
    
    // MARK: - Aerodynamic Forces
    
    /// Calculate lift force with stall modeling
    private func calculateLift() -> (force: SIMD3<Float>, moment: SIMD3<Float>) {
        let aoa = angleOfAttack
        
        var cl: Float
        
        if abs(aoa) < stallAngleRadians {
            cl = cl0 + clAlpha * aoa
        } else if abs(aoa) < criticalAngle {
            let stallFactor = 1.0 - (abs(aoa) - stallAngleRadians) / (criticalAngle - stallAngleRadians)
            let maxCl = cl0 + clAlpha * stallAngleRadians
            cl = maxCl * (0.5 + 0.5 * stallFactor) * (aoa > 0 ? 1 : -1)
        } else {
            let sign: Float = aoa > 0 ? 1 : -1
            cl = 0.8 * sign * cos(aoa * 2)
        }
        
        cl += flaps * clFlaps
        
        let liftMagnitude = cl * dynamicPressure * wingArea
        
        // Lift perpendicular to velocity in aircraft's vertical plane
        let velocityDir = normalize(velocity)
        let rightWing = bodyToWorld(SIMD3<Float>(1, 0, 0))
        let liftDir = normalize(cross(velocityDir, rightWing))
        
        let liftForce = liftDir * liftMagnitude
        let pitchMoment = SIMD3<Float>(-liftMagnitude * 0.005, 0, 0)
        
        return (liftForce, pitchMoment)
    }
    
    /// Calculate drag force
    private func calculateDrag() -> SIMD3<Float> {
        let aoa = angleOfAttack
        
        var cd = cd0
        
        // Induced drag
        let cl = cl0 + clAlpha * min(abs(aoa), stallAngleRadians) * (aoa > 0 ? 1 : -1)
        let e: Float = 0.8
        let cdi = (cl * cl) / (.pi * aspectRatio * e)
        cd += cdi
        
        cd += flaps * cdFlaps
        
        if abs(aoa) > stallAngleRadians {
            cd += 0.5 * (abs(aoa) - stallAngleRadians)
        }
        
        let dragMagnitude = cd * dynamicPressure * wingArea
        return -normalize(velocity) * dragMagnitude
    }
    
    /// Calculate lateral side force from sideslip
    /// This is the key force that prevents crab flight: when the aircraft
    /// slips sideways, the fuselage side area generates a force pushing it
    /// back into the wind, and a yaw moment weathervaning the nose.
    private func calculateSideForce() -> SIMD3<Float> {
        let beta = sideslipAngle
        
        // Side force: proportional to sideslip angle, opposes the slip
        // Acts perpendicular to the aircraft forward axis, in the horizontal plane
        let sideForceMagnitude = -sin(beta) * sideForceCoeff * dynamicPressure * wingArea * 0.1
        
        // Direction: along the body Y axis (right wing direction) projected into world
        let sideDir = bodyToWorld(SIMD3<Float>(1, 0, 0))
        
        return sideDir * sideForceMagnitude
    }
    
    /// Calculate control surface moments
    private func calculateControlMoments() -> SIMD3<Float> {
        let qS = dynamicPressure * wingArea
        
        // Elevator → pitch moment (body q-axis → stored in .x)
        let pitchMoment = elevator * elevatorEffectiveness * qS * 0.5
        
        // Aileron → roll moment (body p-axis → stored in .z)
        let rollMoment = aileron * aileronEffectiveness * qS * wingSpan * 0.1
        
        // Rudder → yaw moment (body r-axis → stored in .y)
        let yawMoment = rudder * rudderEffectiveness * qS * 0.3
        
        // Adverse yaw from aileron
        let adverseYaw = -aileron * 0.06 * qS * 0.1
        
        // In stall, control effectiveness is reduced
        var eff: Float = 1.0
        if abs(angleOfAttack) > stallAngleRadians {
            eff = 0.3
        }
        
        return SIMD3<Float>(
            pitchMoment * eff,
            (yawMoment + adverseYaw) * eff,
            rollMoment * eff
        )
    }
    
    /// Calculate stability and damping moments
    private func calculateStabilityMoments() -> SIMD3<Float> {
        let qS = dynamicPressure * wingArea
        
        // --- Roll stability ---
        // Dihedral effect: bank angle creates a restoring roll moment
        let dihedralMoment = -orientation.z * qS * 0.005
        // Roll rate damping
        let rollDamping = -angularVelocity.z * qS * wingSpan * 0.012
        
        // --- Pitch stability ---
        // Pitch rate damping
        let pitchDamping = -angularVelocity.x * qS * 0.06
        
        // --- Yaw ---
        // Yaw rate damping only (heading tracking is done in update())
        let yawDamping = -angularVelocity.y * qS * 0.03
        
        return SIMD3<Float>(
            pitchDamping,
            yawDamping,
            dihedralMoment + rollDamping
        )
    }
    
    /// A320 FBW autotrim: hold pitch attitude and return to wings-level
    private func calculateAutotrimMoments() -> SIMD3<Float> {
        let qS = dynamicPressure * wingArea
        
        let pitchError = autotrimPitch - orientation.x
        let rollError = autotrimRoll - orientation.z
        
        // PD controller for pitch hold
        let pitchCmd = pitchError * autotrimPitchGain - angularVelocity.x * autotrimPitchGain * 0.6
        let pitchMoment = pitchCmd * qS * 0.15
        
        // PD controller for roll — return to wings level
        let rollCmd = rollError * autotrimRollGain - angularVelocity.z * autotrimRollGain * 0.4
        let rollMoment = rollCmd * qS * 0.08
        
        return SIMD3<Float>(pitchMoment, 0, rollMoment)
    }
    
    // MARK: - Ground Forces
    
    /// Calculate ground forces (normal force, friction)
    private func calculateGroundForces() -> SIMD3<Float> {
        var forces: SIMD3<Float> = .zero
        
        let groundHeight = terrainGenerator?.getHeightAt(x: position.x, z: position.z) ?? 0
        let wheelHeight: Float = 1.5
        
        if position.y < groundHeight + wheelHeight {
            let penetration = groundHeight + wheelHeight - position.y
            let springForce = penetration * 50000.0
            let damperForce = -velocity.y * 5000.0
            
            forces.y += springForce + damperForce
            
            let horizontalSpeed = sqrt(velocity.x * velocity.x + velocity.z * velocity.z)
            if horizontalSpeed > 0.1 {
                let frictionCoeff: Float = brakes > 0.1 ? 0.7 : 0.02
                let normalForce = forces.y
                let frictionMagnitude = frictionCoeff * normalForce * brakes + 100
                
                let horizontalDir = SIMD3<Float>(velocity.x, 0, velocity.z) / horizontalSpeed
                forces -= horizontalDir * min(frictionMagnitude, horizontalSpeed * mass / 0.016)
            }
        }
        
        return forces
    }
    
    /// Handle ground collision
    private func handleGroundCollision() {
        let groundHeight = terrainGenerator?.getHeightAt(x: position.x, z: position.z) ?? 0
        let wheelHeight: Float = 1.5
        
        isOnGround = position.y <= groundHeight + wheelHeight + 0.1
        
        if position.y < groundHeight + wheelHeight {
            position.y = groundHeight + wheelHeight
            
            if velocity.y < 0 {
                velocity.y = 0
            }
            
            orientation.x = max(-0.1, min(0.1, orientation.x))
            orientation.z = max(-0.1, min(0.1, orientation.z))
            angularVelocity.x *= 0.8
            angularVelocity.z *= 0.8
        }
    }
    
    /// Update stall warning and stall status
    private func updateStallStatus() {
        let aoa = abs(angleOfAttack)
        stallWarning = aoa > stallAngleRadians * 0.8 && !isOnGround
        isStalling = aoa > stallAngleRadians && !isOnGround
    }
    
    /// Normalize orientation angles
    private func normalizeOrientation() {
        orientation.x = max(-.pi/2 + 0.1, min(.pi/2 - 0.1, orientation.x))
        
        while orientation.y > .pi { orientation.y -= 2 * .pi }
        while orientation.y < -.pi { orientation.y += 2 * .pi }
        
        while orientation.z > .pi { orientation.z -= 2 * .pi }
        while orientation.z < -.pi { orientation.z += 2 * .pi }
    }
    
    // MARK: - Coordinate Transformations
    
    /// Transform from body coordinates to world coordinates
    /// Convention: pitch > 0 = nose UP, yaw > 0 = nose RIGHT, roll > 0 = right wing DOWN
    func bodyToWorld(_ v: SIMD3<Float>) -> SIMD3<Float> {
        let pitch = -orientation.x  // Negate: internal rotation uses math convention
        let yaw = orientation.y
        let roll = orientation.z
        
        let cosPitch = cos(pitch)
        let sinPitch = sin(pitch)
        let cosYaw = cos(yaw)
        let sinYaw = sin(yaw)
        let cosRoll = cos(roll)
        let sinRoll = sin(roll)
        
        // Combined rotation (yaw * pitch * roll)
        let x = v.x * (cosYaw * cosRoll + sinYaw * sinPitch * sinRoll) +
                v.y * (-cosYaw * sinRoll + sinYaw * sinPitch * cosRoll) +
                v.z * (sinYaw * cosPitch)
        
        let y = v.x * (cosPitch * sinRoll) +
                v.y * (cosPitch * cosRoll) +
                v.z * (-sinPitch)
        
        let z = v.x * (-sinYaw * cosRoll + cosYaw * sinPitch * sinRoll) +
                v.y * (sinYaw * sinRoll + cosYaw * sinPitch * cosRoll) +
                v.z * (cosYaw * cosPitch)
        
        return SIMD3<Float>(x, y, z)
    }
    
    /// Transform from world coordinates to body coordinates
    /// Convention: pitch > 0 = nose UP, yaw > 0 = nose RIGHT, roll > 0 = right wing DOWN
    func worldToBody(_ v: SIMD3<Float>) -> SIMD3<Float> {
        let pitch = -orientation.x  // Negate: match bodyToWorld convention
        let yaw = orientation.y
        let roll = orientation.z
        
        let cosPitch = cos(pitch)
        let sinPitch = sin(pitch)
        let cosYaw = cos(yaw)
        let sinYaw = sin(yaw)
        let cosRoll = cos(roll)
        let sinRoll = sin(roll)
        
        // Inverse rotation (transpose)
        let x = v.x * (cosYaw * cosRoll + sinYaw * sinPitch * sinRoll) +
                v.y * (cosPitch * sinRoll) +
                v.z * (-sinYaw * cosRoll + cosYaw * sinPitch * sinRoll)
        
        let y = v.x * (-cosYaw * sinRoll + sinYaw * sinPitch * cosRoll) +
                v.y * (cosPitch * cosRoll) +
                v.z * (sinYaw * sinRoll + cosYaw * sinPitch * cosRoll)
        
        let z = v.x * (sinYaw * cosPitch) +
                v.y * (-sinPitch) +
                v.z * (cosYaw * cosPitch)
        
        return SIMD3<Float>(x, y, z)
    }
    
    /// Get rotation quaternion for entity orientation
    /// Negates pitch to match RealityKit convention (positive X rotation = nose down)
    func getRotationQuaternion() -> simd_quatf {
        let qPitch = simd_quatf(angle: -orientation.x, axis: SIMD3<Float>(1, 0, 0))
        let qYaw = simd_quatf(angle: orientation.y, axis: SIMD3<Float>(0, 1, 0))
        let qRoll = simd_quatf(angle: orientation.z, axis: SIMD3<Float>(0, 0, 1))
        
        return qYaw * qPitch * qRoll
    }
    
    // MARK: - Reset
    
    /// Reset aircraft to starting position on runway
    func resetToRunway() {
        position = SIMD3<Float>(0, 2, -150)
        velocity = .zero
        orientation = .zero
        angularVelocity = .zero
        throttle = 0
        elevator = 0
        aileron = 0
        rudder = 0
        flaps = 0
        brakes = 1.0
        isOnGround = true
        isStalling = false
        stallWarning = false
        autotrimActive = false
    }
}
