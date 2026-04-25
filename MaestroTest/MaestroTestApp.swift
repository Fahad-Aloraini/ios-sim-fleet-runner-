//
//  MaestroTestApp.swift
//  MaestroTest
//

import SwiftUI
import SwiftData

@main
struct MaestroTestApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: Counter.self)
    }
}
