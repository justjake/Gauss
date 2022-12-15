//
//  GaussApp.swift
//  Gauss
//
//  Created by Jake Teton-Landis on 12/3/22.
//

import SwiftUI

@main
struct GaussApp: App {
    private let kernel = GaussKernel()
    
    init() {
        kernel.preloadPipeline(GaussModel.Default)
    }
    
    var body: some Scene {
        DocumentGroup(newDocument: GaussDocument()) { file in
            ContentView(document: file.$document).environmentObject(kernel)
        }
    }
}
