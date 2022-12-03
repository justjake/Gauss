//
//  ContentView.swift
//  Gauss
//
//  Created by Jake Teton-Landis on 12/3/22.
//

import SwiftUI

struct ContentView: View {
    @Binding var document: GaussDocument

    var body: some View {
        VStack {
            List {
                ForEach($document.prompts) { $prompt in
                    PromptView(prompt: $prompt, images: $document.images)
                }
            }
            Button("New Prompt") {
                let prompt = GaussPrompt()
                document.prompts.append(prompt)
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var document: GaussDocument {
        var prompt = GaussPrompt()
        prompt.text = "A high tech solarpunk utopia in the Amazon rainforest"
        
        var negativePrompt = GaussPrompt()
        negativePrompt.text = "A cyberpunk street samurai weilding an energy katana, by wopr, volumetric light, hyper realistic"
        negativePrompt.negativeText = "multiple arms, watermark, signature"

        return GaussDocument(prompts: [prompt, negativePrompt])
    }
    
    static var previews: some View {
        ContentView(document: .constant(document))
    }
}
