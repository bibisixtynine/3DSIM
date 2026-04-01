//
//  _DSIMApp.swift
//  3DSIM
//
//  Created by Jérôme Binachon on 01/04/2026.
//

import SwiftUI

@main
struct _DSIMApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
