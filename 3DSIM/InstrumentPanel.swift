//
//  InstrumentPanel.swift
//  3DSIM
//
//  Flight Instruments HUD Display
//

import SwiftUI
import Combine

/// Flight instruments overlay view
struct InstrumentPanel: View {
    @ObservedObject var flightData: FlightDataModel
    let cameraModeName: String
    let isPaused: Bool
    
    var body: some View {
        ZStack {
            // Main instrument cluster at bottom
            VStack {
                Spacer()
                
                HStack(alignment: .bottom, spacing: 20) {
                    // Left instruments
                    VStack(spacing: 10) {
                        AirspeedIndicator(airspeed: flightData.airspeedKnots)
                        AltimeterView(altitude: flightData.altitude)
                    }
                    
                    // Center - Attitude Indicator
                    AttitudeIndicator(
                        pitch: flightData.pitch,
                        roll: flightData.roll,
                        isStalling: flightData.isStalling,
                        stallWarning: flightData.stallWarning
                    )
                    
                    // Right instruments
                    VStack(spacing: 10) {
                        VerticalSpeedIndicator(verticalSpeed: flightData.verticalSpeed)
                        HeadingIndicator(heading: flightData.heading)
                    }
                }
                .padding(.bottom, 20)
            }
            
            // Top status bar
            VStack {
                HStack {
                    // Throttle and flaps
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("THR")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                            ThrottleBar(value: flightData.throttle)
                        }
                        HStack {
                            Text("FLP")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                            FlapsBar(value: flightData.flaps)
                        }
                        HStack {
                            Text("BRK")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                            BrakesIndicator(value: flightData.brakes)
                        }
                    }
                    .foregroundColor(.white)
                    .padding(10)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(8)
                    
                    Spacer()
                    
                    // Status indicators
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("CAM: \(cameraModeName)")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                        
                        if flightData.isOnGround {
                            Text("ON GROUND")
                                .foregroundColor(.green)
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                        }
                        
                        if flightData.stallWarning {
                            Text("⚠️ STALL WARNING")
                                .foregroundColor(.yellow)
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                        }
                        
                        if flightData.isStalling {
                            Text("🔴 STALL")
                                .foregroundColor(.red)
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                        }
                    }
                    .foregroundColor(.white)
                    .padding(10)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(8)
                }
                .padding()
                
                Spacer()
            }
            
            // Pause overlay
            if isPaused {
                Color.black.opacity(0.5)
                Text("PAUSED\nPress P to Resume")
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
            }
            
            // Controls help (bottom left)
            VStack {
                Spacer()
                HStack {
                    ControlsHelp()
                    Spacer()
                }
                .padding()
            }
        }
    }
}

/// Airspeed indicator gauge
struct AirspeedIndicator: View {
    let airspeed: Float
    
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.8))
                .frame(width: 100, height: 100)
            
            Circle()
                .stroke(Color.white, lineWidth: 2)
                .frame(width: 95, height: 95)
            
            // Speed arc markings
            ForEach(0..<13) { i in
                let angle = Double(i) * 22.5 - 135
                let isMain = i % 2 == 0
                Rectangle()
                    .fill(speedColor(for: Float(i) * 20))
                    .frame(width: isMain ? 3 : 1, height: isMain ? 12 : 8)
                    .offset(y: -38)
                    .rotationEffect(.degrees(angle))
            }
            
            // Needle
            let needleAngle = min(max(Double(airspeed) / 240 * 270 - 135, -135), 135)
            Rectangle()
                .fill(Color.white)
                .frame(width: 3, height: 35)
                .offset(y: -17)
                .rotationEffect(.degrees(needleAngle))
            
            // Center cap
            Circle()
                .fill(Color.gray)
                .frame(width: 10, height: 10)
            
            // Value display
            VStack {
                Spacer()
                Text("\(Int(airspeed))")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                Text("KTS")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.gray)
            }
            .frame(height: 70)
        }
        .frame(width: 100, height: 100)
    }
    
    func speedColor(for speed: Float) -> Color {
        if speed < 60 { return .red }        // Stall speed
        if speed < 80 { return .yellow }     // Caution
        if speed < 160 { return .green }     // Normal
        if speed < 200 { return .yellow }    // Caution high
        return .red                          // Overspeed
    }
}

/// Altimeter gauge
struct AltimeterView: View {
    let altitude: Float
    
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.8))
                .frame(width: 100, height: 100)
            
            Circle()
                .stroke(Color.white, lineWidth: 2)
                .frame(width: 95, height: 95)
            
            // Scale markings
            ForEach(0..<10) { i in
                let angle = Double(i) * 36 - 90
                VStack(spacing: 2) {
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 2, height: 10)
                    Text("\(i)")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.white)
                }
                .offset(y: -32)
                .rotationEffect(.degrees(angle))
            }
            
            // Hundreds needle (short)
            let hundredsAngle = Double(altitude.truncatingRemainder(dividingBy: 1000)) / 1000 * 360 - 90
            Rectangle()
                .fill(Color.white)
                .frame(width: 4, height: 25)
                .offset(y: -12)
                .rotationEffect(.degrees(hundredsAngle))
            
            // Thousands needle (long)
            let thousandsAngle = Double(altitude) / 10000 * 360 - 90
            Rectangle()
                .fill(Color.white)
                .frame(width: 2, height: 35)
                .offset(y: -17)
                .rotationEffect(.degrees(thousandsAngle))
            
            // Center cap
            Circle()
                .fill(Color.gray)
                .frame(width: 10, height: 10)
            
            // Digital readout
            VStack {
                Spacer()
                Text("\(Int(altitude))")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                Text("FT")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.gray)
            }
            .frame(height: 70)
        }
        .frame(width: 100, height: 100)
    }
}

/// Attitude indicator (artificial horizon)
struct AttitudeIndicator: View {
    let pitch: Float  // In radians
    let roll: Float   // In radians
    let isStalling: Bool
    let stallWarning: Bool
    
    var body: some View {
        ZStack {
            // Background (clipped horizon)
            Circle()
                .fill(Color.black.opacity(0.8))
                .frame(width: 150, height: 150)
            
            // Horizon
            GeometryReader { geo in
                let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                let pitchOffset = CGFloat(pitch * 180 / .pi) * 2 // Scaled pitch
                
                ZStack {
                    // Sky
                    Rectangle()
                        .fill(LinearGradient(
                            colors: [Color.blue.opacity(0.8), Color.blue.opacity(0.5)],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                        .frame(height: 150)
                        .offset(y: -75 + pitchOffset)
                    
                    // Ground
                    Rectangle()
                        .fill(LinearGradient(
                            colors: [Color.brown.opacity(0.7), Color.brown.opacity(0.9)],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                        .frame(height: 150)
                        .offset(y: 75 + pitchOffset)
                    
                    // Horizon line
                    Rectangle()
                        .fill(Color.white)
                        .frame(height: 2)
                        .offset(y: pitchOffset)
                    
                    // Pitch ladder
                    ForEach([-20, -10, 10, 20], id: \.self) { deg in
                        Rectangle()
                            .fill(Color.white.opacity(0.7))
                            .frame(width: deg == 0 ? 60 : 30, height: 1)
                            .offset(y: CGFloat(deg) * 2 + pitchOffset)
                    }
                }
                .rotationEffect(.radians(Double(-roll)))
                .position(center)
            }
            .frame(width: 150, height: 150)
            .clipShape(Circle())
            
            // Aircraft reference (fixed)
            Path { path in
                path.move(to: CGPoint(x: 45, y: 75))
                path.addLine(to: CGPoint(x: 65, y: 75))
                path.addLine(to: CGPoint(x: 75, y: 80))
                path.addLine(to: CGPoint(x: 85, y: 75))
                path.addLine(to: CGPoint(x: 105, y: 75))
            }
            .stroke(Color.yellow, lineWidth: 3)
            .frame(width: 150, height: 150)
            
            // Center dot
            Circle()
                .fill(Color.yellow)
                .frame(width: 6, height: 6)
            
            // Bank angle indicators
            ForEach([0, 10, 20, 30, 45, 60], id: \.self) { angle in
                ForEach([-1, 1], id: \.self) { side in
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 2, height: angle == 0 ? 15 : 8)
                        .offset(y: -68)
                        .rotationEffect(.degrees(Double(angle * side)))
                }
            }
            
            // Roll pointer
            Triangle()
                .fill(Color.white)
                .frame(width: 10, height: 10)
                .offset(y: -60)
                .rotationEffect(.radians(Double(-roll)))
            
            // Border
            Circle()
                .stroke(isStalling ? Color.red : (stallWarning ? Color.yellow : Color.white), lineWidth: 3)
                .frame(width: 148, height: 148)
        }
        .frame(width: 150, height: 150)
    }
}

/// Triangle shape for roll indicator
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Vertical speed indicator
struct VerticalSpeedIndicator: View {
    let verticalSpeed: Float  // In m/s
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.8))
                .frame(width: 60, height: 100)
            
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white, lineWidth: 1)
                .frame(width: 58, height: 98)
            
            // Scale
            VStack(spacing: 0) {
                ForEach([20, 10, 0, -10, -20], id: \.self) { val in
                    HStack {
                        Text("\(abs(val))")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.white)
                            .frame(width: 20)
                        Rectangle()
                            .fill(Color.white)
                            .frame(width: 10, height: 1)
                    }
                    if val != -20 {
                        Spacer()
                    }
                }
            }
            .frame(height: 80)
            .padding(.horizontal, 5)
            
            // Needle
            let clampedVS = min(max(verticalSpeed * 3.28084 / 100, -20), 20) // Convert to hundreds of ft/min
            let needleY = -clampedVS * 2
            
            HStack(spacing: 0) {
                Spacer()
                Rectangle()
                    .fill(Color.green)
                    .frame(width: 20, height: 3)
            }
            .offset(y: CGFloat(needleY))
            .frame(width: 60)
            
            // Label
            VStack {
                Spacer()
                Text("VS")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.gray)
            }
            .frame(height: 90)
        }
        .frame(width: 60, height: 100)
    }
}

/// Heading indicator (compass)
struct HeadingIndicator: View {
    let heading: Float  // In degrees
    
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.8))
                .frame(width: 100, height: 100)
            
            Circle()
                .stroke(Color.white, lineWidth: 2)
                .frame(width: 95, height: 95)
            
            // Compass card (rotates)
            ZStack {
                ForEach(0..<36) { i in
                    let angle = Double(i) * 10
                    let isCardinal = i % 9 == 0
                    let isMain = i % 3 == 0
                    
                    VStack(spacing: 2) {
                        Rectangle()
                            .fill(Color.white)
                            .frame(width: isCardinal ? 3 : (isMain ? 2 : 1), 
                                   height: isCardinal ? 12 : (isMain ? 8 : 5))
                        
                        if isCardinal {
                            Text(cardinalDirection(for: i * 10))
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(i == 0 ? .red : .white)
                        } else if isMain {
                            Text("\(i)")
                                .font(.system(size: 7, design: .monospaced))
                                .foregroundColor(.white)
                        }
                    }
                    .offset(y: -35)
                    .rotationEffect(.degrees(angle))
                }
            }
            .rotationEffect(.degrees(Double(-heading)))
            
            // Fixed aircraft indicator
            Path { path in
                path.move(to: CGPoint(x: 50, y: 15))
                path.addLine(to: CGPoint(x: 50, y: 30))
            }
            .stroke(Color.yellow, lineWidth: 3)
            .frame(width: 100, height: 100)
            
            // Digital readout
            VStack {
                Spacer()
                Text(String(format: "%03.0f°", heading))
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
            }
            .frame(height: 75)
        }
        .frame(width: 100, height: 100)
    }
    
    func cardinalDirection(for degrees: Int) -> String {
        switch degrees {
        case 0: return "N"
        case 90: return "E"
        case 180: return "S"
        case 270: return "W"
        default: return ""
        }
    }
}

/// Throttle bar indicator
struct ThrottleBar: View {
    let value: Float  // 0 to 1
    
    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(Color.gray.opacity(0.5))
                .frame(width: 80, height: 12)
            
            Rectangle()
                .fill(Color.green)
                .frame(width: CGFloat(value) * 80, height: 12)
        }
        .cornerRadius(3)
    }
}

/// Flaps bar indicator
struct FlapsBar: View {
    let value: Float  // 0 to 1
    
    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(Color.gray.opacity(0.5))
                .frame(width: 80, height: 12)
            
            Rectangle()
                .fill(Color.orange)
                .frame(width: CGFloat(value) * 80, height: 12)
        }
        .cornerRadius(3)
    }
}

/// Brakes indicator
struct BrakesIndicator: View {
    let value: Float  // 0 to 1
    
    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(Color.gray.opacity(0.5))
                .frame(width: 80, height: 12)
            
            Rectangle()
                .fill(value > 0.1 ? Color.red : Color.gray)
                .frame(width: CGFloat(value) * 80, height: 12)
        }
        .cornerRadius(3)
    }
}

/// Controls help overlay - AZERTY keyboard layout
struct ControlsHelp: View {
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: { isExpanded.toggle() }) {
                HStack {
                    Text(isExpanded ? "▼" : "▶")
                    Text("Controles (AZERTY)")
                }
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Z/S - Gaz")
                    Text("↑/↓ - Tangage")
                    Text("←/→ - Roulis")
                    Text("Q/D - Gouverne")
                    Text("F - Volets")
                    Text("B/Espace - Freins")
                    Text("C - Camera")
                    Text("V - Cockpit/Ext")
                    Text("P - Pause")
                    Text("R - Reset")
                    Divider().background(Color.white.opacity(0.3))
                    Text("Joystick/Manette")
                    Text("virtuels disponibles")
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))
            }
        }
        .padding(8)
        .background(Color.black.opacity(0.6))
        .cornerRadius(8)
    }
}

/// Observable flight data model
class FlightDataModel: ObservableObject {
    @Published var airspeedKnots: Float = 0
    @Published var altitude: Float = 0
    @Published var verticalSpeed: Float = 0
    @Published var heading: Float = 0
    @Published var pitch: Float = 0
    @Published var roll: Float = 0
    @Published var throttle: Float = 0
    @Published var flaps: Float = 0
    @Published var brakes: Float = 0
    @Published var isOnGround: Bool = true
    @Published var isStalling: Bool = false
    @Published var stallWarning: Bool = false
    
    // Control surface positions (-1 to 1)
    @Published var elevator: Float = 0
    @Published var aileron: Float = 0
    @Published var rudder: Float = 0
    
    func update(from physics: FlightPhysics) {
        airspeedKnots = physics.airspeedKnots
        altitude = physics.altitudeAGL * 3.28084  // Convert to feet
        verticalSpeed = physics.verticalSpeed
        heading = physics.heading
        pitch = physics.orientation.x
        roll = physics.orientation.z
        throttle = physics.throttle
        flaps = physics.flaps
        brakes = physics.brakes
        isOnGround = physics.isOnGround
        isStalling = physics.isStalling
        stallWarning = physics.stallWarning
        
        // Control surface positions
        elevator = physics.elevator
        aileron = physics.aileron
        rudder = physics.rudder
    }
}
