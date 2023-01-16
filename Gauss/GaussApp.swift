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
    private let kernel = GaussKernel.inst

    static let MODELS_WINDOW = "models"
    static let TASKS_WINDOW = "tasks"

    var body: some Scene {
        DocumentGroup(newDocument: GaussDocument()) { file in
            ContentView(document: file.$document).environmentObject(kernel)
        }

        Window("Models", id: GaussApp.MODELS_WINDOW) {
            SplashView().padding()
        }

        Window("Tasks", id: GaussApp.TASKS_WINDOW) {
            ObservableTasksList()
        }
    }
}
