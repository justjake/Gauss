//
//  GaussApp.swift
//  Gauss
//
//  Created by Jake Teton-Landis on 12/3/22.
//

import SwiftUI

@main
struct GaussApp: App {
    @ObservedObject private var assets = AssetManager.inst
    private let kernel = GaussKernel()

    var body: some Scene {
        DocumentGroup(newDocument: GaussDocument()) { file in
            ContentView(document: file.$document).environmentObject(kernel)
        }

        Settings {
            AppSettingsView()
        }
    }
}
