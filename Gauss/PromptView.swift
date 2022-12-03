//
//  PromptView.swift
//  Gauss
//
//  Created by Jake Teton-Landis on 12/3/22.
//

import SwiftUI

//var width = 512
//var height = 512
//var guidance = 5
//var steps = 10
//var seed = GaussSeed.random

struct DoubleProxy {
    @Binding var int: Int

    
}

struct PromptView: View {
    @Binding var prompt: GaussPrompt
    @Binding var images: GaussImages
    
    var body: some View {
        Form {
            Section(header: Text("Prompt")) {
                TextEditor(
                    text: $prompt.text
                ).textFieldStyle(.roundedBorder)
                    .navigationTitle("Prompt")
            }
                            
            Section(header: Text("Negative Prompt")) {
                Text("AI will try to avoid this").foregroundColor(.secondary)
                TextEditor(
                    text: $prompt.negativeText
                ).textFieldStyle(.roundedBorder)
                    .navigationTitle("Prompt")

            }
            
            Section() {
                Slider(value: $prompt.guidance, in: 1...20, step: 1
                ) {
                    Text("Guidance")
                } minimumValueLabel: {
                    Text("1")
                } maximumValueLabel: {
                    Text("20")
                }
                Text(prompt.guidance.formatted())
                    .multilineTextAlignment(.center)
                    .badge(/*@START_MENU_TOKEN@*/"Label"/*@END_MENU_TOKEN@*/)
                
                Slider(value: $prompt.steps, in: 1...75, step: 1) {
                    Text("Steps")
                } minimumValueLabel: {
                    Text("1")
                } maximumValueLabel: {
                    Text("75")
                }
                Text(prompt.steps.formatted()).multilineTextAlignment(.center)
            }
            
            Section() {
                Button("Generate +", action: { print("clicked")
                }).buttonStyle(.borderedProminent)
                
                ScrollView(.horizontal) {
                    LazyHStack {
                        ForEach($prompt.results) { $result in
                            ResultView(result: $result, images: $images)
                        }
                    }
                }
            }
        }.padding(.horizontal)
    }
}

struct PromptView_Previews: PreviewProvider {
    @State static var prompt = GaussPrompt()
    
    static var previews: some View {
        PromptView(prompt: $prompt, images:  .constant([:]))
            .previewLayout(.sizeThatFits)
    }
}
