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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .preferredColorScheme(.dark)
        }
        .lumenstreamDataContainer()
    }
}
