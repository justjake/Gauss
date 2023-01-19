//
//  GaussApp.swift
//  Gauss
//
//  Created by Jake Teton-Landis on 12/3/22.
//

import SwiftUI

extension CGFloat {
    static let AppMinWidth = 375.0
}

@main
struct GaussApp: App {
    @ObservedObject private var assets = AssetManager.inst
    private let kernel = GaussKernel.inst

    static let MODELS_WINDOW = "models"
    static let TASKS_WINDOW = "tasks"

    var body: some Scene {
        DocumentGroup(newDocument: GaussDocument()) { file in
            ContentView(document: file.$document)
                .environmentObject(kernel)
                .frame(minWidth: .AppMinWidth, minHeight: 400)
        }.defaultSize(width: 750, height: 850)

        Window("Models", id: GaussApp.MODELS_WINDOW) {
            SplashView().padding().frame(minWidth: .AppMinWidth)
        }

        Window("Tasks", id: GaussApp.TASKS_WINDOW) {
            ObservableTasksList().frame(minWidth: .AppMinWidth)
        }
        .defaultSize(width: .AppMinWidth, height: .AppMinWidth * 2)
        .defaultPosition(.topTrailing)
    }
}
