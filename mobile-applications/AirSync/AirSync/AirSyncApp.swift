//
//  AirSyncApp.swift
//  AirSync
//
//  Created by Jack Darnell on 11/27/25.
//

import SwiftUI

@main
@MainActor
struct AirSyncApp: App {
    private var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    var body: some Scene {
        WindowGroup {
            if isRunningTests {
                CalibrationView(session: .previewSession())
            } else {
                ContentView()
            }
        }
    }
}
