//
//  SceneryGenerator.swift
//  3DSIM
//
//  Premium Cartoon Scenery - Forests, Houses, Aircraft, Helicopters, Balloons, Birds
//

import Foundation
import RealityKit
import simd
import AppKit

private typealias UIColor = NSColor

/// Generates premium cartoon-style procedural scenery
class SceneryGenerator {
    
    let terrainGenerator: TerrainGenerator
    private var random: SeededRandomGenerator
    
    // Scenery configuration - much richer world
    let numberOfHouses = 120
    let numberOfTreeClusters = 80
    let numberOfAircraft = 8
    let numberOfHelicopters = 4
    let numberOfBalloons = 6
    let numberOfBirdFlocks = 10
    let numberOfRoadVehicles = 30
    
    // Store animated entities
    var aiAircraft: [(entity: Entity, position: SIMD3<Float>, heading: Float, altitude: Float, speed: Float)] = []
    var helicopters: [(entity: Entity, position: SIMD3<Float>, heading: Float, altitude: Float, orbitCenter: SIMD3<Float>, orbitRadius: Float)] = []
    var balloons: [(entity: Entity, position: SIMD3<Float>, drift: SIMD3<Float>, baseAltitude: Float)] = []
    var birdFlocks: [(entity: Entity, position: SIMD3<Float>, heading: Float, altitude: Float, flapPhase: Float)] = []
    
    init(terrainGenerator: TerrainGenerator, seed: UInt64 = 54321) {
        self.terrainGenerator = terrainGenerator
        self.random = SeededRandomGenerator(seed: seed)
    }
    
    /// Generate all scenery elements
    func generateScenery() -> Entity {
        let sceneryEntity = Entity()
        sceneryEntity.name = "Scenery"
        
        // Generate forest clusters
        let forests = generateForests()
        sceneryEntity.addChild(forests)
        
        // Generate houses/villages
        let houses = generateHouses()
        sceneryEntity.addChild(houses)
        
        // Generate road details (lane markings, barriers)
        let roadDetails = generateRoadDetails()
        sceneryEntity.addChild(roadDetails)
        
        // Generate AI aircraft
        let aircraft = generateAIAircraft()
        sceneryEntity.addChild(aircraft)
        
        // Generate helicopters
        let helis = generateHelicopters()
        sceneryEntity.addChild(helis)
        
        // Generate hot air balloons
        let balloonEntities = generateBalloons()
        sceneryEntity.addChild(balloonEntities)
        
        // Generate bird flocks
        let birds = generateBirdFlocks()
        sceneryEntity.addChild(birds)
        
        return sceneryEntity
    }
    
    // MARK: - Forests
    
    /// Generate dense forest clusters in forest zones
    private func generateForests() -> Entity {
        let forestEntity = Entity()
        forestEntity.name = "Forests"
        
        for _ in 0..<numberOfTreeClusters {
            // Find a forest zone position
            var x: Float
            var z: Float
            var attempts = 0
            
            repeat {
                x = Float.random(in: -1200...1200, using: &random)
                z = Float.random(in: -1200...1200, using: &random)
                attempts += 1
            } while (!terrainGenerator.isForest(x: x, z: z) || abs(x) < 80 && abs(z) < 250) && attempts < 20
            
            guard attempts < 20 else { continue }
            
            let groundHeight = terrainGenerator.getHeightAt(x: x, z: z)
            guard groundHeight > terrainGenerator.waterLevel + 2 && groundHeight < 120 else { continue }
            
            // Create a cluster of trees
            let clusterSize = Int.random(in: 8...25, using: &random)
            let clusterRadius: Float = Float.random(in: 15...40, using: &random)
            
            for j in 0..<clusterSize {
                let offsetX = Float.random(in: -clusterRadius...clusterRadius, using: &random)
                let offsetZ = Float.random(in: -clusterRadius...clusterRadius, using: &random)
                let treeX = x + offsetX
                let treeZ = z + offsetZ
                let treeHeight = terrainGenerator.getHeightAt(x: treeX, z: treeZ)
                
                guard treeHeight > terrainGenerator.waterLevel + 1 else { continue }
                
                let tree = createCartoonTree(index: j)
                tree.position = SIMD3<Float>(treeX, treeHeight, treeZ)
                forestEntity.addChild(tree)
            }
        }
        
        return forestEntity
    }
    
    /// Create a premium cartoon-style tree with multiple canopy spheres
    private func createCartoonTree(index: Int) -> Entity {
        let treeEntity = Entity()
        treeEntity.name = "Tree_\(index)"
        
        let trunkHeight = Float.random(in: 4...10, using: &random)
        let trunkRadius: Float = Float.random(in: 0.3...0.6, using: &random)
        let treeType = Int.random(in: 0...2, using: &random)
        
        // Cartoon trunk - warm brown
        let trunkMesh = MeshResource.generateBox(size: SIMD3<Float>(trunkRadius * 2, trunkHeight, trunkRadius * 2), cornerRadius: trunkRadius * 0.5)
        var trunkMaterial = SimpleMaterial()
        trunkMaterial.color = .init(tint: UIColor(red: 0.45, green: 0.28, blue: 0.14, alpha: 1.0))
        
        let trunkEntity = Entity()
        trunkEntity.components.set(ModelComponent(mesh: trunkMesh, materials: [trunkMaterial]))
        trunkEntity.position.y = trunkHeight / 2
        treeEntity.addChild(trunkEntity)
        
        switch treeType {
        case 0:
            // Round cartoon tree - multiple overlapping spheres
            let canopyColors: [UIColor] = [
                UIColor(red: 0.18, green: 0.55, blue: 0.22, alpha: 1.0),
                UIColor(red: 0.22, green: 0.62, blue: 0.25, alpha: 1.0),
                UIColor(red: 0.15, green: 0.48, blue: 0.20, alpha: 1.0),
            ]
            
            let mainRadius = Float.random(in: 2.5...4.5, using: &random)
            for k in 0..<3 {
                let r = mainRadius * Float.random(in: 0.6...1.0, using: &random)
                let canopyMesh = MeshResource.generateSphere(radius: r)
                var mat = SimpleMaterial()
                mat.color = .init(tint: canopyColors[k % canopyColors.count])
                
                let canopy = Entity()
                canopy.components.set(ModelComponent(mesh: canopyMesh, materials: [mat]))
                let offsetX = Float.random(in: -1.0...1.0, using: &random)
                let offsetZ = Float.random(in: -1.0...1.0, using: &random)
                canopy.position = SIMD3<Float>(offsetX, trunkHeight + r * 0.4 + Float(k) * 0.5, offsetZ)
                treeEntity.addChild(canopy)
            }
            
        case 1:
            // Pine/conifer tree - cone shape using stacked discs
            let coneHeight = Float.random(in: 5...9, using: &random)
            let layers = 4
            for k in 0..<layers {
                let progress = Float(k) / Float(layers)
                let layerRadius = (1.0 - progress * 0.8) * 3.0
                let layerHeight: Float = 1.5
                let layerMesh = MeshResource.generateBox(
                    size: SIMD3<Float>(layerRadius * 2, layerHeight, layerRadius * 2),
                    cornerRadius: layerRadius * 0.3
                )
                var mat = SimpleMaterial()
                let greenShade = 0.3 + CGFloat(progress) * 0.2
                mat.color = .init(tint: UIColor(red: 0.08, green: greenShade, blue: 0.12, alpha: 1.0))
                
                let layer = Entity()
                layer.components.set(ModelComponent(mesh: layerMesh, materials: [mat]))
                layer.position.y = trunkHeight + Float(k) * (coneHeight / Float(layers))
                treeEntity.addChild(layer)
            }
            
        default:
            // Autumn/varied tree - orange/yellow canopy
            let canopyRadius = Float.random(in: 2.5...4.0, using: &random)
            let canopyMesh = MeshResource.generateSphere(radius: canopyRadius)
            let autumnColors: [UIColor] = [
                UIColor(red: 0.85, green: 0.55, blue: 0.15, alpha: 1.0),
                UIColor(red: 0.75, green: 0.25, blue: 0.15, alpha: 1.0),
                UIColor(red: 0.90, green: 0.70, blue: 0.10, alpha: 1.0),
            ]
            var mat = SimpleMaterial()
            mat.color = .init(tint: autumnColors[index % autumnColors.count])
            
            let canopy = Entity()
            canopy.components.set(ModelComponent(mesh: canopyMesh, materials: [mat]))
            canopy.position.y = trunkHeight + canopyRadius * 0.6
            treeEntity.addChild(canopy)
        }
        
        return treeEntity
    }
    
    // MARK: - Houses / Villages
    
    /// Generate cartoon-style houses arranged in small villages
    private func generateHouses() -> Entity {
        let housesEntity = Entity()
        housesEntity.name = "Houses"
        
        // Create village clusters along roads and in flat areas
        let villagePositions: [SIMD2<Float>] = [
            SIMD2<Float>(350, 300), SIMD2<Float>(-300, 200),
            SIMD2<Float>(500, -200), SIMD2<Float>(-400, -400),
            SIMD2<Float>(200, -500), SIMD2<Float>(-600, 100),
            SIMD2<Float>(700, 100), SIMD2<Float>(-100, 500),
        ]
        
        var houseIndex = 0
        for villageCenter in villagePositions {
            let housesInVillage = Int.random(in: 8...18, using: &random)
            
            for _ in 0..<housesInVillage {
                let x = villageCenter.x + Float.random(in: -60...60, using: &random)
                let z = villageCenter.y + Float.random(in: -60...60, using: &random)
                
                let groundHeight = terrainGenerator.getHeightAt(x: x, z: z)
                guard groundHeight > terrainGenerator.waterLevel + 2 && groundHeight < 80 else { continue }
                guard !terrainGenerator.isLake(x: x, z: z) else { continue }
                
                let house = createCartoonHouse(index: houseIndex)
                house.position = SIMD3<Float>(x, groundHeight, z)
                
                let rotation = Float.random(in: 0...Float.pi * 2, using: &random)
                house.orientation = simd_quatf(angle: rotation, axis: SIMD3<Float>(0, 1, 0))
                
                housesEntity.addChild(house)
                houseIndex += 1
            }
        }
        
        return housesEntity
    }
    
    /// Create a premium cartoon house with bright colors
    private func createCartoonHouse(index: Int) -> Entity {
        let houseEntity = Entity()
        houseEntity.name = "House_\(index)"
        
        let width = Float.random(in: 7...14, using: &random)
        let depth = Float.random(in: 7...14, using: &random)
        let height = Float.random(in: 3.5...7, using: &random)
        let roofHeight = Float.random(in: 2...4, using: &random)
        
        // Cartoon house body - vibrant pastel colors
        let bodyMesh = MeshResource.generateBox(size: SIMD3<Float>(width, height, depth), cornerRadius: 0.3)
        let bodyColors: [UIColor] = [
            UIColor(red: 0.95, green: 0.92, blue: 0.82, alpha: 1.0),  // Warm cream
            UIColor(red: 0.85, green: 0.90, blue: 0.95, alpha: 1.0),  // Soft blue
            UIColor(red: 0.95, green: 0.88, blue: 0.85, alpha: 1.0),  // Peach
            UIColor(red: 0.90, green: 0.95, blue: 0.88, alpha: 1.0),  // Mint green
            UIColor(red: 0.95, green: 0.93, blue: 0.78, alpha: 1.0),  // Butter yellow
            UIColor(red: 0.92, green: 0.85, blue: 0.92, alpha: 1.0),  // Lavender
        ]
        
        var bodyMaterial = SimpleMaterial()
        bodyMaterial.color = .init(tint: bodyColors[index % bodyColors.count])
        
        let bodyEntity = Entity()
        bodyEntity.components.set(ModelComponent(mesh: bodyMesh, materials: [bodyMaterial]))
        bodyEntity.position.y = height / 2
        houseEntity.addChild(bodyEntity)
        
        // Cartoon roof - bright saturated colors
        let roofMesh = MeshResource.generateBox(size: SIMD3<Float>(width * 1.15, roofHeight, depth * 1.15), cornerRadius: 0.5)
        let roofColors: [UIColor] = [
            UIColor(red: 0.85, green: 0.25, blue: 0.20, alpha: 1.0),  // Bright red
            UIColor(red: 0.22, green: 0.45, blue: 0.65, alpha: 1.0),  // Ocean blue
            UIColor(red: 0.55, green: 0.30, blue: 0.18, alpha: 1.0),  // Warm brown
            UIColor(red: 0.60, green: 0.65, blue: 0.30, alpha: 1.0),  // Olive
            UIColor(red: 0.70, green: 0.22, blue: 0.35, alpha: 1.0),  // Berry
        ]
        
        var roofMaterial = SimpleMaterial()
        roofMaterial.color = .init(tint: roofColors[index % roofColors.count])
        
        let roofEntity = Entity()
        roofEntity.components.set(ModelComponent(mesh: roofMesh, materials: [roofMaterial]))
        roofEntity.position.y = height + roofHeight / 2
        roofEntity.scale = SIMD3<Float>(1.0, 1.0, 0.7) // Pitched roof
        houseEntity.addChild(roofEntity)
        
        // Chimney
        if Int.random(in: 0...2, using: &random) == 0 {
            let chimneyMesh = MeshResource.generateBox(size: SIMD3<Float>(1.0, 3.0, 1.0), cornerRadius: 0.1)
            var chimneyMat = SimpleMaterial()
            chimneyMat.color = .init(tint: UIColor(red: 0.6, green: 0.35, blue: 0.25, alpha: 1.0))
            let chimney = Entity()
            chimney.components.set(ModelComponent(mesh: chimneyMesh, materials: [chimneyMat]))
            chimney.position = SIMD3<Float>(width * 0.3, height + roofHeight + 0.5, 0)
            houseEntity.addChild(chimney)
        }
        
        // Door
        let doorMesh = MeshResource.generateBox(size: SIMD3<Float>(1.3, 2.4, 0.15), cornerRadius: 0.15)
        var doorMaterial = SimpleMaterial()
        doorMaterial.color = .init(tint: UIColor(red: 0.45, green: 0.28, blue: 0.15, alpha: 1.0))
        
        let doorEntity = Entity()
        doorEntity.components.set(ModelComponent(mesh: doorMesh, materials: [doorMaterial]))
        doorEntity.position = SIMD3<Float>(0, 1.2, depth / 2 + 0.07)
        houseEntity.addChild(doorEntity)
        
        // Windows - cartoon bright blue
        let windowMesh = MeshResource.generateBox(size: SIMD3<Float>(1.1, 1.3, 0.12), cornerRadius: 0.15)
        var windowMaterial = SimpleMaterial()
        windowMaterial.color = .init(tint: UIColor(red: 0.55, green: 0.78, blue: 0.92, alpha: 1.0))
        
        for wx in [-1, 1] as [Float] {
            let windowEntity = Entity()
            windowEntity.components.set(ModelComponent(mesh: windowMesh, materials: [windowMaterial]))
            windowEntity.position = SIMD3<Float>(wx * width * 0.3, height * 0.6, depth / 2 + 0.06)
            houseEntity.addChild(windowEntity)
        }
        
        // Garden fence for some houses
        if Int.random(in: 0...3, using: &random) == 0 {
            let fenceMesh = MeshResource.generateBox(size: SIMD3<Float>(width * 1.8, 1.0, 0.1))
            var fenceMat = SimpleMaterial()
            fenceMat.color = .init(tint: UIColor(red: 0.9, green: 0.9, blue: 0.85, alpha: 1.0))
            
            for side in [-1.0, 1.0] as [Float] {
                let fence = Entity()
                fence.components.set(ModelComponent(mesh: fenceMesh, materials: [fenceMat]))
                fence.position = SIMD3<Float>(0, 0.5, side * (depth / 2 + 3))
                houseEntity.addChild(fence)
            }
        }
        
        return houseEntity
    }
    
    // MARK: - Road Details
    
    /// Generate road lane markings and barriers
    private func generateRoadDetails() -> Entity {
        let roadEntity = Entity()
        roadEntity.name = "RoadDetails"
        
        var dashMaterial = SimpleMaterial()
        dashMaterial.color = .init(tint: UIColor(red: 1.0, green: 1.0, blue: 0.8, alpha: 1.0))
        
        // Lane dashes on the main east-west highway
        let dashMesh = MeshResource.generatePlane(width: 0.5, depth: 3.0)
        var x: Float = -800
        while x < 800 {
            let z: Float = 300
            let h = terrainGenerator.getHeightAt(x: x, z: z)
            if h > terrainGenerator.waterLevel + 1 && h < 80 {
                let dash = Entity()
                dash.components.set(ModelComponent(mesh: dashMesh, materials: [dashMaterial]))
                dash.position = SIMD3<Float>(x, h + 0.15, z)
                roadEntity.addChild(dash)
            }
            x += 10
        }
        
        // Lane dashes on the north-south road
        let dashMeshV = MeshResource.generatePlane(width: 3.0, depth: 0.5)
        var z: Float = -800
        while z < 800 {
            let roadX: Float = 400
            let h = terrainGenerator.getHeightAt(x: roadX, z: z)
            if h > terrainGenerator.waterLevel + 1 && h < 80 {
                let dash = Entity()
                dash.components.set(ModelComponent(mesh: dashMeshV, materials: [dashMaterial]))
                dash.position = SIMD3<Float>(roadX, h + 0.15, z)
                roadEntity.addChild(dash)
            }
            z += 10
        }
        
        return roadEntity
    }
    
    // MARK: - AI Aircraft
    
    /// Generate AI aircraft flying around at various altitudes
    private func generateAIAircraft() -> Entity {
        let aircraftEntity = Entity()
        aircraftEntity.name = "AIAircraft"
        
        aiAircraft.removeAll()
        
        for i in 0..<numberOfAircraft {
            let aircraft = createAircraftModel(index: i)
            
            let angle = Float(i) * (2 * .pi / Float(numberOfAircraft))
            let radius = Float.random(in: 400...900, using: &random)
            let altitude = Float.random(in: 80...350, using: &random)
            let speed = Float.random(in: 40...70, using: &random)
            
            let x = cos(angle) * radius
            let z = sin(angle) * radius
            
            aircraft.position = SIMD3<Float>(x, altitude, z)
            let heading = angle + .pi / 2
            aircraft.orientation = simd_quatf(angle: heading, axis: SIMD3<Float>(0, 1, 0))
            
            aircraftEntity.addChild(aircraft)
            aiAircraft.append((entity: aircraft, position: aircraft.position, heading: heading, altitude: altitude, speed: speed))
        }
        
        return aircraftEntity
    }
    
    /// Create a cartoon aircraft model with vibrant livery
    func createAircraftModel(index: Int = 0) -> Entity {
        let aircraftEntity = Entity()
        aircraftEntity.name = "Aircraft_\(index)"
        
        // Fuselage - cartoon style with rounded corners
        let fuselageMesh = MeshResource.generateBox(size: SIMD3<Float>(1.2, 1.0, 6.0), cornerRadius: 0.4)
        let liveryColors: [UIColor] = [
            .white,
            UIColor(red: 0.95, green: 0.95, blue: 0.98, alpha: 1.0),
            UIColor(red: 0.20, green: 0.35, blue: 0.65, alpha: 1.0),
            UIColor(red: 0.85, green: 0.25, blue: 0.20, alpha: 1.0),
            UIColor(red: 0.15, green: 0.55, blue: 0.35, alpha: 1.0),
            UIColor(red: 0.90, green: 0.70, blue: 0.10, alpha: 1.0),
        ]
        var fuselageMaterial = SimpleMaterial()
        fuselageMaterial.color = .init(tint: liveryColors[index % liveryColors.count])
        
        let fuselageEntity = Entity()
        fuselageEntity.components.set(ModelComponent(mesh: fuselageMesh, materials: [fuselageMaterial]))
        aircraftEntity.addChild(fuselageEntity)
        
        // Wings
        let wingMesh = MeshResource.generateBox(size: SIMD3<Float>(10.0, 0.15, 1.5), cornerRadius: 0.05)
        var wingMaterial = SimpleMaterial()
        wingMaterial.color = .init(tint: liveryColors[index % liveryColors.count])
        
        let wingEntity = Entity()
        wingEntity.components.set(ModelComponent(mesh: wingMesh, materials: [wingMaterial]))
        wingEntity.position = SIMD3<Float>(0, 0, 0.5)
        aircraftEntity.addChild(wingEntity)
        
        // Tail surfaces
        let hStabMesh = MeshResource.generateBox(size: SIMD3<Float>(3.0, 0.1, 0.6))
        let hStabEntity = Entity()
        hStabEntity.components.set(ModelComponent(mesh: hStabMesh, materials: [wingMaterial]))
        hStabEntity.position = SIMD3<Float>(0, 0.3, -2.5)
        aircraftEntity.addChild(hStabEntity)
        
        let vStabMesh = MeshResource.generateBox(size: SIMD3<Float>(0.1, 1.5, 1.0))
        let vStabEntity = Entity()
        vStabEntity.components.set(ModelComponent(mesh: vStabMesh, materials: [wingMaterial]))
        vStabEntity.position = SIMD3<Float>(0, 0.8, -2.3)
        aircraftEntity.addChild(vStabEntity)
        
        // Stripe on tail
        let stripeMesh = MeshResource.generateBox(size: SIMD3<Float>(0.12, 1.4, 0.3))
        var stripeMat = SimpleMaterial()
        stripeMat.color = .init(tint: liveryColors[(index + 2) % liveryColors.count])
        let stripe = Entity()
        stripe.components.set(ModelComponent(mesh: stripeMesh, materials: [stripeMat]))
        stripe.position = SIMD3<Float>(0, 0.8, -2.3)
        aircraftEntity.addChild(stripe)
        
        // Engine cowling
        let engineMesh = MeshResource.generateBox(size: SIMD3<Float>(0.8, 0.8, 1.0), cornerRadius: 0.3)
        var engineMaterial = SimpleMaterial()
        engineMaterial.color = .init(tint: UIColor(red: 0.25, green: 0.25, blue: 0.30, alpha: 1.0))
        
        let engineEntity = Entity()
        engineEntity.components.set(ModelComponent(mesh: engineMesh, materials: [engineMaterial]))
        engineEntity.position = SIMD3<Float>(0, 0, 3.2)
        aircraftEntity.addChild(engineEntity)
        
        // Propeller
        let propMesh = MeshResource.generateBox(size: SIMD3<Float>(0.1, 2.0, 0.2))
        var propMaterial = SimpleMaterial()
        propMaterial.color = .init(tint: UIColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1.0))
        
        let propEntity = Entity()
        propEntity.components.set(ModelComponent(mesh: propMesh, materials: [propMaterial]))
        propEntity.position = SIMD3<Float>(0, 0, 3.7)
        propEntity.name = "Propeller"
        aircraftEntity.addChild(propEntity)
        
        // Landing gear
        let gearMesh = MeshResource.generateBox(size: SIMD3<Float>(0.15, 1.0, 0.15))
        var gearMaterial = SimpleMaterial()
        gearMaterial.color = .init(tint: UIColor(red: 0.3, green: 0.3, blue: 0.3, alpha: 1.0))
        
        for gx in [-1.5, 1.5] as [Float] {
            let gearEntity = Entity()
            gearEntity.components.set(ModelComponent(mesh: gearMesh, materials: [gearMaterial]))
            gearEntity.position = SIMD3<Float>(gx, -0.8, 0.5)
            aircraftEntity.addChild(gearEntity)
            
            let wheelMesh = MeshResource.generateBox(size: SIMD3<Float>(0.3, 0.5, 0.5), cornerRadius: 0.2)
            var wheelMaterial = SimpleMaterial()
            wheelMaterial.color = .init(tint: .black)
            let wheelEntity = Entity()
            wheelEntity.components.set(ModelComponent(mesh: wheelMesh, materials: [wheelMaterial]))
            wheelEntity.position = SIMD3<Float>(gx, -1.2, 0.5)
            aircraftEntity.addChild(wheelEntity)
        }
        
        // Nose wheel
        let noseGearEntity = Entity()
        noseGearEntity.components.set(ModelComponent(mesh: gearMesh, materials: [gearMaterial]))
        noseGearEntity.position = SIMD3<Float>(0, -0.7, 2.0)
        aircraftEntity.addChild(noseGearEntity)
        
        let noseWheelMesh = MeshResource.generateBox(size: SIMD3<Float>(0.2, 0.35, 0.35), cornerRadius: 0.15)
        var noseWheelMat = SimpleMaterial()
        noseWheelMat.color = .init(tint: .black)
        let noseWheelEntity = Entity()
        noseWheelEntity.components.set(ModelComponent(mesh: noseWheelMesh, materials: [noseWheelMat]))
        noseWheelEntity.position = SIMD3<Float>(0, -1.0, 2.0)
        aircraftEntity.addChild(noseWheelEntity)
        
        return aircraftEntity
    }
    
    // MARK: - Helicopters
    
    /// Generate cartoon helicopters orbiting around
    private func generateHelicopters() -> Entity {
        let heliRoot = Entity()
        heliRoot.name = "Helicopters"
        
        helicopters.removeAll()
        
        for i in 0..<numberOfHelicopters {
            let heli = createHelicopterModel(index: i)
            
            let orbitCenter = SIMD3<Float>(
                Float.random(in: -500...500, using: &random),
                0,
                Float.random(in: -500...500, using: &random)
            )
            let orbitRadius = Float.random(in: 100...250, using: &random)
            let altitude = Float.random(in: 60...200, using: &random)
            let angle = Float.random(in: 0...(2 * .pi), using: &random)
            
            let x = orbitCenter.x + cos(angle) * orbitRadius
            let z = orbitCenter.z + sin(angle) * orbitRadius
            
            heli.position = SIMD3<Float>(x, altitude, z)
            heliRoot.addChild(heli)
            
            helicopters.append((entity: heli, position: heli.position, heading: angle, altitude: altitude, orbitCenter: orbitCenter, orbitRadius: orbitRadius))
        }
        
        return heliRoot
    }
    
    /// Create a cartoon helicopter model
    private func createHelicopterModel(index: Int) -> Entity {
        let heliEntity = Entity()
        heliEntity.name = "Helicopter_\(index)"
        
        let heliColors: [UIColor] = [
            UIColor(red: 0.85, green: 0.20, blue: 0.15, alpha: 1.0),
            UIColor(red: 0.15, green: 0.45, blue: 0.70, alpha: 1.0),
            UIColor(red: 0.90, green: 0.65, blue: 0.10, alpha: 1.0),
            UIColor(red: 0.20, green: 0.60, blue: 0.25, alpha: 1.0),
        ]
        
        // Body - rounded box
        let bodyMesh = MeshResource.generateBox(size: SIMD3<Float>(2.0, 1.8, 4.0), cornerRadius: 0.5)
        var bodyMat = SimpleMaterial()
        bodyMat.color = .init(tint: heliColors[index % heliColors.count])
        
        let body = Entity()
        body.components.set(ModelComponent(mesh: bodyMesh, materials: [bodyMat]))
        heliEntity.addChild(body)
        
        // Cockpit glass
        let glassMesh = MeshResource.generateBox(size: SIMD3<Float>(1.8, 1.2, 1.5), cornerRadius: 0.4)
        var glassMat = SimpleMaterial()
        glassMat.color = .init(tint: UIColor(red: 0.5, green: 0.75, blue: 0.90, alpha: 0.7))
        
        let glass = Entity()
        glass.components.set(ModelComponent(mesh: glassMesh, materials: [glassMat]))
        glass.position = SIMD3<Float>(0, 0.3, 1.5)
        heliEntity.addChild(glass)
        
        // Tail boom
        let tailMesh = MeshResource.generateBox(size: SIMD3<Float>(0.5, 0.5, 4.0), cornerRadius: 0.15)
        let tail = Entity()
        tail.components.set(ModelComponent(mesh: tailMesh, materials: [bodyMat]))
        tail.position = SIMD3<Float>(0, 0.3, -3.5)
        heliEntity.addChild(tail)
        
        // Tail rotor (vertical disc)
        let tailRotorMesh = MeshResource.generateBox(size: SIMD3<Float>(0.1, 1.5, 0.15))
        var tailRotorMat = SimpleMaterial()
        tailRotorMat.color = .init(tint: UIColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1.0))
        
        let tailRotor = Entity()
        tailRotor.name = "TailRotor"
        tailRotor.components.set(ModelComponent(mesh: tailRotorMesh, materials: [tailRotorMat]))
        tailRotor.position = SIMD3<Float>(0.3, 0.3, -5.3)
        heliEntity.addChild(tailRotor)
        
        // Main rotor mast
        let mastMesh = MeshResource.generateBox(size: SIMD3<Float>(0.3, 1.0, 0.3))
        var mastMat = SimpleMaterial()
        mastMat.color = .init(tint: UIColor(red: 0.3, green: 0.3, blue: 0.3, alpha: 1.0))
        
        let mast = Entity()
        mast.components.set(ModelComponent(mesh: mastMesh, materials: [mastMat]))
        mast.position = SIMD3<Float>(0, 1.4, 0)
        heliEntity.addChild(mast)
        
        // Main rotor blades
        let bladeMesh = MeshResource.generateBox(size: SIMD3<Float>(8.0, 0.08, 0.4))
        var bladeMat = SimpleMaterial()
        bladeMat.color = .init(tint: UIColor(red: 0.15, green: 0.15, blue: 0.18, alpha: 1.0))
        
        let rotorHub = Entity()
        rotorHub.name = "MainRotor"
        rotorHub.position = SIMD3<Float>(0, 1.95, 0)
        
        for bladeAngle in [0, Float.pi / 2] as [Float] {
            let blade = Entity()
            blade.components.set(ModelComponent(mesh: bladeMesh, materials: [bladeMat]))
            blade.orientation = simd_quatf(angle: bladeAngle, axis: SIMD3<Float>(0, 1, 0))
            rotorHub.addChild(blade)
        }
        
        heliEntity.addChild(rotorHub)
        
        // Skids
        let skidMesh = MeshResource.generateBox(size: SIMD3<Float>(0.12, 0.12, 3.0), cornerRadius: 0.05)
        var skidMat = SimpleMaterial()
        skidMat.color = .init(tint: UIColor(red: 0.3, green: 0.3, blue: 0.3, alpha: 1.0))
        
        for side in [-1.0, 1.0] as [Float] {
            let skid = Entity()
            skid.components.set(ModelComponent(mesh: skidMesh, materials: [skidMat]))
            skid.position = SIMD3<Float>(side * 1.0, -1.2, 0)
            heliEntity.addChild(skid)
            
            // Skid struts
            let strutMesh = MeshResource.generateBox(size: SIMD3<Float>(0.08, 0.6, 0.08))
            for sz in [-0.8, 0.8] as [Float] {
                let strut = Entity()
                strut.components.set(ModelComponent(mesh: strutMesh, materials: [skidMat]))
                strut.position = SIMD3<Float>(side * 1.0, -0.9, sz)
                heliEntity.addChild(strut)
            }
        }
        
        return heliEntity
    }
    
    // MARK: - Hot Air Balloons
    
    /// Generate colorful hot air balloons floating in the sky
    private func generateBalloons() -> Entity {
        let balloonRoot = Entity()
        balloonRoot.name = "Balloons"
        
        balloons.removeAll()
        
        for i in 0..<numberOfBalloons {
            let balloon = createBalloonModel(index: i)
            
            let x = Float.random(in: -800...800, using: &random)
            let z = Float.random(in: -800...800, using: &random)
            let altitude = Float.random(in: 80...250, using: &random)
            
            balloon.position = SIMD3<Float>(x, altitude, z)
            balloonRoot.addChild(balloon)
            
            let drift = SIMD3<Float>(
                Float.random(in: -2...2, using: &random),
                Float.random(in: -0.3...0.3, using: &random),
                Float.random(in: -2...2, using: &random)
            )
            
            balloons.append((entity: balloon, position: balloon.position, drift: drift, baseAltitude: altitude))
        }
        
        return balloonRoot
    }
    
    /// Create a cartoon hot air balloon
    private func createBalloonModel(index: Int) -> Entity {
        let balloonEntity = Entity()
        balloonEntity.name = "Balloon_\(index)"
        
        let balloonColors: [UIColor] = [
            UIColor(red: 0.90, green: 0.25, blue: 0.20, alpha: 1.0),
            UIColor(red: 0.20, green: 0.55, blue: 0.85, alpha: 1.0),
            UIColor(red: 0.95, green: 0.70, blue: 0.10, alpha: 1.0),
            UIColor(red: 0.70, green: 0.20, blue: 0.60, alpha: 1.0),
            UIColor(red: 0.15, green: 0.70, blue: 0.40, alpha: 1.0),
            UIColor(red: 0.95, green: 0.50, blue: 0.15, alpha: 1.0),
        ]
        
        // Envelope (balloon itself) - large sphere
        let envelopeRadius: Float = 8.0
        let envelopeMesh = MeshResource.generateSphere(radius: envelopeRadius)
        var envelopeMat = SimpleMaterial()
        envelopeMat.color = .init(tint: balloonColors[index % balloonColors.count])
        
        let envelope = Entity()
        envelope.components.set(ModelComponent(mesh: envelopeMesh, materials: [envelopeMat]))
        envelope.position.y = envelopeRadius + 5
        envelope.scale = SIMD3<Float>(1.0, 1.3, 1.0) // Taller than wide
        balloonEntity.addChild(envelope)
        
        // Decorative stripe band
        let stripeMesh = MeshResource.generateBox(size: SIMD3<Float>(envelopeRadius * 2.1, 2.0, envelopeRadius * 2.1), cornerRadius: envelopeRadius)
        var stripeMat = SimpleMaterial()
        stripeMat.color = .init(tint: balloonColors[(index + 3) % balloonColors.count])
        
        let stripeEntity = Entity()
        stripeEntity.components.set(ModelComponent(mesh: stripeMesh, materials: [stripeMat]))
        stripeEntity.position.y = envelopeRadius + 5
        balloonEntity.addChild(stripeEntity)
        
        // Basket
        let basketMesh = MeshResource.generateBox(size: SIMD3<Float>(2.5, 1.5, 2.5), cornerRadius: 0.2)
        var basketMat = SimpleMaterial()
        basketMat.color = .init(tint: UIColor(red: 0.55, green: 0.38, blue: 0.20, alpha: 1.0))
        
        let basket = Entity()
        basket.components.set(ModelComponent(mesh: basketMesh, materials: [basketMat]))
        basket.position.y = 0.75
        balloonEntity.addChild(basket)
        
        // Rope lines (simplified as thin boxes connecting basket to envelope)
        let ropeMesh = MeshResource.generateBox(size: SIMD3<Float>(0.05, 10.0, 0.05))
        var ropeMat = SimpleMaterial()
        ropeMat.color = .init(tint: UIColor(red: 0.4, green: 0.35, blue: 0.25, alpha: 1.0))
        
        for rx in [-1.0, 1.0] as [Float] {
            for rz in [-1.0, 1.0] as [Float] {
                let rope = Entity()
                rope.components.set(ModelComponent(mesh: ropeMesh, materials: [ropeMat]))
                rope.position = SIMD3<Float>(rx * 0.8, 6.5, rz * 0.8)
                balloonEntity.addChild(rope)
            }
        }
        
        return balloonEntity
    }
    
    // MARK: - Bird Flocks
    
    /// Generate flocks of birds
    private func generateBirdFlocks() -> Entity {
        let birdRoot = Entity()
        birdRoot.name = "Birds"
        
        birdFlocks.removeAll()
        
        for i in 0..<numberOfBirdFlocks {
            let flock = createBirdFlock(index: i)
            
            let x = Float.random(in: -600...600, using: &random)
            let z = Float.random(in: -600...600, using: &random)
            let altitude = Float.random(in: 30...150, using: &random)
            let heading = Float.random(in: 0...(2 * .pi), using: &random)
            
            flock.position = SIMD3<Float>(x, altitude, z)
            birdRoot.addChild(flock)
            
            birdFlocks.append((entity: flock, position: flock.position, heading: heading, altitude: altitude, flapPhase: Float.random(in: 0...(2 * .pi), using: &random)))
        }
        
        return birdRoot
    }
    
    /// Create a small flock of cartoon birds
    private func createBirdFlock(index: Int) -> Entity {
        let flockEntity = Entity()
        flockEntity.name = "BirdFlock_\(index)"
        
        let birdsInFlock = Int.random(in: 3...8, using: &random)
        
        for j in 0..<birdsInFlock {
            let bird = createBird()
            bird.position = SIMD3<Float>(
                Float.random(in: -5...5, using: &random),
                Float.random(in: -2...2, using: &random),
                Float.random(in: -5...5, using: &random)
            )
            bird.name = "Bird_\(j)"
            flockEntity.addChild(bird)
        }
        
        return flockEntity
    }
    
    /// Create a single cartoon bird (simple V shape)
    private func createBird() -> Entity {
        let birdEntity = Entity()
        
        // Body
        let bodyMesh = MeshResource.generateBox(size: SIMD3<Float>(0.2, 0.2, 0.5), cornerRadius: 0.08)
        var bodyMat = SimpleMaterial()
        bodyMat.color = .init(tint: UIColor(red: 0.15, green: 0.15, blue: 0.18, alpha: 1.0))
        
        let body = Entity()
        body.components.set(ModelComponent(mesh: bodyMesh, materials: [bodyMat]))
        birdEntity.addChild(body)
        
        // Wings
        let wingMesh = MeshResource.generateBox(size: SIMD3<Float>(1.2, 0.03, 0.25))
        var wingMat = SimpleMaterial()
        wingMat.color = .init(tint: UIColor(red: 0.2, green: 0.2, blue: 0.25, alpha: 1.0))
        
        let wings = Entity()
        wings.name = "Wings"
        wings.components.set(ModelComponent(mesh: wingMesh, materials: [wingMat]))
        wings.position.y = 0.1
        birdEntity.addChild(wings)
        
        return birdEntity
    }
    
    // MARK: - Animation Updates
    
    /// Update all animated scenery (call each frame)
    func updateAIAircraft(deltaTime: Float) {
        updateAircraft(deltaTime: deltaTime)
        updateHelicopters(deltaTime: deltaTime)
        updateBalloons(deltaTime: deltaTime)
        updateBirds(deltaTime: deltaTime)
    }
    
    /// Update AI aircraft positions
    private func updateAircraft(deltaTime: Float) {
        for i in 0..<aiAircraft.count {
            var aircraft = aiAircraft[i]
            
            // Circular flight with slight variation
            aircraft.heading += deltaTime * 0.08
            
            let vx = sin(aircraft.heading) * aircraft.speed * deltaTime
            let vz = cos(aircraft.heading) * aircraft.speed * deltaTime
            
            aircraft.position.x += vx
            aircraft.position.z += vz
            aircraft.position.y = aircraft.altitude + sin(aircraft.heading * 2) * 10
            
            aircraft.entity.position = aircraft.position
            
            // Bank into turns for realism
            let bankAngle: Float = -0.25
            let qYaw = simd_quatf(angle: aircraft.heading, axis: SIMD3<Float>(0, 1, 0))
            let qBank = simd_quatf(angle: bankAngle, axis: SIMD3<Float>(0, 0, 1))
            aircraft.entity.orientation = qYaw * qBank
            
            if let propeller = aircraft.entity.findEntity(named: "Propeller") {
                let propRotation = simd_quatf(angle: Float(Date().timeIntervalSince1970 * 30), axis: SIMD3<Float>(0, 0, 1))
                propeller.orientation = propRotation
            }
            
            aiAircraft[i] = aircraft
        }
    }
    
    /// Update helicopter positions and rotor animation
    private func updateHelicopters(deltaTime: Float) {
        for i in 0..<helicopters.count {
            var heli = helicopters[i]
            
            // Orbit around center point
            heli.heading += deltaTime * 0.12
            
            heli.position.x = heli.orbitCenter.x + cos(heli.heading) * heli.orbitRadius
            heli.position.z = heli.orbitCenter.z + sin(heli.heading) * heli.orbitRadius
            heli.position.y = heli.altitude + sin(heli.heading * 3) * 5
            
            heli.entity.position = heli.position
            
            // Face direction of travel with slight bank
            let facingAngle = heli.heading + .pi / 2
            let qYaw = simd_quatf(angle: facingAngle, axis: SIMD3<Float>(0, 1, 0))
            let qBank = simd_quatf(angle: -0.15, axis: SIMD3<Float>(0, 0, 1))
            heli.entity.orientation = qYaw * qBank
            
            // Spin main rotor
            if let rotor = heli.entity.findEntity(named: "MainRotor") {
                let rotorAngle = Float(Date().timeIntervalSince1970 * 15)
                rotor.orientation = simd_quatf(angle: rotorAngle, axis: SIMD3<Float>(0, 1, 0))
            }
            
            // Spin tail rotor
            if let tailRotor = heli.entity.findEntity(named: "TailRotor") {
                let tailAngle = Float(Date().timeIntervalSince1970 * 25)
                tailRotor.orientation = simd_quatf(angle: tailAngle, axis: SIMD3<Float>(1, 0, 0))
            }
            
            helicopters[i] = heli
        }
    }
    
    /// Update balloon positions with gentle drift
    private func updateBalloons(deltaTime: Float) {
        for i in 0..<balloons.count {
            var balloon = balloons[i]
            
            // Gentle drift
            balloon.position += balloon.drift * deltaTime
            
            // Bob up and down gently
            let time = Float(Date().timeIntervalSince1970)
            balloon.position.y = balloon.baseAltitude + sin(time * 0.3 + Float(i)) * 3.0
            
            // Keep balloons within bounds
            if abs(balloon.position.x) > 1000 { balloon.drift.x *= -1 }
            if abs(balloon.position.z) > 1000 { balloon.drift.z *= -1 }
            
            balloon.entity.position = balloon.position
            
            // Gentle rotation
            balloon.entity.orientation = simd_quatf(angle: time * 0.05, axis: SIMD3<Float>(0, 1, 0))
            
            balloons[i] = balloon
        }
    }
    
    /// Update bird flock positions with flapping
    private func updateBirds(deltaTime: Float) {
        let time = Float(Date().timeIntervalSince1970)
        
        for i in 0..<birdFlocks.count {
            var flock = birdFlocks[i]
            
            // Fly in gentle curves
            flock.heading += deltaTime * Float.random(in: -0.3...0.3)
            
            let speed: Float = 15.0
            flock.position.x += sin(flock.heading) * speed * deltaTime
            flock.position.z += cos(flock.heading) * speed * deltaTime
            flock.position.y = flock.altitude + sin(time * 0.5 + Float(i) * 2) * 5
            
            // Keep in bounds
            if abs(flock.position.x) > 800 || abs(flock.position.z) > 800 {
                flock.heading += .pi
            }
            
            flock.entity.position = flock.position
            flock.entity.orientation = simd_quatf(angle: flock.heading, axis: SIMD3<Float>(0, 1, 0))
            
            // Animate wing flapping for each bird in flock
            flock.flapPhase += deltaTime * 8
            for child in flock.entity.children {
                if let wings = child.findEntity(named: "Wings") {
                    let flapAngle = sin(flock.flapPhase) * 0.4
                    wings.orientation = simd_quatf(angle: flapAngle, axis: SIMD3<Float>(0, 0, 1))
                }
            }
            
            birdFlocks[i] = flock
        }
    }
}

/// Seeded random number generator for reproducible results
struct SeededRandomGenerator: RandomNumberGenerator {
    var state: UInt64
    
    init(seed: UInt64) {
        self.state = seed
    }
    
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
