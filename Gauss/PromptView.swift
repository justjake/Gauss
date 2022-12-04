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
    @Binding var document: GaussDocument
    @State private var jobs: [GenerateImageJob] = []
    @EnvironmentObject private var kernel: GaussKernel
    @FocusState private var focused
    
    var locked: Bool {
        return prompt.results.count > 0 || jobs.count > 0
    }
    
    var hasResults: Bool {
        return (jobs.count + prompt.results.count) > 0
    }
    
    var showAddButton: Bool {
        return document.prompts.last?.id == prompt.id
    }
    
    var shouldFocusOnReveal: Bool {
        let newestPrompt = document.prompts.max(by: { $0.createdAt > $1.createdAt })
        return newestPrompt?.id == prompt.id
    }
    
    var body: some View {
        VStack {
            HStack {
                card
                deleteButton
            }
            if hasResults {
                results
            }
            if showAddButton {
                AddPromptButton(document: $document)
                    .frame(maxWidth: 650, alignment: .leading)
                    .padding()
            }
        }
    }
    
    var card: some View {
        Group {
        VStack {
            /// Section for editing the prompt
            Group {
                TextField(
                    "Prompt",
                    text: $prompt.text,
                    axis: .vertical
                )
                .onSubmit {
                    generateImage()
                }
                .focused($focused)
                .task {
                    if shouldFocusOnReveal {
                        self.focused = true
                    }
                }
                .textFieldStyle(.plain)
                .font(Font.headline)
                .navigationTitle("Prompt")
                .padding([.horizontal, .top])
                
                HStack(spacing: 20) {
                    Slider(value: $prompt.steps, in: 1...75, step: 5) {
                        Text("Steps")
                    } minimumValueLabel: {
                        Text("1")
                    } maximumValueLabel: {
                        Text("75")
                    }
                    
                    Toggle("Safe", isOn: $prompt.safety)
                        .toggleStyle(.switch)
                }.padding(.horizontal)
                
            }.disabled(locked)
            
            /// Section for generating & reviewing images
            VStack(spacing: 0) {
                Divider()
//                Rectangle().fill(.separator).frame(height: 1)
                HStack(spacing: 0) {
                    (Button {
                        self.generateImage()
                    } label: {
                        VStack{
                            Divider().opacity(0)
                            HStack(spacing: 0) {
                                Spacer()
                                Text("Generate")
                                Spacer()
                            }
                            Divider().opacity(0)
                        }.contentShape(Rectangle())
                    }).overlay(Divider(), alignment: .trailing)
                    
                    Button {
                        self.copyPrompt()
                    } label: {
                        VStack{
                            Divider().opacity(0)
                            HStack {
                                Spacer()
                                Text("Duplicate")
                                Spacer()
                            }
                            Divider().opacity(0)
                        }.contentShape(Rectangle())

                    }
                }.buttonStyle(.borderless)
                Divider().opacity(0)
                
                
                if (hasResults) {
                }
            }
        }
        }.background(background).frame(maxWidth: 600)
    }
    
    var results: some View {
        ScrollView(.horizontal) {
            LazyHStack {
                ForEach($jobs) { $job in
                    GaussProgressView(job: job)
                }
                
                ForEach($prompt.results) { $result in
                    ResultView(result: $result, images: $images)
                }
            }
        }
    }
    
    var deleteButton: some View {
        Button {
            self.delete()
        } label: {
            Image(systemName: "xmark").imageScale(.large)
        }.padding()
            .buttonStyle(.borderless)
            .contentShape(Circle())
    }

    
    var background: some View {
        let gradient = Gradient(colors: [
            Color(nsColor: NSColor.windowBackgroundColor),
            Color(nsColor: NSColor.underPageBackgroundColor),
        ])
        
        let rect = RoundedRectangle(cornerRadius: 14, style: .continuous)
        let stroke = rect.strokeBorder(.separator)
        let background = rect
            .fill(Color(nsColor: NSColor.windowBackgroundColor))
//            .fill(.linearGradient(gradient, startPoint: .top, endPoint: .bottom))
            .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 2)
        return background.overlay(stroke)
    }
    
    func generateImage() {
        let job = kernel.startGenerateImageJob(forPrompt: prompt) { results, job in
            saveResults(results)
            jobs.removeAll(where: { $0 === job })
        }
        jobs.append(job)
    }
    
    func copyPrompt() {
        var copy = self.prompt
        let blank = GaussPrompt()
        
        copy.id = blank.id
        copy.createdAt = blank.createdAt
        copy.results = blank.results
        copy.favorite = blank.favorite
        copy.hidden = blank.hidden
        
        let position = self.document.prompts.firstIndex(where: { $0.id == self.prompt.id })
        self.document.prompts.insert(copy, at: position ?? 0 + 1)
    }
    
    func saveResults(_ images: [CGImage?]) {
        let saveable = renderableImageArray(from: images)
        if saveable.count == 0 {
            return
        }
        let first = saveable[0]
        let imageId = UUID()
        self.images[imageId.uuidString] = first
        let result = GaussResult(promptId: prompt.id, imageId: imageId)
        prompt.results.append(result)
    }
    
    func delete() {
        document.prompts.removeAll(where: { $0.id == prompt.id })
    }
}

struct PromptView_Previews: PreviewProvider {
    @State static var doc = GaussDocument(prompts: [
        GaussPrompt()
    ])
    @State static var prompt = doc.prompts.first!
    
    static var previews: some View {
        PromptView(prompt: $prompt, images: .constant([:]), document: $doc).padding()
        
    }
}
