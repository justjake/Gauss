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
        ZStack(alignment: .top) {
            ScrollView([.vertical]) {
                VStack(spacing: 0) {
                    ForEach($document.prompts) { $prompt in
                        PromptView(
                            prompt: $prompt,
                            images: $document.images,
                            document: $document
                        )
                            .frame(maxWidth: 980)
                            .padding([.horizontal, .bottom])
                    }
                    Button("Add Prompt") {
                        let prompt = GaussPrompt()
                        document.prompts.append(prompt)
                    }
                }.padding([.vertical])
                    .frame(alignment: .top)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)

            
            VStack {
                HStack {
                    Spacer()
                    KernelStatusView().padding().opacity(0.5)
                }
                Spacer()
            }
        }.background(Rectangle().fill(.background))
    }
}

struct ContentView_Previews: PreviewProvider {
    static var kernel = GaussKernel()
    static var document: GaussDocument {
        var prompt = GaussPrompt()
        prompt.text = "A high tech solarpunk utopia in the Amazon rainforest"
        
        var negativePrompt = GaussPrompt()
        negativePrompt.text = "A cyberpunk street samurai weilding an energy katana, by wopr, volumetric light, hyper realistic"

        return GaussDocument(prompts: [prompt, negativePrompt])
    }
    
    static var previews: some View {
        ContentView(document: .constant(document)).environmentObject(kernel)
    }
}
