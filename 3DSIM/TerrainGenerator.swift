//
//  TerrainGenerator.swift
//  3DSIM
//
//  Flight Simulator Terrain Generation System - Infinite Terrain
//

import Foundation
import RealityKit
import simd
import AppKit

private typealias UIColor = NSColor

/// Generates infinite procedural terrain with dynamic chunk loading
class TerrainGenerator {
    
    // Terrain configuration
    let chunkWorldSize: Float = 200.0    // Size of each chunk in meters
    let chunkResolution: Int = 20        // Grid points per chunk side
    let maxMountainHeight: Float = 300.0
    let waterLevel: Float = -2.0
    let viewDistance: Int = 5            // Chunks to load in each direction
    
    // Noise parameters for terrain generation
    private let seed: UInt64
    
    // Chunk management
    private var loadedChunks: [ChunkCoord: Entity] = [:]
    private var terrainRoot: Entity?
    private var waterEntity: Entity?
    
    // Chunk coordinate type
    struct ChunkCoord: Hashable {
        let x: Int
        let z: Int
    }
    
    init(seed: UInt64 = 12345) {
        self.seed = seed
    }
    
    /// Generates the initial terrain entity (will be updated dynamically)
    func generateTerrain() -> Entity {
        let terrainEntity = Entity()
        terrainEntity.name = "Terrain"
        terrainRoot = terrainEntity
        
        // Generate water plane (large enough for visible area)
        let water = generateWater()
        terrainEntity.addChild(water)
        waterEntity = water
        
        // Load initial chunks around origin
        updateChunks(playerPosition: SIMD3<Float>(0, 0, 0))
        
        return terrainEntity
    }
    
    /// Update loaded chunks based on player position - call each frame
    func updateChunks(playerPosition: SIMD3<Float>) {
        guard let root = terrainRoot else { return }
        
        // Calculate current chunk
        let currentChunkX = Int(floor(playerPosition.x / chunkWorldSize))
        let currentChunkZ = Int(floor(playerPosition.z / chunkWorldSize))
        
        // Determine which chunks should be loaded
        var neededChunks: Set<ChunkCoord> = []
        for dx in -viewDistance...viewDistance {
            for dz in -viewDistance...viewDistance {
                neededChunks.insert(ChunkCoord(x: currentChunkX + dx, z: currentChunkZ + dz))
            }
        }
        
        // Unload chunks that are too far
        let chunksToRemove = loadedChunks.keys.filter { !neededChunks.contains($0) }
        for coord in chunksToRemove {
            if let entity = loadedChunks[coord] {
                entity.removeFromParent()
                loadedChunks.removeValue(forKey: coord)
            }
        }
        
        // Load new chunks
        for coord in neededChunks {
            if loadedChunks[coord] == nil {
                let chunk = generateChunk(chunkX: coord.x, chunkZ: coord.z)
                root.addChild(chunk)
                loadedChunks[coord] = chunk
            }
        }
        
        // Update water position to follow player
        waterEntity?.position = SIMD3<Float>(playerPosition.x, waterLevel, playerPosition.z)
    }
    
    /// Generates a single terrain chunk at the given chunk coordinates
    private func generateChunk(chunkX: Int, chunkZ: Int) -> Entity {
        let entity = Entity()
        entity.name = "Chunk_\(chunkX)_\(chunkZ)"
        
        let cellSize = chunkWorldSize / Float(chunkResolution)
        let chunkOriginX = Float(chunkX) * chunkWorldSize
        let chunkOriginZ = Float(chunkZ) * chunkWorldSize
        
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []
        
        // Generate vertices
        for z in 0...chunkResolution {
            for x in 0...chunkResolution {
                let worldX = chunkOriginX + Float(x) * cellSize
                let worldZ = chunkOriginZ + Float(z) * cellSize
                let height = getHeightAt(x: worldX, z: worldZ)
                
                positions.append(SIMD3<Float>(worldX, height, worldZ))
                uvs.append(SIMD2<Float>(Float(x) / Float(chunkResolution), Float(z) / Float(chunkResolution)))
            }
        }
        
        // Calculate normals
        for z in 0...chunkResolution {
            for x in 0...chunkResolution {
                let worldX = chunkOriginX + Float(x) * cellSize
                let worldZ = chunkOriginZ + Float(z) * cellSize
                let normal = calculateNormal(x: worldX, z: worldZ, cellSize: cellSize)
                normals.append(normal)
            }
        }
        
        // Generate indices for triangles
        for z in 0..<chunkResolution {
            for x in 0..<chunkResolution {
                let topLeft = UInt32(z * (chunkResolution + 1) + x)
                let topRight = topLeft + 1
                let bottomLeft = UInt32((z + 1) * (chunkResolution + 1) + x)
                let bottomRight = bottomLeft + 1
                
                indices.append(topLeft)
                indices.append(bottomLeft)
                indices.append(topRight)
                
                indices.append(topRight)
                indices.append(bottomLeft)
                indices.append(bottomRight)
            }
        }
        
        // Create mesh
        var meshDescriptor = MeshDescriptor()
        meshDescriptor.positions = MeshBuffer(positions)
        meshDescriptor.normals = MeshBuffer(normals)
        meshDescriptor.textureCoordinates = MeshBuffer(uvs)
        meshDescriptor.primitives = .triangles(indices)
        
        do {
            let mesh = try MeshResource.generate(from: [meshDescriptor])
            
            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(tint: getTerrainColor(chunkX: chunkX, chunkZ: chunkZ))
            material.roughness = .init(floatLiteral: 0.9)
            material.metallic = .init(floatLiteral: 0.0)
            
            entity.components.set(ModelComponent(mesh: mesh, materials: [material]))
        } catch {
            print("Failed to generate terrain chunk: \(error)")
        }
        
        return entity
    }
    
    /// Check if a position is on a road
    func isRoad(x: Float, z: Float) -> Bool {
        // Main highway running east-west
        let highway1 = abs(z - 300) < 6.0
        // Secondary road running north-south
        let highway2 = abs(x - 400) < 5.0
        // Winding country road
        let roadWave = sin(x * 0.008) * 150 + cos(x * 0.003) * 80
        let countryRoad = abs(z - roadWave - 100) < 4.0
        // Ring road around airport area
        let distFromCenter = sqrt(x * x + z * z)
        let ringRoad = abs(distFromCenter - 600) < 5.0
        
        return highway1 || highway2 || countryRoad || ringRoad
    }
    
    /// Check if position is in a lake zone
    func isLake(x: Float, z: Float) -> Bool {
        // Several lakes at fixed positions
        let lake1Center = SIMD2<Float>(-500, 400)
        let lake1Radius: Float = 120
        let d1 = sqrt(pow(x - lake1Center.x, 2) + pow(z - lake1Center.y, 2))
        
        let lake2Center = SIMD2<Float>(600, -300)
        let lake2Radius: Float = 80
        let d2 = sqrt(pow(x - lake2Center.x, 2) + pow(z - lake2Center.y, 2))
        
        let lake3Center = SIMD2<Float>(-200, -600)
        let lake3Radius: Float = 100
        let d3 = sqrt(pow(x - lake3Center.x, 2) + pow(z - lake3Center.y, 2))
        
        return d1 < lake1Radius || d2 < lake2Radius || d3 < lake3Radius
    }
    
    /// Check if position is in a forest zone
    func isForest(x: Float, z: Float) -> Bool {
        let forestNoise = noise2D(x: x * 0.005 + 50, y: z * 0.005 + 50)
        let distFromAirport = sqrt(x * x + z * z)
        return forestNoise > 0.1 && distFromAirport > 300 && !isRoad(x: x, z: z) && !isLake(x: x, z: z)
    }
    
    /// Gets terrain color - premium cartoon style with vibrant colors
    private func getTerrainColor(chunkX: Int, chunkZ: Int) -> UIColor {
        let centerX = Float(chunkX) * chunkWorldSize + chunkWorldSize / 2
        let centerZ = Float(chunkZ) * chunkWorldSize + chunkWorldSize / 2
        let height = getHeightAt(x: centerX, z: centerZ)
        
        // Roads - dark asphalt gray
        if isRoad(x: centerX, z: centerZ) && height > waterLevel + 1 && height < 80 {
            return UIColor(red: 0.25, green: 0.25, blue: 0.28, alpha: 1.0)
        }
        
        // Snow caps - bright white with slight blue tint (cartoon)
        if height > maxMountainHeight * 0.75 {
            return UIColor(red: 0.95, green: 0.97, blue: 1.0, alpha: 1.0)
        }
        // Rocky mountains - warm purple-gray (cartoon style)
        else if height > maxMountainHeight * 0.5 {
            return UIColor(red: 0.55, green: 0.48, blue: 0.52, alpha: 1.0)
        }
        // Sandy beach near water
        else if height < waterLevel + 3 && height > waterLevel - 1 {
            return UIColor(red: 0.93, green: 0.87, blue: 0.65, alpha: 1.0)
        }
        // Forest zones - rich dark green cartoon style
        else if isForest(x: centerX, z: centerZ) {
            let variation = noise2D(x: centerX * 0.02, y: centerZ * 0.02)
            let green = 0.45 + CGFloat(variation * 0.1)
            return UIColor(red: 0.15, green: green, blue: 0.18, alpha: 1.0)
        }
        // Default grass - vibrant cartoon green with warm variation
        else {
            let variation = noise2D(x: centerX * 0.01, y: centerZ * 0.01)
            let green = 0.55 + CGFloat(variation * 0.12)
            let red = 0.30 + CGFloat(variation * 0.05)
            return UIColor(red: red, green: green, blue: 0.22, alpha: 1.0)
        }
    }
    
    /// Calculates height at a given world position using multiple octaves of noise
    func getHeightAt(x: Float, z: Float) -> Float {
        var height: Float = 0.0
        
        // Multiple octaves of noise for natural looking terrain
        let octaves = 5
        var amplitude: Float = 1.0
        var frequency: Float = 0.002
        var maxValue: Float = 0.0
        
        for _ in 0..<octaves {
            height += noise2D(x: x * frequency, y: z * frequency) * amplitude
            maxValue += amplitude
            amplitude *= 0.5
            frequency *= 2.0
        }
        
        height = height / maxValue
        
        // Apply exponential for sharper peaks
        height = pow(max(0, height), 1.5)
        
        // Scale to max height
        height *= maxMountainHeight
        
        // Create depressions for designated lakes
        if isLake(x: x, z: z) {
            height = min(height, waterLevel - 3.0)
        }
        
        // Create valleys for natural water features (but not near airport)
        let distFromAirport = sqrt(x * x + z * z)
        if distFromAirport > 400 {
            let valleyNoise = noise2D(x: x * 0.003 + 100, y: z * 0.003 + 100)
            if valleyNoise < -0.3 {
                height = min(height, waterLevel - 2 + (valleyNoise + 0.3) * 10)
            }
        }
        
        // Flatten terrain under roads
        if isRoad(x: x, z: z) && distFromAirport > 200 {
            let roadHeight = max(waterLevel + 1.5, height * 0.3)
            height = min(height, roadHeight)
        }
        
        // Flatten area around airport - large flat zone with smooth transition
        // Airport zone: runway is 400m long, 30m wide, plus buildings to the side
        let airportWidth: Float = 200.0   // Total width of flat area
        let airportLength: Float = 500.0  // Total length of flat area
        let transitionZone: Float = 150.0 // Gradual transition zone
        
        let distX = abs(x)
        let distZ = abs(z)
        
        // Check if we're in or near the airport zone
        if distX < airportWidth + transitionZone && distZ < airportLength + transitionZone {
            var flatteningFactor: Float = 0.0
            
            if distX < airportWidth && distZ < airportLength {
                // Inside airport - completely flat
                flatteningFactor = 1.0
            } else {
                // In transition zone - smooth blend
                let transitionX = max(0, distX - airportWidth) / transitionZone
                let transitionZ = max(0, distZ - airportLength) / transitionZone
                let transitionDist = max(transitionX, transitionZ)
                
                // Smooth step function for gradual transition
                flatteningFactor = 1.0 - (transitionDist * transitionDist * (3.0 - 2.0 * transitionDist))
                flatteningFactor = max(0, flatteningFactor)
            }
            
            // Blend between terrain height and flat ground (elevation 0)
            height = height * (1.0 - flatteningFactor) + 0.0 * flatteningFactor
        }
        
        return height
    }
    
    /// Calculates normal vector at a terrain point
    private func calculateNormal(x: Float, z: Float, cellSize: Float) -> SIMD3<Float> {
        let delta: Float = cellSize * 0.5
        
        let hL = getHeightAt(x: x - delta, z: z)
        let hR = getHeightAt(x: x + delta, z: z)
        let hD = getHeightAt(x: x, z: z - delta)
        let hU = getHeightAt(x: x, z: z + delta)
        
        let normal = SIMD3<Float>(hL - hR, 2.0 * delta, hD - hU)
        return normalize(normal)
    }
    
    /// Generates water surface - follows player
    private func generateWater() -> Entity {
        let waterEntity = Entity()
        waterEntity.name = "Water"
        
        // Large water plane
        let waterSize = chunkWorldSize * Float(viewDistance * 2 + 1)
        let waterMesh = MeshResource.generatePlane(width: waterSize, depth: waterSize)
        
        // Premium cartoon water - vibrant turquoise
        var waterMaterial = PhysicallyBasedMaterial()
        waterMaterial.baseColor = .init(tint: UIColor(red: 0.15, green: 0.55, blue: 0.75, alpha: 0.85))
        waterMaterial.roughness = .init(floatLiteral: 0.05)
        waterMaterial.metallic = .init(floatLiteral: 0.4)
        waterMaterial.blending = .transparent(opacity: .init(floatLiteral: 0.75))
        
        waterEntity.components.set(ModelComponent(mesh: waterMesh, materials: [waterMaterial]))
        waterEntity.position = SIMD3<Float>(0, waterLevel, 0)
        
        return waterEntity
    }
    
    /// 2D Perlin-like noise function
    func noise2D(x: Float, y: Float) -> Float {
        let xi = Int(floor(x)) & 255
        let yi = Int(floor(y)) & 255
        
        let xf = x - floor(x)
        let yf = y - floor(y)
        
        let u = fade(xf)
        let v = fade(yf)
        
        let aa = hash(xi, yi)
        let ab = hash(xi, yi + 1)
        let ba = hash(xi + 1, yi)
        let bb = hash(xi + 1, yi + 1)
        
        let x1 = lerp(grad(aa, xf, yf), grad(ba, xf - 1, yf), u)
        let x2 = lerp(grad(ab, xf, yf - 1), grad(bb, xf - 1, yf - 1), u)
        
        return lerp(x1, x2, v)
    }
    
    private func fade(_ t: Float) -> Float {
        return t * t * t * (t * (t * 6 - 15) + 10)
    }
    
    private func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float {
        return a + t * (b - a)
    }
    
    private func hash(_ x: Int, _ y: Int) -> Int {
        var h = Int(seed) + x * 374761393 + y * 668265263
        h = (h ^ (h >> 13)) &* 1274126177
        return h
    }
    
    private func grad(_ hash: Int, _ x: Float, _ y: Float) -> Float {
        let h = hash & 7
        let u = h < 4 ? x : y
        let v = h < 4 ? y : x
        return ((h & 1) != 0 ? -u : u) + ((h & 2) != 0 ? -2 * v : 2 * v)
    }
}
