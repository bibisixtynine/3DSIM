//
//  ContentView.swift
//  3DSIM
//
//  Premium Cartoon Flight Simulator Main View
//

import SwiftUI
import RealityKit
import AppKit

private typealias UIColor = NSColor

struct ContentView: View {
    // Game state
    @StateObject private var flightData = FlightDataModel()
    @StateObject private var inputController = InputController()
    @StateObject private var renderSettings = RenderSettings.shared
    @State private var isPaused = false
    @State private var cameraModeName = "Chase"
    @State private var showSettings = false
    
    // Core systems (stored for reference)
    @State private var flightPhysics: FlightPhysics?
    @State private var cameraSystem: CameraSystem?
    @State private var sceneryGenerator: SceneryGenerator?
    @State private var terrainGenerator: TerrainGenerator?
    @State private var weatherSystem: WeatherSystem?
    @State private var playerAircraft: Entity?
    @State private var propellerAngle: Float = 0
    @State private var propellerEntity: Entity?
    
    // Scene entity references for toggling visibility
    @State private var sceneRoot: Entity?
    
    var body: some View {
        ZStack {
            // 3D Scene - no gesture handling
            RealityView { content in
                createFlightSimScene(content)
            } update: { content in
                // Update loop handled by timer
            }
            .ignoresSafeArea()
            .allowsHitTesting(false) // Disable hit testing on RealityView
            
            // Instrument Panel HUD
            InstrumentPanel(
                flightData: flightData,
                cameraModeName: cameraModeName,
                isPaused: isPaused
            )
            .allowsHitTesting(false)
            
            // Virtual Controls Overlay - handles all touch/mouse input
            VirtualControlsOverlay(flightData: flightData)
            
            // Settings button (top-right)
            VStack {
                HStack {
                    Spacer()
                    Button(action: { showSettings.toggle() }) {
                        Image(systemName: "gearshape.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding(8)
                            .background(.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 12)
                    .padding(.top, 8)
                }
                Spacer()
            }
            
            // Settings panel
            if showSettings {
                settingsPanel
            }
        }
        .handleKeyboardInput(with: inputController)
        .onAppear {
            setupInputCallbacks()
            startGameLoop()
        }
    }
    
    /// Settings panel overlay
    private var settingsPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Paramètres de rendu")
                            .font(.headline)
                            .foregroundColor(.white)
                        Spacer()
                        Button(action: { showSettings = false }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.bottom, 4)
                    
                    settingsToggle("Arbres / Forêts", isOn: $renderSettings.showTrees, icon: "tree.fill")
                    settingsToggle("Maisons", isOn: $renderSettings.showHouses, icon: "house.fill")
                    settingsToggle("Routes", isOn: $renderSettings.showRoadDetails, icon: "road.lanes")
                    settingsToggle("Avions IA", isOn: $renderSettings.showAIAircraft, icon: "airplane")
                    settingsToggle("Hélicoptères", isOn: $renderSettings.showHelicopters, icon: "helicopter.circle")
                    settingsToggle("Montgolfières", isOn: $renderSettings.showBalloons, icon: "balloon.fill")
                    settingsToggle("Oiseaux", isOn: $renderSettings.showBirds, icon: "bird.fill")
                    settingsToggle("Nuages", isOn: $renderSettings.showClouds, icon: "cloud.fill")
                    settingsToggle("Météo (orage)", isOn: $renderSettings.showWeather, icon: "cloud.bolt.fill")
                    settingsToggle("Eau", isOn: $renderSettings.showWater, icon: "water.waves")
                }
                .padding(14)
                .frame(width: 240)
                .background(.ultraThinMaterial)
                .cornerRadius(12)
                .shadow(radius: 8)
                .padding(.trailing, 12)
                .padding(.top, 50)
            }
            Spacer()
        }
    }
    
    private func settingsToggle(_ label: String, isOn: Binding<Bool>, icon: String) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .frame(width: 18)
                    .foregroundColor(isOn.wrappedValue ? .blue : .gray)
                Text(label)
                    .font(.callout)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .onChange(of: isOn.wrappedValue) {
            applyRenderSettings()
        }
    }
    
    /// Apply current render settings to scene entities
    private func applyRenderSettings() {
        guard let root = sceneRoot else { return }
        
        func setEnabled(_ name: String, _ enabled: Bool) {
            root.findEntity(named: name)?.isEnabled = enabled
        }
        
        setEnabled("Forests", renderSettings.showTrees)
        setEnabled("Houses", renderSettings.showHouses)
        setEnabled("RoadDetails", renderSettings.showRoadDetails)
        setEnabled("AIAircraft", renderSettings.showAIAircraft)
        setEnabled("Helicopters", renderSettings.showHelicopters)
        setEnabled("Balloons", renderSettings.showBalloons)
        setEnabled("Birds", renderSettings.showBirds)
        setEnabled("Clouds", renderSettings.showClouds)
        setEnabled("StormClouds", renderSettings.showWeather)
        setEnabled("Lightning", renderSettings.showWeather)
        setEnabled("Rain", renderSettings.showWeather)
        setEnabled("Water", renderSettings.showWater)
    }
    
    /// Creates the complete premium cartoon flight simulator scene
    private func createFlightSimScene(_ content: any RealityViewContentProtocol) {
        // Initialize core systems
        let terrainGen = TerrainGenerator()
        terrainGenerator = terrainGen
        
        let physics = FlightPhysics()
        physics.terrainGenerator = terrainGen
        flightPhysics = physics
        
        let camera = CameraSystem()
        camera.flightPhysics = physics
        cameraSystem = camera
        
        let scenery = SceneryGenerator(terrainGenerator: terrainGen)
        sceneryGenerator = scenery
        
        let weather = WeatherSystem()
        weatherSystem = weather
        
        // Create root entity
        let rootEntity = Entity()
        rootEntity.name = "FlightSimRoot"
        
        // Add terrain (infinite, dynamically loaded)
        let terrain = terrainGen.generateTerrain()
        rootEntity.addChild(terrain)
        
        // Add airport
        let airportGen = AirportGenerator()
        let airport = airportGen.generateAirport()
        rootEntity.addChild(airport)
        
        // Add scenery (forests, houses, aircraft, helicopters, balloons, birds)
        let sceneryEntities = scenery.generateScenery()
        rootEntity.addChild(sceneryEntities)
        
        // Add weather (clouds, storms)
        let weatherEntities = weather.generateWeather()
        rootEntity.addChild(weatherEntities)
        
        // Add player aircraft
        let aircraft = scenery.createAircraftModel(index: 99)
        aircraft.name = "PlayerAircraft"
        aircraft.position = physics.position
        rootEntity.addChild(aircraft)
        playerAircraft = aircraft
        propellerEntity = aircraft.findEntity(named: "Propeller")
        
        // Add premium cartoon sky
        let sky = createPremiumSkyDome()
        rootEntity.addChild(sky)
        
        // Add premium lighting
        let lighting = createPremiumLighting()
        rootEntity.addChild(lighting)
        
        // Add camera
        _ = camera.setupCamera(in: content)
        
        // Add everything to scene
        content.add(rootEntity)
        sceneRoot = rootEntity
        
        // Apply saved render settings
        applyRenderSettings()
    }
    
    /// Create premium cartoon sky dome with gradient
    private func createPremiumSkyDome() -> Entity {
        let skyEntity = Entity()
        skyEntity.name = "Sky"
        
        // Main sky sphere - bright cartoon blue
        let skyMesh = MeshResource.generateSphere(radius: 10000)
        
        var skyMaterial = UnlitMaterial()
        skyMaterial.color = .init(tint: UIColor(red: 0.45, green: 0.72, blue: 0.95, alpha: 1.0))
        
        skyEntity.components.set(ModelComponent(mesh: skyMesh, materials: [skyMaterial]))
        skyEntity.scale = SIMD3<Float>(-1, 1, 1) // Invert normals
        
        // Sun sphere - bright golden
        let sunMesh = MeshResource.generateSphere(radius: 200)
        var sunMaterial = UnlitMaterial()
        sunMaterial.color = .init(tint: UIColor(red: 1.0, green: 0.95, blue: 0.70, alpha: 1.0))
        
        let sunEntity = Entity()
        sunEntity.components.set(ModelComponent(mesh: sunMesh, materials: [sunMaterial]))
        sunEntity.position = SIMD3<Float>(3000, 5000, 2000)
        skyEntity.addChild(sunEntity)
        
        // Sun glow halo
        let glowMesh = MeshResource.generateSphere(radius: 350)
        var glowMaterial = UnlitMaterial()
        glowMaterial.color = .init(tint: UIColor(red: 1.0, green: 0.97, blue: 0.80, alpha: 0.3))
        
        let glowEntity = Entity()
        glowEntity.components.set(ModelComponent(mesh: glowMesh, materials: [glowMaterial]))
        glowEntity.position = SIMD3<Float>(3000, 5000, 2000)
        skyEntity.addChild(glowEntity)
        
        // Horizon gradient ring - warm cartoon orange/pink near horizon
        let horizonMesh = MeshResource.generateSphere(radius: 9800)
        var horizonMaterial = UnlitMaterial()
        horizonMaterial.color = .init(tint: UIColor(red: 0.75, green: 0.85, blue: 0.95, alpha: 0.5))
        
        let horizonEntity = Entity()
        horizonEntity.components.set(ModelComponent(mesh: horizonMesh, materials: [horizonMaterial]))
        horizonEntity.scale = SIMD3<Float>(-1.0, 0.3, -1.0) // Flatten for horizon band
        skyEntity.addChild(horizonEntity)
        
        return skyEntity
    }
    
    /// Create premium scene lighting - warm, cartoon-style with rich shadows
    private func createPremiumLighting() -> Entity {
        let lightEntity = Entity()
        lightEntity.name = "Lighting"
        
        // Main sun light - warm golden
        let sunLight = DirectionalLightComponent(
            color: UIColor(red: 1.0, green: 0.95, blue: 0.85, alpha: 1.0),
            intensity: 2500,
            isRealWorldProxy: false
        )
        
        let sunEntity = Entity()
        sunEntity.components.set(sunLight)
        sunEntity.orientation = simd_quatf(angle: -.pi / 3.5, axis: SIMD3<Float>(1, 0, -0.3))
        lightEntity.addChild(sunEntity)
        
        // Fill light - soft blue sky bounce
        let fillLight = DirectionalLightComponent(
            color: UIColor(red: 0.65, green: 0.78, blue: 0.95, alpha: 1.0),
            intensity: 600,
            isRealWorldProxy: false
        )
        
        let fillEntity = Entity()
        fillEntity.components.set(fillLight)
        fillEntity.orientation = simd_quatf(angle: .pi / 4, axis: SIMD3<Float>(-1, 0, 0.5))
        lightEntity.addChild(fillEntity)
        
        return lightEntity
    }
    
    /// Setup input controller callbacks
    private func setupInputCallbacks() {
        inputController.onCycleCamera = { [self] in
            cameraSystem?.cycleMode()
            cameraModeName = cameraSystem?.modeName ?? "Unknown"
        }
        
        inputController.onToggleCockpitChase = { [self] in
            if cameraSystem?.currentMode == .cockpit {
                cameraSystem?.setMode(.chase)
            } else {
                cameraSystem?.setMode(.cockpit)
            }
            cameraModeName = cameraSystem?.modeName ?? "Unknown"
        }
        
        inputController.onTogglePause = { [self] in
            isPaused.toggle()
        }
        
        inputController.onReset = { [self] in
            flightPhysics?.resetToRunway()
            isPaused = false
        }
    }
    
    /// Start the main game loop
    private func startGameLoop() {
        var lastTime = Date()
        
        Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { _ in
            let currentTime = Date()
            let deltaTime = Float(currentTime.timeIntervalSince(lastTime))
            lastTime = currentTime
            
            guard !isPaused else { return }
            
            // Read virtual control state
            let virtualState = VirtualControlState.shared
            inputController.virtualPitch = virtualState.joystickPitch
            inputController.virtualRoll = virtualState.joystickRoll
            inputController.virtualThrottle = virtualState.throttleValue
            inputController.virtualRudder = virtualState.rudderValue
            
            // Update physics
            if let physics = flightPhysics {
                inputController.applyInputs(to: physics, deltaTime: deltaTime)
                physics.update(deltaTime: deltaTime)
                
                // Update terrain chunks
                terrainGenerator?.updateChunks(playerPosition: physics.position)
                
                // Update weather system (skip if clouds + weather both off)
                if renderSettings.showClouds || renderSettings.showWeather {
                    weatherSystem?.update(deltaTime: deltaTime, playerPosition: physics.position)
                }
                
                // Update flight data for HUD
                DispatchQueue.main.async {
                    flightData.update(from: physics)
                }
                
                // Update player aircraft entity
                if let aircraft = playerAircraft {
                    aircraft.position = physics.position
                    aircraft.orientation = physics.getRotationQuaternion()
                    
                    if let propeller = propellerEntity {
                        let idleSpeed: Float = physics.throttle > 0.01 ? 10.0 : 0.0
                        let throttleSpeed = physics.throttle * 70.0
                        let windmillSpeed = min(physics.airspeed * 0.3, 30.0)
                        propellerAngle += (idleSpeed + throttleSpeed + windmillSpeed) * deltaTime
                        if propellerAngle > 100 * .pi { propellerAngle -= 100 * .pi }
                        propeller.orientation = simd_quatf(angle: propellerAngle, axis: SIMD3<Float>(0, 0, 1))
                    }
                }
            }
            
            // Update camera
            cameraSystem?.update(deltaTime: deltaTime)
            
            // Update AI aircraft, helicopters, balloons, birds (skip if all off)
            if renderSettings.showAIAircraft || renderSettings.showHelicopters ||
               renderSettings.showBalloons || renderSettings.showBirds {
                sceneryGenerator?.updateAIAircraft(deltaTime: deltaTime,
                    aircraft: renderSettings.showAIAircraft,
                    helicopters: renderSettings.showHelicopters,
                    balloons: renderSettings.showBalloons,
                    birds: renderSettings.showBirds)
            }
        }
    }
}

#Preview {
    ContentView()
}
