//
//  AirportGenerator.swift
//  3DSIM
//
//  Airport and Runway Generation
//

import Foundation
import RealityKit
import simd
import AppKit

private typealias UIColor = NSColor

/// Generates airport infrastructure including runways, taxiways, and buildings
class AirportGenerator {
    
    // Runway configuration
    let runwayLength: Float = 400.0      // meters
    let runwayWidth: Float = 30.0        // meters
    let runwayHeading: Float = 0.0       // degrees (north-south)
    
    // Position (center of runway)
    let runwayCenter: SIMD3<Float> = SIMD3<Float>(0, 0.1, 0)
    
    /// Remote airstrip locations (x, z, heading in degrees)
    let remoteAirstrips: [(x: Float, z: Float, heading: Float, name: String)] = [
        (x: 800, z: 700, heading: 45, name: "RemoteStrip_NE"),
        (x: -700, z: -500, heading: 90, name: "RemoteStrip_SW"),
        (x: -900, z: 600, heading: 0, name: "RemoteStrip_NW"),
    ]
    
    /// Generate complete airport with main and remote strips
    func generateAirport() -> Entity {
        let airportEntity = Entity()
        airportEntity.name = "Airport"
        
        // Main runway
        let runway = generateRunway()
        airportEntity.addChild(runway)
        
        // Taxiways
        let taxiways = generateTaxiways()
        airportEntity.addChild(taxiways)
        
        // Runway markings
        let markings = generateRunwayMarkings()
        airportEntity.addChild(markings)
        
        // Airport buildings
        let buildings = generateAirportBuildings()
        airportEntity.addChild(buildings)
        
        // Runway lights
        let lights = generateRunwayLights()
        airportEntity.addChild(lights)
        
        // Windsock
        let windsock = generateWindsock()
        airportEntity.addChild(windsock)
        
        // Remote airstrips
        for strip in remoteAirstrips {
            let remoteStrip = generateRemoteAirstrip(name: strip.name)
            remoteStrip.position = SIMD3<Float>(strip.x, 0.1, strip.z)
            remoteStrip.orientation = simd_quatf(angle: strip.heading * .pi / 180, axis: SIMD3<Float>(0, 1, 0))
            airportEntity.addChild(remoteStrip)
        }
        
        return airportEntity
    }
    
    /// Generate a small remote grass/paved airstrip
    private func generateRemoteAirstrip(name: String) -> Entity {
        let stripEntity = Entity()
        stripEntity.name = name
        
        let stripLength: Float = 250
        let stripWidth: Float = 15
        
        // Runway surface - slightly different look for remote strip
        let stripMesh = MeshResource.generatePlane(width: stripWidth, depth: stripLength)
        var stripMat = SimpleMaterial()
        stripMat.color = .init(tint: UIColor(red: 0.28, green: 0.28, blue: 0.30, alpha: 1.0))
        
        let surface = Entity()
        surface.components.set(ModelComponent(mesh: stripMesh, materials: [stripMat]))
        stripEntity.addChild(surface)
        
        // Centerline
        let centerMesh = MeshResource.generatePlane(width: 0.4, depth: stripLength - 20)
        var centerMat = SimpleMaterial()
        centerMat.color = .init(tint: .white)
        
        let centerLine = Entity()
        centerLine.components.set(ModelComponent(mesh: centerMesh, materials: [centerMat]))
        centerLine.position.y = 0.02
        stripEntity.addChild(centerLine)
        
        // Edge lights
        let lightMesh = MeshResource.generateSphere(radius: 0.15)
        var lightMat = SimpleMaterial()
        lightMat.color = .init(tint: UIColor(red: 1.0, green: 1.0, blue: 0.8, alpha: 1.0))
        
        var z: Float = -stripLength / 2
        while z <= stripLength / 2 {
            for side in [-1.0, 1.0] as [Float] {
                let light = Entity()
                light.components.set(ModelComponent(mesh: lightMesh, materials: [lightMat]))
                light.position = SIMD3<Float>(side * (stripWidth / 2 + 1), 0.2, z)
                stripEntity.addChild(light)
            }
            z += 40
        }
        
        // Small shed / hangar
        let shedMesh = MeshResource.generateBox(size: SIMD3<Float>(12, 6, 15), cornerRadius: 0.5)
        var shedMat = SimpleMaterial()
        shedMat.color = .init(tint: UIColor(red: 0.65, green: 0.60, blue: 0.55, alpha: 1.0))
        
        let shed = Entity()
        shed.components.set(ModelComponent(mesh: shedMesh, materials: [shedMat]))
        shed.position = SIMD3<Float>(stripWidth / 2 + 20, 3, 0)
        stripEntity.addChild(shed)
        
        // Windsock
        let sock = generateWindsock()
        sock.position = SIMD3<Float>(-stripWidth / 2 - 8, 0, stripLength / 4)
        stripEntity.addChild(sock)
        
        return stripEntity
    }
    
    /// Generate main runway surface
    private func generateRunway() -> Entity {
        let runwayEntity = Entity()
        runwayEntity.name = "Runway"
        
        // Main runway surface
        let runwayMesh = MeshResource.generatePlane(width: runwayWidth, depth: runwayLength)
        
        var runwayMaterial = SimpleMaterial()
        runwayMaterial.color = .init(tint: UIColor(red: 0.2, green: 0.2, blue: 0.22, alpha: 1.0))
        
        runwayEntity.components.set(ModelComponent(mesh: runwayMesh, materials: [runwayMaterial]))
        runwayEntity.position = runwayCenter
        
        return runwayEntity
    }
    
    /// Generate taxiways
    private func generateTaxiways() -> Entity {
        let taxiwayEntity = Entity()
        taxiwayEntity.name = "Taxiways"
        
        var taxiwayMaterial = SimpleMaterial()
        taxiwayMaterial.color = .init(tint: UIColor(red: 0.25, green: 0.25, blue: 0.27, alpha: 1.0))
        
        // Main parallel taxiway
        let taxiway1 = MeshResource.generatePlane(width: 15.0, depth: runwayLength * 0.8)
        let taxiway1Entity = Entity()
        taxiway1Entity.components.set(ModelComponent(mesh: taxiway1, materials: [taxiwayMaterial]))
        taxiway1Entity.position = SIMD3<Float>(runwayWidth / 2 + 20, 0.08, 0)
        taxiwayEntity.addChild(taxiway1Entity)
        
        // Connecting taxiways
        let connectorMesh = MeshResource.generatePlane(width: 25.0, depth: 12.0)
        
        for z in [-runwayLength * 0.35, 0.0, runwayLength * 0.35] as [Float] {
            let connector = Entity()
            connector.components.set(ModelComponent(mesh: connectorMesh, materials: [taxiwayMaterial]))
            connector.position = SIMD3<Float>(runwayWidth / 2 + 7.5, 0.08, z)
            taxiwayEntity.addChild(connector)
        }
        
        // Apron/parking area
        let apronMesh = MeshResource.generatePlane(width: 80.0, depth: 60.0)
        let apronEntity = Entity()
        apronEntity.components.set(ModelComponent(mesh: apronMesh, materials: [taxiwayMaterial]))
        apronEntity.position = SIMD3<Float>(runwayWidth / 2 + 70, 0.08, 0)
        taxiwayEntity.addChild(apronEntity)
        
        return taxiwayEntity
    }
    
    /// Generate runway markings (centerline, threshold, numbers)
    private func generateRunwayMarkings() -> Entity {
        let markingsEntity = Entity()
        markingsEntity.name = "RunwayMarkings"
        
        var whiteMaterial = SimpleMaterial()
        whiteMaterial.color = .init(tint: .white)
        
        var yellowMaterial = SimpleMaterial()
        yellowMaterial.color = .init(tint: UIColor(red: 1.0, green: 0.9, blue: 0.0, alpha: 1.0))
        
        // Centerline dashes
        let dashLength: Float = 15.0
        let dashWidth: Float = 0.5
        let dashSpacing: Float = 15.0
        let dashMesh = MeshResource.generatePlane(width: dashWidth, depth: dashLength)
        
        var z = -runwayLength / 2 + 30
        while z < runwayLength / 2 - 30 {
            let dash = Entity()
            dash.components.set(ModelComponent(mesh: dashMesh, materials: [whiteMaterial]))
            dash.position = SIMD3<Float>(0, 0.12, z)
            markingsEntity.addChild(dash)
            z += dashLength + dashSpacing
        }
        
        // Threshold markings
        let thresholdBarMesh = MeshResource.generatePlane(width: 1.5, depth: 20.0)
        
        for end in [-1.0, 1.0] as [Float] {
            let thresholdZ = end * (runwayLength / 2 - 15)
            
            for i in -4...4 {
                if i == 0 { continue }  // Skip center
                let bar = Entity()
                bar.components.set(ModelComponent(mesh: thresholdBarMesh, materials: [whiteMaterial]))
                bar.position = SIMD3<Float>(Float(i) * 2.5, 0.12, thresholdZ)
                markingsEntity.addChild(bar)
            }
        }
        
        // Runway numbers (simplified as rectangles)
        let numberMesh = MeshResource.generatePlane(width: 4.0, depth: 12.0)
        
        // "36" at north end
        let num36 = Entity()
        num36.components.set(ModelComponent(mesh: numberMesh, materials: [whiteMaterial]))
        num36.position = SIMD3<Float>(0, 0.12, runwayLength / 2 - 45)
        markingsEntity.addChild(num36)
        
        // "18" at south end
        let num18 = Entity()
        num18.components.set(ModelComponent(mesh: numberMesh, materials: [whiteMaterial]))
        num18.position = SIMD3<Float>(0, 0.12, -runwayLength / 2 + 45)
        markingsEntity.addChild(num18)
        
        // Edge markings (yellow)
        let edgeMesh = MeshResource.generatePlane(width: 0.5, depth: runwayLength - 20)
        
        for side in [-1.0, 1.0] as [Float] {
            let edge = Entity()
            edge.components.set(ModelComponent(mesh: edgeMesh, materials: [yellowMaterial]))
            edge.position = SIMD3<Float>(side * (runwayWidth / 2 - 1), 0.12, 0)
            markingsEntity.addChild(edge)
        }
        
        // Taxiway centerline markings (yellow dashes)
        let taxiDashMesh = MeshResource.generatePlane(width: 0.3, depth: 3.0)
        z = -runwayLength * 0.4
        while z < runwayLength * 0.4 {
            let dash = Entity()
            dash.components.set(ModelComponent(mesh: taxiDashMesh, materials: [yellowMaterial]))
            dash.position = SIMD3<Float>(runwayWidth / 2 + 20, 0.1, z)
            markingsEntity.addChild(dash)
            z += 6.0
        }
        
        return markingsEntity
    }
    
    /// Generate airport buildings (terminal, hangars, tower)
    private func generateAirportBuildings() -> Entity {
        let buildingsEntity = Entity()
        buildingsEntity.name = "AirportBuildings"
        
        // Control tower
        let tower = generateControlTower()
        tower.position = SIMD3<Float>(runwayWidth / 2 + 100, 0, -50)
        buildingsEntity.addChild(tower)
        
        // Main terminal building
        let terminal = generateTerminal()
        terminal.position = SIMD3<Float>(runwayWidth / 2 + 120, 0, 30)
        buildingsEntity.addChild(terminal)
        
        // Hangars
        for i in 0..<3 {
            let hangar = generateHangar(index: i)
            hangar.position = SIMD3<Float>(runwayWidth / 2 + 80, 0, Float(i - 1) * 50)
            buildingsEntity.addChild(hangar)
        }
        
        return buildingsEntity
    }
    
    /// Generate control tower
    private func generateControlTower() -> Entity {
        let towerEntity = Entity()
        towerEntity.name = "ControlTower"
        
        // Tower shaft
        let shaftMesh = MeshResource.generateBox(size: SIMD3<Float>(8, 25, 8))
        var shaftMaterial = SimpleMaterial()
        shaftMaterial.color = .init(tint: UIColor(red: 0.85, green: 0.85, blue: 0.88, alpha: 1.0))
        
        let shaftEntity = Entity()
        shaftEntity.components.set(ModelComponent(mesh: shaftMesh, materials: [shaftMaterial]))
        shaftEntity.position.y = 12.5
        towerEntity.addChild(shaftEntity)
        
        // Control room (top)
        let cabMesh = MeshResource.generateBox(size: SIMD3<Float>(12, 5, 12))
        var cabMaterial = SimpleMaterial()
        cabMaterial.color = .init(tint: UIColor(red: 0.3, green: 0.5, blue: 0.6, alpha: 1.0))
        
        let cabEntity = Entity()
        cabEntity.components.set(ModelComponent(mesh: cabMesh, materials: [cabMaterial]))
        cabEntity.position.y = 27.5
        towerEntity.addChild(cabEntity)
        
        // Windows (glass band)
        let windowMesh = MeshResource.generateBox(size: SIMD3<Float>(12.2, 3, 12.2))
        var windowMaterial = SimpleMaterial()
        windowMaterial.color = .init(tint: UIColor(red: 0.6, green: 0.8, blue: 0.9, alpha: 0.7))
        
        let windowEntity = Entity()
        windowEntity.components.set(ModelComponent(mesh: windowMesh, materials: [windowMaterial]))
        windowEntity.position.y = 27.5
        towerEntity.addChild(windowEntity)
        
        // Antenna
        let antennaMesh = MeshResource.generateBox(size: SIMD3<Float>(0.3, 6, 0.3))
        var antennaMaterial = SimpleMaterial()
        antennaMaterial.color = .init(tint: UIColor(red: 0.3, green: 0.3, blue: 0.3, alpha: 1.0))
        
        let antennaEntity = Entity()
        antennaEntity.components.set(ModelComponent(mesh: antennaMesh, materials: [antennaMaterial]))
        antennaEntity.position.y = 33
        towerEntity.addChild(antennaEntity)
        
        return towerEntity
    }
    
    /// Generate terminal building
    private func generateTerminal() -> Entity {
        let terminalEntity = Entity()
        terminalEntity.name = "Terminal"
        
        // Main building
        let mainMesh = MeshResource.generateBox(size: SIMD3<Float>(40, 8, 25))
        var mainMaterial = SimpleMaterial()
        mainMaterial.color = .init(tint: UIColor(red: 0.9, green: 0.9, blue: 0.92, alpha: 1.0))
        
        let mainEntity = Entity()
        mainEntity.components.set(ModelComponent(mesh: mainMesh, materials: [mainMaterial]))
        mainEntity.position.y = 4
        terminalEntity.addChild(mainEntity)
        
        // Roof
        let roofMesh = MeshResource.generateBox(size: SIMD3<Float>(42, 1, 27))
        var roofMaterial = SimpleMaterial()
        roofMaterial.color = .init(tint: UIColor(red: 0.3, green: 0.35, blue: 0.4, alpha: 1.0))
        
        let roofEntity = Entity()
        roofEntity.components.set(ModelComponent(mesh: roofMesh, materials: [roofMaterial]))
        roofEntity.position.y = 8.5
        terminalEntity.addChild(roofEntity)
        
        // Glass facade
        let glassMesh = MeshResource.generateBox(size: SIMD3<Float>(40.5, 6, 0.3))
        var glassMaterial = SimpleMaterial()
        glassMaterial.color = .init(tint: UIColor(red: 0.5, green: 0.7, blue: 0.9, alpha: 0.6))
        
        let glassEntity = Entity()
        glassEntity.components.set(ModelComponent(mesh: glassMesh, materials: [glassMaterial]))
        glassEntity.position = SIMD3<Float>(0, 4, -12.7)
        terminalEntity.addChild(glassEntity)
        
        return terminalEntity
    }
    
    /// Generate hangar building
    private func generateHangar(index: Int) -> Entity {
        let hangarEntity = Entity()
        hangarEntity.name = "Hangar_\(index)"
        
        let width: Float = 30
        let depth: Float = 35
        let height: Float = 12
        
        // Walls
        let wallMesh = MeshResource.generateBox(size: SIMD3<Float>(width, height, depth))
        var wallMaterial = SimpleMaterial()
        wallMaterial.color = .init(tint: UIColor(red: 0.7, green: 0.7, blue: 0.75, alpha: 1.0))
        
        let wallEntity = Entity()
        wallEntity.components.set(ModelComponent(mesh: wallMesh, materials: [wallMaterial]))
        wallEntity.position.y = height / 2
        hangarEntity.addChild(wallEntity)
        
        // Roof (curved approximation)
        let roofMesh = MeshResource.generateBox(size: SIMD3<Float>(width + 1, 2, depth + 1))
        var roofMaterial = SimpleMaterial()
        roofMaterial.color = .init(tint: UIColor(red: 0.4, green: 0.45, blue: 0.5, alpha: 1.0))
        
        let roofEntity = Entity()
        roofEntity.components.set(ModelComponent(mesh: roofMesh, materials: [roofMaterial]))
        roofEntity.position.y = height + 1
        hangarEntity.addChild(roofEntity)
        
        // Hangar door (closed)
        let doorMesh = MeshResource.generateBox(size: SIMD3<Float>(width - 2, height - 1, 0.5))
        var doorMaterial = SimpleMaterial()
        doorMaterial.color = .init(tint: UIColor(red: 0.3, green: 0.35, blue: 0.4, alpha: 1.0))
        
        let doorEntity = Entity()
        doorEntity.components.set(ModelComponent(mesh: doorMesh, materials: [doorMaterial]))
        doorEntity.position = SIMD3<Float>(0, (height - 1) / 2, -depth / 2 - 0.3)
        hangarEntity.addChild(doorEntity)
        
        return hangarEntity
    }
    
    /// Generate runway edge lights
    private func generateRunwayLights() -> Entity {
        let lightsEntity = Entity()
        lightsEntity.name = "RunwayLights"
        
        let lightMesh = MeshResource.generateSphere(radius: 0.2)
        
        var whiteLightMaterial = SimpleMaterial()
        whiteLightMaterial.color = .init(tint: UIColor(red: 1.0, green: 1.0, blue: 0.9, alpha: 1.0))
        
        var greenLightMaterial = SimpleMaterial()
        greenLightMaterial.color = .init(tint: UIColor(red: 0.0, green: 1.0, blue: 0.3, alpha: 1.0))
        
        var redLightMaterial = SimpleMaterial()
        redLightMaterial.color = .init(tint: UIColor(red: 1.0, green: 0.2, blue: 0.2, alpha: 1.0))
        
        // Edge lights
        let spacing: Float = 30.0
        var z = -runwayLength / 2
        
        while z <= runwayLength / 2 {
            for side in [-1.0, 1.0] as [Float] {
                let light = Entity()
                light.components.set(ModelComponent(mesh: lightMesh, materials: [whiteLightMaterial]))
                light.position = SIMD3<Float>(side * (runwayWidth / 2 + 1), 0.3, z)
                lightsEntity.addChild(light)
            }
            z += spacing
        }
        
        // Threshold lights (green)
        for i in -8...8 {
            let light = Entity()
            light.components.set(ModelComponent(mesh: lightMesh, materials: [greenLightMaterial]))
            light.position = SIMD3<Float>(Float(i) * 2, 0.3, -runwayLength / 2 + 5)
            lightsEntity.addChild(light)
        }
        
        // End lights (red)
        for i in -8...8 {
            let light = Entity()
            light.components.set(ModelComponent(mesh: lightMesh, materials: [redLightMaterial]))
            light.position = SIMD3<Float>(Float(i) * 2, 0.3, runwayLength / 2 - 5)
            lightsEntity.addChild(light)
        }
        
        // PAPI lights (precision approach path indicator)
        for i in 0..<4 {
            let papi = Entity()
            let isWhite = i < 2
            papi.components.set(ModelComponent(mesh: lightMesh, materials: [isWhite ? whiteLightMaterial : redLightMaterial]))
            papi.position = SIMD3<Float>(-runwayWidth / 2 - 10, 0.5, -runwayLength / 2 + 80 + Float(i) * 3)
            papi.scale = SIMD3<Float>(1.5, 1.5, 1.5)
            lightsEntity.addChild(papi)
        }
        
        return lightsEntity
    }
    
    /// Generate windsock
    private func generateWindsock() -> Entity {
        let windsockEntity = Entity()
        windsockEntity.name = "Windsock"
        
        // Pole
        let poleMesh = MeshResource.generateBox(size: SIMD3<Float>(0.15, 6, 0.15))
        var poleMaterial = SimpleMaterial()
        poleMaterial.color = .init(tint: UIColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1.0))
        
        let poleEntity = Entity()
        poleEntity.components.set(ModelComponent(mesh: poleMesh, materials: [poleMaterial]))
        poleEntity.position.y = 3
        windsockEntity.addChild(poleEntity)
        
        // Sock (cone shape approximated)
        let sockMesh = MeshResource.generateBox(size: SIMD3<Float>(0.8, 0.8, 2.5))
        var sockMaterial = SimpleMaterial()
        sockMaterial.color = .init(tint: UIColor(red: 1.0, green: 0.5, blue: 0.0, alpha: 1.0))
        
        let sockEntity = Entity()
        sockEntity.components.set(ModelComponent(mesh: sockMesh, materials: [sockMaterial]))
        sockEntity.position = SIMD3<Float>(1.2, 5.8, 0)
        
        // Slight angle for wind effect
        sockEntity.orientation = simd_quatf(angle: 0.3, axis: SIMD3<Float>(0, 0, 1))
        windsockEntity.addChild(sockEntity)
        
        // Position near runway
        windsockEntity.position = SIMD3<Float>(-runwayWidth / 2 - 15, 0, runwayLength / 4)
        
        return windsockEntity
    }
}
