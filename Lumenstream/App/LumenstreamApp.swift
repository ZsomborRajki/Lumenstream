//
//  LumenstreamApp.swift
//  Lumenstream
//
//  Created by Zsombor Rajki on 2026. 10. 17..
//

import LumenstreamData
import SwiftUI

@main
struct LumenstreamApp: App {
    @State private var model = LumenstreamModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.sceneDidBecomeActive() }
        }
        .lumenstreamDataContainer()
    }
}
