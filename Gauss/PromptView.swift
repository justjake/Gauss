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


struct PromptView: View {
    @Binding var prompt: GaussPrompt
    @Binding var images: GaussImages
    @State var jobs: [GenerateImageJob] = []
    
    var body: some View {
        Form {
            Section(header: Text("Prompt")) {
                TextEditor(
                    text: $prompt.text
                ).textFieldStyle(.roundedBorder)
                    .navigationTitle("Prompt")
            }
            
            Section() {
                Slider(value: $prompt.steps, in: 1...75, step: 1) {
                    Text("Steps")
                } minimumValueLabel: {
                    Text("1")
                } maximumValueLabel: {
                    Text("75")
                }
                Text(prompt.steps.formatted()).multilineTextAlignment(.center)
                
                Toggle("Safe", isOn: $prompt.safety)
            }
            
            Section() {
                Button("Generate +", action: {
                    self.generateImage()
                }).buttonStyle(.borderedProminent)
                
                ScrollView(.horizontal) {
                    LazyHStack {
                        ForEach($jobs) { $job in
                            ProgressView(job: job)
                        }
                        
                        ForEach($prompt.results) { $result in
                            ResultView(result: $result, images: $images)
                        }
                    }
                }
            }
        }
    }
    
    func generateImage() {
        let kernel = GaussKernel()
        let job = kernel.generate(forPrompt: prompt)
        jobs.append(job)
    }
}

struct PromptView_Previews: PreviewProvider {
    @State static var prompt = GaussPrompt()
    
    static var previews: some View {
        PromptView(prompt: $prompt, images:  .constant([:]))
            .previewLayout(.sizeThatFits)
    }
}
