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
    let viewDistance: Int = 40           // Chunks to load in each direction
    
    // Noise parameters for terrain generation
    private let seed: UInt64
    
    // Chunk management
    private var loadedChunks: [ChunkCoord: Entity] = [:]
    private var terrainRoot: Entity?
    private var waterEntity: Entity?
    
    // Background generation
    private let generationQueue = DispatchQueue(label: "terrain.generation", qos: .utility)
    /// Chunks whose mesh data has been computed in background, ready to materialize
    private var readyChunks: [(coord: ChunkCoord, data: ChunkMeshData)] = []
    /// Chunks currently being generated in background
    private var generatingChunks: Set<ChunkCoord> = []
    private let readyLock = NSLock()
    
    // Progressive loading
    private var chunkLoadQueue: [ChunkCoord] = []
    private var currentPlayerChunkX: Int = Int.min
    private var currentPlayerChunkZ: Int = Int.min
    
    /// Max chunks to materialize (add to scene) per frame — the lightweight part
    private let maxMaterializePerFrame: Int = 2
    /// Max background generation tasks to dispatch at once
    private let maxPendingGenerations: Int = 8
    /// Max chunks to remove per frame
    private let maxRemovalsPerFrame: Int = 10
    
    // Chunk coordinate type
    struct ChunkCoord: Hashable {
        let x: Int
        let z: Int
    }
    
    /// Pre-computed mesh data — generated on background thread
    private struct ChunkMeshData {
        let positions: [SIMD3<Float>]
        let normals: [SIMD3<Float>]
        let uvs: [SIMD2<Float>]
        let indices: [UInt32]
        let color: (r: CGFloat, g: CGFloat, b: CGFloat)
        let resolution: Int
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
        
        // Synchronously preload a small area around origin (runway must be visible)
        let preloadRadius = 4
        for dx in -preloadRadius...preloadRadius {
            for dz in -preloadRadius...preloadRadius {
                let coord = ChunkCoord(x: dx, z: dz)
                let data = computeChunkMeshData(chunkX: dx, chunkZ: dz, distSq: 0)
                let entity = materializeChunk(coord: coord, data: data)
                terrainEntity.addChild(entity)
                loadedChunks[coord] = entity
            }
        }
        
        // Queue the rest for progressive background loading
        currentPlayerChunkX = 0
        currentPlayerChunkZ = 0
        rebuildLoadQueue(centerX: 0, centerZ: 0)
        
        return terrainEntity
    }
    
    /// Update loaded chunks based on player position — call each frame.
    /// Heavy mesh computation runs on a background thread. Only lightweight
    /// materialization (MeshResource creation + scene insertion) happens here,
    /// limited to a small number per frame to guarantee smooth frame rate.
    func updateChunks(playerPosition: SIMD3<Float>) {
        guard let root = terrainRoot else { return }
        
        let chunkX = Int(floor(playerPosition.x / chunkWorldSize))
        let chunkZ = Int(floor(playerPosition.z / chunkWorldSize))
        
        // Rebuild load queue when player enters a new chunk
        if chunkX != currentPlayerChunkX || chunkZ != currentPlayerChunkZ {
            currentPlayerChunkX = chunkX
            currentPlayerChunkZ = chunkZ
            rebuildLoadQueue(centerX: chunkX, centerZ: chunkZ)
        }
        
        // --- Unload distant chunks (limited per frame) ---
        let unloadMargin = viewDistance + 2
        var removals = 0
        for coord in Array(loadedChunks.keys) {
            if removals >= maxRemovalsPerFrame { break }
            let dx = abs(coord.x - chunkX)
            let dz = abs(coord.z - chunkZ)
            if dx > unloadMargin || dz > unloadMargin {
                if let entity = loadedChunks[coord] {
                    entity.removeFromParent()
                    loadedChunks.removeValue(forKey: coord)
                    removals += 1
                }
            }
        }
        
        // --- Dispatch background generation for queued chunks ---
        var dispatched = 0
        while generatingChunks.count < maxPendingGenerations && !chunkLoadQueue.isEmpty && dispatched < maxPendingGenerations {
            let coord = chunkLoadQueue.removeFirst()
            if loadedChunks[coord] != nil || generatingChunks.contains(coord) { continue }
            let dx = abs(coord.x - chunkX)
            let dz = abs(coord.z - chunkZ)
            if dx > viewDistance || dz > viewDistance { continue }
            
            generatingChunks.insert(coord)
            let distSq = dx * dx + dz * dz
            generationQueue.async { [weak self] in
                guard let self = self else { return }
                let data = self.computeChunkMeshData(chunkX: coord.x, chunkZ: coord.z, distSq: distSq)
                self.readyLock.lock()
                self.readyChunks.append((coord: coord, data: data))
                self.readyLock.unlock()
            }
            dispatched += 1
        }
        
        // --- Materialize ready chunks (main thread, lightweight) ---
        readyLock.lock()
        let batch = readyChunks.prefix(maxMaterializePerFrame)
        readyChunks.removeFirst(min(maxMaterializePerFrame, readyChunks.count))
        readyLock.unlock()
        
        for item in batch {
            generatingChunks.remove(item.coord)
            if loadedChunks[item.coord] != nil { continue }
            let dx = abs(item.coord.x - chunkX)
            let dz = abs(item.coord.z - chunkZ)
            if dx > unloadMargin || dz > unloadMargin { continue }
            
            let entity = materializeChunk(coord: item.coord, data: item.data)
            root.addChild(entity)
            loadedChunks[item.coord] = entity
        }
        
        // Update water position to follow player
        waterEntity?.position = SIMD3<Float>(playerPosition.x, waterLevel, playerPosition.z)
    }
    
    /// Rebuild the chunk load queue, sorted by distance from center (closest first)
    private func rebuildLoadQueue(centerX: Int, centerZ: Int) {
        chunkLoadQueue.removeAll()
        
        for dx in -viewDistance...viewDistance {
            for dz in -viewDistance...viewDistance {
                let coord = ChunkCoord(x: centerX + dx, z: centerZ + dz)
                if loadedChunks[coord] == nil && !generatingChunks.contains(coord) {
                    chunkLoadQueue.append(coord)
                }
            }
        }
        
        chunkLoadQueue.sort { a, b in
            let da = (a.x - centerX) * (a.x - centerX) + (a.z - centerZ) * (a.z - centerZ)
            let db = (b.x - centerX) * (b.x - centerX) + (b.z - centerZ) * (b.z - centerZ)
            return da < db
        }
    }
    
    /// Compute all mesh data for a chunk — SAFE to call from any thread.
    /// Uses LOD: distant chunks get fewer vertices.
    private func computeChunkMeshData(chunkX: Int, chunkZ: Int, distSq: Int) -> ChunkMeshData {
        // LOD: reduce resolution for distant chunks
        let res: Int
        if distSq > 600 {       // > ~24 chunks away
            res = 2
        } else if distSq > 200 { // > ~14 chunks away
            res = 4
        } else if distSq > 80 {  // > ~9 chunks away
            res = 8
        } else {
            res = chunkResolution
        }
        
        let cellSize = chunkWorldSize / Float(res)
        let chunkOriginX = Float(chunkX) * chunkWorldSize
        let chunkOriginZ = Float(chunkZ) * chunkWorldSize
        
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []
        
        positions.reserveCapacity((res + 1) * (res + 1))
        normals.reserveCapacity((res + 1) * (res + 1))
        uvs.reserveCapacity((res + 1) * (res + 1))
        indices.reserveCapacity(res * res * 6)
        
        for z in 0...res {
            for x in 0...res {
                let worldX = chunkOriginX + Float(x) * cellSize
                let worldZ = chunkOriginZ + Float(z) * cellSize
                let height = getHeightAt(x: worldX, z: worldZ)
                positions.append(SIMD3<Float>(worldX, height, worldZ))
                uvs.append(SIMD2<Float>(Float(x) / Float(res), Float(z) / Float(res)))
            }
        }
        
        for z in 0...res {
            for x in 0...res {
                let worldX = chunkOriginX + Float(x) * cellSize
                let worldZ = chunkOriginZ + Float(z) * cellSize
                let normal = calculateNormal(x: worldX, z: worldZ, cellSize: cellSize)
                normals.append(normal)
            }
        }
        
        for z in 0..<res {
            for x in 0..<res {
                let tl = UInt32(z * (res + 1) + x)
                let tr = tl + 1
                let bl = UInt32((z + 1) * (res + 1) + x)
                let br = bl + 1
                indices.append(contentsOf: [tl, bl, tr, tr, bl, br])
            }
        }
        
        let color = getTerrainColorRGB(chunkX: chunkX, chunkZ: chunkZ)
        
        return ChunkMeshData(positions: positions, normals: normals, uvs: uvs,
                             indices: indices, color: color, resolution: res)
    }
    
    /// Create a RealityKit Entity from pre-computed mesh data — call on main thread only.
    private func materializeChunk(coord: ChunkCoord, data: ChunkMeshData) -> Entity {
        let entity = Entity()
        entity.name = "Chunk_\(coord.x)_\(coord.z)"
        
        var meshDescriptor = MeshDescriptor()
        meshDescriptor.positions = MeshBuffer(data.positions)
        meshDescriptor.normals = MeshBuffer(data.normals)
        meshDescriptor.textureCoordinates = MeshBuffer(data.uvs)
        meshDescriptor.primitives = .triangles(data.indices)
        
        do {
            let mesh = try MeshResource.generate(from: [meshDescriptor])
            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(tint: UIColor(red: data.color.r, green: data.color.g, blue: data.color.b, alpha: 1.0))
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
    
    /// Gets terrain color as RGB tuple — thread-safe (no UIColor creation)
    private func getTerrainColorRGB(chunkX: Int, chunkZ: Int) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        let centerX = Float(chunkX) * chunkWorldSize + chunkWorldSize / 2
        let centerZ = Float(chunkZ) * chunkWorldSize + chunkWorldSize / 2
        let height = getHeightAt(x: centerX, z: centerZ)
        
        // Roads - dark asphalt gray
        if isRoad(x: centerX, z: centerZ) && height > waterLevel + 1 && height < 80 {
            return (0.25, 0.25, 0.28)
        }
        
        // Snow caps
        if height > maxMountainHeight * 0.75 {
            return (0.95, 0.97, 1.0)
        }
        // Rocky mountains
        else if height > maxMountainHeight * 0.5 {
            return (0.55, 0.48, 0.52)
        }
        // Sandy beach near water
        else if height < waterLevel + 3 && height > waterLevel - 1 {
            return (0.93, 0.87, 0.65)
        }
        // Forest zones
        else if isForest(x: centerX, z: centerZ) {
            let variation = CGFloat(noise2D(x: centerX * 0.02, y: centerZ * 0.02))
            return (0.15, 0.45 + variation * 0.1, 0.18)
        }
        // Default grass
        else {
            let variation = CGFloat(noise2D(x: centerX * 0.01, y: centerZ * 0.01))
            return (0.30 + variation * 0.05, 0.55 + variation * 0.12, 0.22)
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
