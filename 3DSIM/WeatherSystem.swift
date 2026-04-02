//
//  WeatherSystem.swift
//  3DSIM
//
//  Premium Cartoon Weather: Clouds, Storms, Dynamic Atmosphere
//

import Foundation
import RealityKit
import simd
import AppKit

private typealias UIColor = NSColor

/// Weather condition types
enum WeatherCondition {
    case clear
    case partlyCloudy
    case overcast
    case storm
}

/// Premium cartoon weather system with volumetric clouds and storms
class WeatherSystem {
    
    // Cloud configuration
    let numberOfClouds = 60
    let cloudBaseAltitude: Float = 200.0
    let cloudTopAltitude: Float = 400.0
    let stormCloudAltitude: Float = 150.0
    
    // Weather state
    var currentCondition: WeatherCondition = .partlyCloudy
    var stormTimer: Float = 0
    var stormActive: Bool = false
    var stormDuration: Float = 0
    var nextStormIn: Float = 120.0  // Seconds until next storm
    
    // Lightning
    var lightningTimer: Float = 0
    var lightningActive: Bool = false
    var lightningEntity: Entity?
    var lightningFlashIntensity: Float = 0
    
    // Cloud entities for animation
    var clouds: [(entity: Entity, basePosition: SIMD3<Float>, speed: SIMD3<Float>, scale: Float)] = []
    var stormClouds: [(entity: Entity, basePosition: SIMD3<Float>)] = []
    
    // Rain entities
    var rainEntity: Entity?
    
    private var random: SeededRandomGenerator
    
    init(seed: UInt64 = 99999) {
        self.random = SeededRandomGenerator(seed: seed)
    }
    
    /// Generate the complete weather system
    func generateWeather() -> Entity {
        let weatherRoot = Entity()
        weatherRoot.name = "Weather"
        
        // Generate clouds
        let cloudEntities = generateClouds()
        weatherRoot.addChild(cloudEntities)
        
        // Generate storm clouds (hidden initially)
        let stormCloudEntities = generateStormClouds()
        weatherRoot.addChild(stormCloudEntities)
        
        // Create lightning entity (hidden initially)
        let lightning = createLightning()
        weatherRoot.addChild(lightning)
        lightningEntity = lightning
        
        // Create rain system (hidden initially)
        let rain = createRainSystem()
        weatherRoot.addChild(rain)
        rainEntity = rain
        rain.isEnabled = false
        
        return weatherRoot
    }
    
    // MARK: - Clouds
    
    /// Generate premium cartoon clouds
    private func generateClouds() -> Entity {
        let cloudRoot = Entity()
        cloudRoot.name = "Clouds"
        
        clouds.removeAll()
        
        for i in 0..<numberOfClouds {
            let cloud = createCartoonCloud(index: i)
            
            let x = Float.random(in: -1500...1500, using: &random)
            let z = Float.random(in: -1500...1500, using: &random)
            let y = Float.random(in: cloudBaseAltitude...cloudTopAltitude, using: &random)
            let scale = Float.random(in: 0.6...2.0, using: &random)
            
            cloud.position = SIMD3<Float>(x, y, z)
            cloud.scale = SIMD3<Float>(scale, scale * 0.6, scale)
            cloudRoot.addChild(cloud)
            
            let speed = SIMD3<Float>(
                Float.random(in: 2...8, using: &random),
                0,
                Float.random(in: -1...1, using: &random)
            )
            
            clouds.append((entity: cloud, basePosition: cloud.position, speed: speed, scale: scale))
        }
        
        return cloudRoot
    }
    
    /// Create a single cartoon cloud from overlapping soft spheres
    private func createCartoonCloud(index: Int) -> Entity {
        let cloudEntity = Entity()
        cloudEntity.name = "Cloud_\(index)"
        
        // Cartoon clouds: bright white, soft, puffy
        let cloudWhite = UIColor(red: 0.98, green: 0.98, blue: 1.0, alpha: 0.92)
        let cloudGray = UIColor(red: 0.88, green: 0.90, blue: 0.94, alpha: 0.88)
        
        var whiteMat = UnlitMaterial()
        whiteMat.color = .init(tint: cloudWhite)
        
        var grayMat = UnlitMaterial()
        grayMat.color = .init(tint: cloudGray)
        
        // Create cloud from multiple overlapping spheres for that cartoon puffy look
        let numPuffs = Int.random(in: 5...12, using: &random)
        let cloudLength = Float.random(in: 30...80, using: &random)
        let cloudWidth = Float.random(in: 20...40, using: &random)
        
        for _ in 0..<numPuffs {
            let radius = Float.random(in: 10...25, using: &random)
            let puffMesh = MeshResource.generateSphere(radius: radius)
            
            let isBottom = Float.random(in: 0...1, using: &random) < 0.3
            let material = isBottom ? grayMat : whiteMat
            
            let puff = Entity()
            puff.components.set(ModelComponent(mesh: puffMesh, materials: [material]))
            puff.position = SIMD3<Float>(
                Float.random(in: -cloudLength/2...cloudLength/2, using: &random),
                Float.random(in: -5...10, using: &random),
                Float.random(in: -cloudWidth/2...cloudWidth/2, using: &random)
            )
            
            // Slightly flatten clouds vertically for cartoon look
            puff.scale = SIMD3<Float>(1.0, Float.random(in: 0.4...0.7, using: &random), 1.0)
            cloudEntity.addChild(puff)
        }
        
        return cloudEntity
    }
    
    // MARK: - Storm Clouds
    
    /// Generate dark storm clouds
    private func generateStormClouds() -> Entity {
        let stormRoot = Entity()
        stormRoot.name = "StormClouds"
        
        stormClouds.removeAll()
        
        // Create a cluster of dark storm clouds
        for i in 0..<15 {
            let cloud = createStormCloud(index: i)
            
            let x = Float.random(in: -600...600, using: &random)
            let z = Float.random(in: -600...600, using: &random)
            let y = stormCloudAltitude + Float.random(in: 0...50, using: &random)
            
            cloud.position = SIMD3<Float>(x, y, z)
            cloud.isEnabled = false  // Hidden until storm
            stormRoot.addChild(cloud)
            
            stormClouds.append((entity: cloud, basePosition: cloud.position))
        }
        
        return stormRoot
    }
    
    /// Create a dark, menacing storm cloud
    private func createStormCloud(index: Int) -> Entity {
        let cloudEntity = Entity()
        cloudEntity.name = "StormCloud_\(index)"
        
        let darkColor = UIColor(red: 0.25, green: 0.28, blue: 0.35, alpha: 0.90)
        let veryDarkColor = UIColor(red: 0.15, green: 0.18, blue: 0.25, alpha: 0.92)
        
        var darkMat = UnlitMaterial()
        darkMat.color = .init(tint: darkColor)
        
        var veryDarkMat = UnlitMaterial()
        veryDarkMat.color = .init(tint: veryDarkColor)
        
        let numPuffs = Int.random(in: 8...15, using: &random)
        
        for _ in 0..<numPuffs {
            let radius = Float.random(in: 20...45, using: &random)
            let puffMesh = MeshResource.generateSphere(radius: radius)
            
            let isBottom = Float.random(in: 0...1, using: &random) < 0.4
            
            let puff = Entity()
            puff.components.set(ModelComponent(mesh: puffMesh, materials: [isBottom ? veryDarkMat : darkMat]))
            puff.position = SIMD3<Float>(
                Float.random(in: -50...50, using: &random),
                Float.random(in: -15...10, using: &random),
                Float.random(in: -50...50, using: &random)
            )
            puff.scale = SIMD3<Float>(1.0, Float.random(in: 0.3...0.5, using: &random), 1.0)
            cloudEntity.addChild(puff)
        }
        
        return cloudEntity
    }
    
    // MARK: - Lightning
    
    /// Create lightning flash entity
    private func createLightning() -> Entity {
        let lightningRoot = Entity()
        lightningRoot.name = "Lightning"
        lightningRoot.isEnabled = false
        
        // Lightning bolt (simplified as bright vertical line)
        let boltMesh = MeshResource.generateBox(size: SIMD3<Float>(2.0, 100.0, 2.0))
        var boltMat = UnlitMaterial()
        boltMat.color = .init(tint: UIColor(red: 1.0, green: 1.0, blue: 0.85, alpha: 0.9))
        
        let bolt = Entity()
        bolt.components.set(ModelComponent(mesh: boltMesh, materials: [boltMat]))
        bolt.position.y = 100
        lightningRoot.addChild(bolt)
        
        // Branch
        let branchMesh = MeshResource.generateBox(size: SIMD3<Float>(1.0, 40.0, 1.0))
        let branch = Entity()
        branch.components.set(ModelComponent(mesh: branchMesh, materials: [boltMat]))
        branch.position = SIMD3<Float>(15, 120, 0)
        branch.orientation = simd_quatf(angle: 0.4, axis: SIMD3<Float>(0, 0, 1))
        lightningRoot.addChild(branch)
        
        return lightningRoot
    }
    
    // MARK: - Rain
    
    /// Create rain particle system (simplified with lines)
    private func createRainSystem() -> Entity {
        let rainRoot = Entity()
        rainRoot.name = "Rain"
        
        let rainDropMesh = MeshResource.generateBox(size: SIMD3<Float>(0.05, 2.0, 0.05))
        var rainMat = UnlitMaterial()
        rainMat.color = .init(tint: UIColor(red: 0.6, green: 0.7, blue: 0.85, alpha: 0.4))
        
        // Create a grid of rain drops
        for _ in 0..<200 {
            let drop = Entity()
            drop.components.set(ModelComponent(mesh: rainDropMesh, materials: [rainMat]))
            drop.position = SIMD3<Float>(
                Float.random(in: -100...100),
                Float.random(in: 0...150),
                Float.random(in: -100...100)
            )
            rainRoot.addChild(drop)
        }
        
        return rainRoot
    }
    
    // MARK: - Update
    
    /// Update weather system each frame
    func update(deltaTime: Float, playerPosition: SIMD3<Float>) {
        // Move clouds
        updateClouds(deltaTime: deltaTime)
        
        // Storm timing
        updateStormCycle(deltaTime: deltaTime, playerPosition: playerPosition)
        
        // Lightning flashes during storm
        if stormActive {
            updateLightning(deltaTime: deltaTime, playerPosition: playerPosition)
            updateRain(deltaTime: deltaTime, playerPosition: playerPosition)
        }
    }
    
    /// Animate cloud movement
    private func updateClouds(deltaTime: Float) {
        for i in 0..<clouds.count {
            var cloud = clouds[i]
            
            // Drift clouds
            cloud.basePosition += cloud.speed * deltaTime
            
            // Wrap around when too far
            if cloud.basePosition.x > 1500 { cloud.basePosition.x = -1500 }
            if cloud.basePosition.x < -1500 { cloud.basePosition.x = 1500 }
            if cloud.basePosition.z > 1500 { cloud.basePosition.z = -1500 }
            if cloud.basePosition.z < -1500 { cloud.basePosition.z = 1500 }
            
            cloud.entity.position = cloud.basePosition
            
            clouds[i] = cloud
        }
    }
    
    /// Manage storm cycle (storms appear periodically)
    private func updateStormCycle(deltaTime: Float, playerPosition: SIMD3<Float>) {
        if stormActive {
            stormDuration -= deltaTime
            if stormDuration <= 0 {
                // End storm
                stormActive = false
                nextStormIn = Float.random(in: 90...180)
                
                for sc in stormClouds {
                    sc.entity.isEnabled = false
                }
                rainEntity?.isEnabled = false
                lightningEntity?.isEnabled = false
            }
        } else {
            nextStormIn -= deltaTime
            if nextStormIn <= 0 {
                // Start storm
                stormActive = true
                stormDuration = Float.random(in: 30...60)
                
                for sc in stormClouds {
                    sc.entity.isEnabled = true
                }
                rainEntity?.isEnabled = true
            }
        }
        
        // Move storm clouds relative to player
        if stormActive {
            for i in 0..<stormClouds.count {
                let sc = stormClouds[i]
                var pos = sc.basePosition
                pos.x += playerPosition.x * 0.5
                pos.z += playerPosition.z * 0.5
                sc.entity.position = pos
            }
        }
    }
    
    /// Flash lightning randomly during storms
    private func updateLightning(deltaTime: Float, playerPosition: SIMD3<Float>) {
        lightningTimer -= deltaTime
        
        if lightningActive {
            lightningFlashIntensity -= deltaTime * 8
            if lightningFlashIntensity <= 0 {
                lightningActive = false
                lightningEntity?.isEnabled = false
            }
        }
        
        if lightningTimer <= 0 && !lightningActive {
            // Trigger lightning
            lightningActive = true
            lightningFlashIntensity = 1.0
            lightningTimer = Float.random(in: 3...12)
            
            if let lightning = lightningEntity {
                lightning.isEnabled = true
                lightning.position = SIMD3<Float>(
                    playerPosition.x + Float.random(in: -200...200),
                    0,
                    playerPosition.z + Float.random(in: -200...200)
                )
            }
        }
    }
    
    /// Move rain particles to follow player
    private func updateRain(deltaTime: Float, playerPosition: SIMD3<Float>) {
        guard let rain = rainEntity else { return }
        
        // Center rain around player
        rain.position = SIMD3<Float>(playerPosition.x, playerPosition.y + 50, playerPosition.z)
        
        // Animate rain drops falling
        for child in rain.children {
            child.position.y -= 80 * deltaTime
            if child.position.y < -50 {
                child.position.y = 150
            }
        }
    }
}
