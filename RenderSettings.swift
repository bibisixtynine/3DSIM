//
//  RenderSettings.swift
//  3DSIM
//
//  Render settings with persistence — toggle scene elements for performance
//

import SwiftUI
import Combine

/// Observable render settings persisted via UserDefaults
class RenderSettings: ObservableObject {
    static let shared = RenderSettings()
    
    @AppStorage("render.trees")       var showTrees: Bool = true       { willSet { objectWillChange.send() } }
    @AppStorage("render.houses")      var showHouses: Bool = true      { willSet { objectWillChange.send() } }
    @AppStorage("render.roads")       var showRoadDetails: Bool = true { willSet { objectWillChange.send() } }
    @AppStorage("render.aiAircraft")  var showAIAircraft: Bool = true  { willSet { objectWillChange.send() } }
    @AppStorage("render.helicopters") var showHelicopters: Bool = true { willSet { objectWillChange.send() } }
    @AppStorage("render.balloons")    var showBalloons: Bool = true    { willSet { objectWillChange.send() } }
    @AppStorage("render.birds")       var showBirds: Bool = true       { willSet { objectWillChange.send() } }
    @AppStorage("render.clouds")      var showClouds: Bool = true      { willSet { objectWillChange.send() } }
    @AppStorage("render.weather")     var showWeather: Bool = true     { willSet { objectWillChange.send() } }
    @AppStorage("render.water")       var showWater: Bool = true       { willSet { objectWillChange.send() } }
}
