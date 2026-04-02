//
//  VirtualControls.swift
//  3DSIM
//
//  Virtual Joystick, Throttle, and Flight Control Display
//  Using NSView for mouse handling to avoid SwiftUI gesture conflicts
//

import SwiftUI
import AppKit

/// Shared state for virtual controls
class VirtualControlState {
    static let shared = VirtualControlState()
    
    var joystickPitch: Float = 0
    var joystickRoll: Float = 0
    var throttleValue: Float = 0
    var rudderValue: Float = 0
    
    private init() {}
}

// MARK: - NSView-based Joystick

class JoystickNSView: NSView {
    var size: CGFloat = 150
    var knobSize: CGFloat = 50
    var isDragging = false
    var knobOffset: CGPoint = .zero
    
    override var isFlipped: Bool { true }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        let center = CGPoint(x: bounds.width / 2, y: bounds.height / 2)
        let radius = size / 2
        
        // Background circle
        context.setFillColor(NSColor.black.withAlphaComponent(0.4).cgColor)
        context.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: size, height: size))
        
        // Outer ring
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.5).cgColor)
        context.setLineWidth(2)
        context.strokeEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: size, height: size))
        
        // Cross hairs
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.3).cgColor)
        context.setLineWidth(1)
        context.move(to: CGPoint(x: center.x, y: center.y - radius + 10))
        context.addLine(to: CGPoint(x: center.x, y: center.y + radius - 10))
        context.move(to: CGPoint(x: center.x - radius + 10, y: center.y))
        context.addLine(to: CGPoint(x: center.x + radius - 10, y: center.y))
        context.strokePath()
        
        // Knob
        let knobCenter = CGPoint(x: center.x + knobOffset.x, y: center.y + knobOffset.y)
        let knobRadius = knobSize / 2
        
        context.setFillColor((isDragging ? NSColor.green : NSColor.white).cgColor)
        context.setShadow(offset: CGSize(width: 0, height: 2), blur: 4, color: NSColor.black.withAlphaComponent(0.5).cgColor)
        context.fillEllipse(in: CGRect(x: knobCenter.x - knobRadius, y: knobCenter.y - knobRadius, width: knobSize, height: knobSize))
    }
    
    override func mouseDown(with event: NSEvent) {
        isDragging = true
        updateKnob(with: event)
    }
    
    override func mouseDragged(with event: NSEvent) {
        updateKnob(with: event)
    }
    
    override func mouseUp(with event: NSEvent) {
        isDragging = false
        knobOffset = .zero
        VirtualControlState.shared.joystickPitch = 0
        VirtualControlState.shared.joystickRoll = 0
        needsDisplay = true
    }
    
    private func updateKnob(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let center = CGPoint(x: bounds.width / 2, y: bounds.height / 2)
        
        var offsetX = location.x - center.x
        var offsetY = location.y - center.y
        
        let maxOffset = (size - knobSize) / 2
        let distance = sqrt(offsetX * offsetX + offsetY * offsetY)
        
        if distance > maxOffset {
            let scale = maxOffset / distance
            offsetX *= scale
            offsetY *= scale
        }
        
        knobOffset = CGPoint(x: offsetX, y: offsetY)
        
        // Normalize to -1...1
        let normalizedX = Float(offsetX / maxOffset)
        let normalizedY = Float(-offsetY / maxOffset)
        
        // Apply sensitivity curve - low sensitivity for precise, smooth control
        let sensitivity: Float = 0.2
        let rollValue = applySensitivityCurve(normalizedX, sensitivity: sensitivity)
        let pitchValue = applySensitivityCurve(normalizedY, sensitivity: sensitivity)
        
        VirtualControlState.shared.joystickRoll = rollValue
        VirtualControlState.shared.joystickPitch = pitchValue
        
        needsDisplay = true
    }
    
    /// Apply an aggressive sensitivity curve — very soft near center, full at edges
    private func applySensitivityCurve(_ input: Float, sensitivity: Float) -> Float {
        let sign: Float = input >= 0 ? 1 : -1
        let absInput = abs(input)
        // Exponent 3.5 gives a large dead zone near center
        let curved = pow(absInput, 3.5) * (1 - sensitivity) + absInput * sensitivity
        // Cap maximum output to 0.7 so full deflection is never too aggressive
        return sign * min(curved, 0.7)
    }
}

struct JoystickView: NSViewRepresentable {
    func makeNSView(context: Context) -> JoystickNSView {
        let view = JoystickNSView()
        view.frame = NSRect(x: 0, y: 0, width: 150, height: 150)
        return view
    }
    
    func updateNSView(_ nsView: JoystickNSView, context: Context) {}
}

// MARK: - NSView-based Throttle

class ThrottleNSView: NSView {
    var width: CGFloat = 60
    var height: CGFloat = 200
    var isDragging = false
    var throttleValue: CGFloat = 0 // 0 to 1
    
    override var isFlipped: Bool { true }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        let trackRect = CGRect(x: 0, y: 0, width: width, height: height)
        
        // Background
        context.setFillColor(NSColor.black.withAlphaComponent(0.4).cgColor)
        let bgPath = NSBezierPath(roundedRect: trackRect, xRadius: 10, yRadius: 10)
        context.addPath(bgPath.cgPath)
        context.fillPath()
        
        // Border
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.5).cgColor)
        context.setLineWidth(2)
        context.addPath(bgPath.cgPath)
        context.strokePath()
        
        // Fill
        let fillHeight = throttleValue * (height - 20)
        let fillRect = CGRect(x: 5, y: height - 10 - fillHeight, width: width - 10, height: fillHeight)
        
        let fillColor: NSColor
        if throttleValue < 0.3 {
            fillColor = NSColor.green.withAlphaComponent(0.6)
        } else if throttleValue < 0.7 {
            fillColor = NSColor.yellow.withAlphaComponent(0.6)
        } else {
            fillColor = NSColor.orange.withAlphaComponent(0.6)
        }
        
        context.setFillColor(fillColor.cgColor)
        let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: 5, yRadius: 5)
        context.addPath(fillPath.cgPath)
        context.fillPath()
        
        // Handle
        let handleY = height - 20 - throttleValue * (height - 40)
        let handleRect = CGRect(x: 5, y: handleY - 15, width: width - 10, height: 30)
        
        context.setFillColor((isDragging ? NSColor.orange : NSColor.gray).cgColor)
        context.setShadow(offset: CGSize(width: 0, height: 2), blur: 4, color: NSColor.black.withAlphaComponent(0.5).cgColor)
        let handlePath = NSBezierPath(roundedRect: handleRect, xRadius: 5, yRadius: 5)
        context.addPath(handlePath.cgPath)
        context.fillPath()
        
        // Percentage text
        context.setShadow(offset: .zero, blur: 0)
        let text = "\(Int(throttleValue * 100))%"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        let textSize = text.size(withAttributes: attributes)
        let textPoint = CGPoint(x: (width - textSize.width) / 2, y: handleY - 15 + (30 - textSize.height) / 2)
        text.draw(at: textPoint, withAttributes: attributes)
    }
    
    override func mouseDown(with event: NSEvent) {
        isDragging = true
        updateThrottle(with: event)
    }
    
    override func mouseDragged(with event: NSEvent) {
        updateThrottle(with: event)
    }
    
    override func mouseUp(with event: NSEvent) {
        isDragging = false
        needsDisplay = true
    }
    
    private func updateThrottle(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let maxTravel = height - 40
        let yOffset = height - location.y - 20
        
        throttleValue = max(0, min(1, yOffset / maxTravel))
        VirtualControlState.shared.throttleValue = Float(throttleValue)
        
        needsDisplay = true
    }
}

struct ThrottleView: NSViewRepresentable {
    func makeNSView(context: Context) -> ThrottleNSView {
        let view = ThrottleNSView()
        view.frame = NSRect(x: 0, y: 0, width: 60, height: 200)
        return view
    }
    
    func updateNSView(_ nsView: ThrottleNSView, context: Context) {}
}

// MARK: - NSView-based Rudder

class RudderNSView: NSView {
    var width: CGFloat = 150
    var height: CGFloat = 40
    var isDragging = false
    var rudderValue: CGFloat = 0 // -1 to 1
    
    override var isFlipped: Bool { true }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        let trackRect = CGRect(x: 0, y: 0, width: width, height: height)
        
        // Background
        context.setFillColor(NSColor.black.withAlphaComponent(0.4).cgColor)
        let bgPath = NSBezierPath(roundedRect: trackRect, xRadius: 8, yRadius: 8)
        context.addPath(bgPath.cgPath)
        context.fillPath()
        
        // Border
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.5).cgColor)
        context.setLineWidth(2)
        context.addPath(bgPath.cgPath)
        context.strokePath()
        
        // Center line
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.3).cgColor)
        context.setLineWidth(2)
        context.move(to: CGPoint(x: width / 2, y: 5))
        context.addLine(to: CGPoint(x: width / 2, y: height - 5))
        context.strokePath()
        
        // L and R labels
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .bold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.5)
        ]
        "L".draw(at: CGPoint(x: 8, y: (height - 12) / 2), withAttributes: labelAttrs)
        "R".draw(at: CGPoint(x: width - 16, y: (height - 12) / 2), withAttributes: labelAttrs)
        
        // Handle
        let handleX = width / 2 + rudderValue * (width - 50) / 2 - 20
        let handleRect = CGRect(x: handleX, y: 5, width: 40, height: height - 10)
        
        context.setFillColor((isDragging ? NSColor.cyan : NSColor.gray).cgColor)
        context.setShadow(offset: CGSize(width: 0, height: 2), blur: 3, color: NSColor.black.withAlphaComponent(0.5).cgColor)
        let handlePath = NSBezierPath(roundedRect: handleRect, xRadius: 5, yRadius: 5)
        context.addPath(handlePath.cgPath)
        context.fillPath()
    }
    
    override func mouseDown(with event: NSEvent) {
        isDragging = true
        updateRudder(with: event)
    }
    
    override func mouseDragged(with event: NSEvent) {
        updateRudder(with: event)
    }
    
    override func mouseUp(with event: NSEvent) {
        isDragging = false
        rudderValue = 0
        VirtualControlState.shared.rudderValue = 0
        needsDisplay = true
    }
    
    private func updateRudder(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let maxTravel = (width - 50) / 2
        let xOffset = location.x - width / 2
        
        rudderValue = max(-1, min(1, xOffset / maxTravel))
        
        // Apply sensitivity curve for smoother control
        let normalized = Float(rudderValue)
        let sensitivity: Float = 0.6
        let sign: Float = normalized >= 0 ? 1 : -1
        let absInput = abs(normalized)
        let curved = pow(absInput, 2.5) * (1 - sensitivity) + absInput * sensitivity
        VirtualControlState.shared.rudderValue = sign * curved
        
        needsDisplay = true
    }
}

struct RudderView: NSViewRepresentable {
    func makeNSView(context: Context) -> RudderNSView {
        let view = RudderNSView()
        view.frame = NSRect(x: 0, y: 0, width: 150, height: 40)
        return view
    }
    
    func updateNSView(_ nsView: RudderNSView, context: Context) {}
}

// MARK: - NSBezierPath CGPath extension

extension NSBezierPath {
    var cgPath: CGPath {
        let path = CGMutablePath()
        var points = [CGPoint](repeating: .zero, count: 3)
        
        for i in 0..<elementCount {
            let type = element(at: i, associatedPoints: &points)
            switch type {
            case .moveTo:
                path.move(to: points[0])
            case .lineTo:
                path.addLine(to: points[0])
            case .curveTo:
                path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .closePath:
                path.closeSubpath()
            case .cubicCurveTo:
                path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .quadraticCurveTo:
                path.addQuadCurve(to: points[1], control: points[0])
            @unknown default:
                break
            }
        }
        return path
    }
}

// MARK: - Control Position Display (SwiftUI - read only)

struct ControlPositionDisplay: View {
    let elevator: Float
    let aileron: Float
    let rudder: Float
    let throttle: Float
    let flaps: Float
    
    var body: some View {
        VStack(spacing: 8) {
            Text("CONTROLES")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
            
            HStack(spacing: 15) {
                StickPositionView(x: aileron, y: elevator)
                
                VStack(spacing: 4) {
                    VerticalControlBar(label: "GAZ", value: throttle, color: .green)
                    VerticalControlBar(label: "DIR", value: (rudder + 1) / 2, color: .cyan)
                    VerticalControlBar(label: "VLT", value: flaps, color: .orange)
                }
            }
        }
        .padding(10)
        .background(Color.black.opacity(0.5))
        .cornerRadius(10)
    }
}

struct StickPositionView: View {
    let x: Float
    let y: Float
    let size: CGFloat = 60
    
    var body: some View {
        Canvas { context, canvasSize in
            // Background
            context.fill(Path(CGRect(origin: .zero, size: canvasSize)), with: .color(.gray.opacity(0.3)))
            
            // Grid
            var gridPath = Path()
            gridPath.move(to: CGPoint(x: canvasSize.width/2, y: 0))
            gridPath.addLine(to: CGPoint(x: canvasSize.width/2, y: canvasSize.height))
            gridPath.move(to: CGPoint(x: 0, y: canvasSize.height/2))
            gridPath.addLine(to: CGPoint(x: canvasSize.width, y: canvasSize.height/2))
            context.stroke(gridPath, with: .color(.white.opacity(0.3)), lineWidth: 1)
            
            // Position dot
            let dotX = canvasSize.width/2 + CGFloat(x) * (canvasSize.width/2 - 5)
            let dotY = canvasSize.height/2 - CGFloat(y) * (canvasSize.height/2 - 5)
            let dotRect = CGRect(x: dotX - 5, y: dotY - 5, width: 10, height: 10)
            context.fill(Path(ellipseIn: dotRect), with: .color(.yellow))
        }
        .frame(width: size, height: size)
    }
}

struct VerticalControlBar: View {
    let label: String
    let value: Float
    let color: Color
    
    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
            
            ZStack(alignment: .bottom) {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 15, height: 40)
                
                Rectangle()
                    .fill(color)
                    .frame(width: 15, height: CGFloat(max(0, min(1, value))) * 40)
            }
            .cornerRadius(3)
        }
    }
}

// MARK: - Main Overlay

struct VirtualControlsOverlay: View {
    @ObservedObject var flightData: FlightDataModel
    
    var body: some View {
        ZStack {
            // Control position display (top right)
            VStack {
                HStack {
                    Spacer()
                    ControlPositionDisplay(
                        elevator: flightData.elevator,
                        aileron: flightData.aileron,
                        rudder: flightData.rudder,
                        throttle: flightData.throttle,
                        flaps: flightData.flaps
                    )
                }
                Spacer()
            }
            .padding(.top, 80)
            .padding(.trailing, 20)
            
            // Virtual controls using NSView
            VStack {
                Spacer()
                
                HStack(alignment: .bottom, spacing: 30) {
                    // Throttle
                    VStack {
                        Text("GAZ")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.6))
                        ThrottleView()
                            .frame(width: 60, height: 200)
                    }
                    
                    Spacer()
                    
                    // Joystick and Rudder
                    VStack(spacing: 25) {
                        VStack {
                            JoystickView()
                                .frame(width: 150, height: 150)
                            Text("JOYSTICK")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.6))
                        }
                        
                        VStack {
                            RudderView()
                                .frame(width: 150, height: 40)
                            Text("DIRECTION")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 40)
            }
        }
    }
}
