//
//  PromptView.swift
//  Gauss
//
//  Created by Jake Teton-Landis on 12/3/22.
//

import SwiftUI

struct PromptView: View {
    @Binding var prompt: GaussPrompt
    @Binding var images: GaussImages
    @Binding var document: GaussDocument
    @EnvironmentObject private var kernel: GaussKernel
        
    var body: some View {
        VStack {
            /// Display the prompt
            Group {
                HStack(alignment: .top, spacing: 20) {
                    Text(prompt.text).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                    deleteButton
                }.padding([.horizontal, .top])
            
                PromptSettingsView(prompt: $prompt).disabled(true)
            }
            
            /// Actions
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: 0) {
                    BottomBarButtonLabel {
                        HStack(spacing: 12) {
                            Label("Generate again", systemImage: "repeat").padding(.trailing, 6)
                                
                            Button(action: { generateImage(1) }) {
                                Label("1 image", systemImage: "1.square.fill").labelStyle(.iconOnly).imageScale(.large)
                            }.help("Generate 1 image with this prompt")
                                
                            Button(action: { generateImage(4) }) {
                                Label("4 image", systemImage: "4.square.fill").labelStyle(.iconOnly).imageScale(.large)
                            }.help("Generate 4 images with this prompt")
                                
                            Button(action: { generateImage(9) }) {
                                Label("9 images", systemImage: "9.square.fill").labelStyle(.iconOnly).imageScale(.large)
                            }.help("Generate 9 images with this prompt")
                        }
                    }
                    
                    Divider()
                    
                    Button {
                        self.remix()
                    } label: {
                        BottomBarButtonLabel {
                            Label("Remix", systemImage: "shuffle")
                                .labelStyle(.titleAndIcon)
                                .help("Edit this prompt in the composer")
                        }
                    }
                }.fixedSize(horizontal: false, vertical: true)
                    .buttonStyle(.borderless)
                
                Divider().opacity(0)
            }
        }.background(.quaternary, in: GaussStyle.rectLarge).frame(maxWidth: 600)
    }
            
    var deleteButton: some View {
        Button {
            self.delete()
        } label: {
            Image(systemName: "xmark")
        }.help(Text("Delete prompt and results"))
            .buttonStyle(.borderless)
            .contentShape(Circle())
    }

    func generateImage(_ count: Int) {
        _ = kernel.startGenerateImageJob(forPrompt: prompt, count: count).onSuccess { images in
            saveResults(images)
        }
    }
    
    func remix() {
        document.composer = prompt.clone()
    }
    
    func saveResults(_ images: [NSImage?]) {
        var imageRefs: [GaussImageRef] = []
        for image in images {
            var ref = GaussImageRef()
            guard let nsImage = image else {
                ref.unsafe = true
                imageRefs.append(ref)
                continue
            }
            self.images.addImage(ref: ref, nsImage)
            imageRefs.append(ref)
        }
        let result = GaussResult(promptId: prompt.id, images: imageRefs)
        prompt.results.append(result)
    }
        
    func delete() {
        let ownPrompt = prompt
        document.prompts.removeAll(where: { $0.id == ownPrompt.id })
        document.images.removePrompt(ownPrompt)
    }
}

struct PromptSettingsView: View {
    @Binding var prompt: GaussPrompt
    @EnvironmentObject var kernel: GaussKernel
    @ObservedObject var assets = AssetManager.inst
    
    var body: some View {
        VStack {
            HStack(spacing: 20) {
                stepsSlider
            }.padding(.horizontal)
            
            HStack(spacing: 20) {
                guidanceSlider
                modelPicker
            }.padding(.horizontal)
        }
    }
    
    var modelPicker: some View {
        Picker("Model", selection: $prompt.model) {
            ForEach(GaussModel.allCases, id: \.self) { model in
                Text(model.shortDescription)
                    .tag(model)
                    .help(Text(model.description))
                    .disabled(assets.locateModel(model: model) == nil)
            }
        }
        .fixedSize()
        .onChange(of: prompt.model) { _ in
            kernel.preloadPipeline(prompt.model)
        }
    }
    
    var safetyToggle: some View {
        Toggle("Safe", isOn: $prompt.safety)
            .toggleStyle(.switch)
            .help(Text("If enabled, try to hide images that contain unsafe content. Often removes progress results."))
    }
    
    var stepsSlider: some View {
        Slider(value: $prompt.steps, in: 1...75, step: 5) {} minimumValueLabel: {
            Text("Speed")
        } maximumValueLabel: {
            Text("Quality")
        }.help(Text("Number of diffusion steps to perform"))
    }
    
    var guidanceSlider: some View {
        Slider(value: $prompt.guidance, in: 0...20) {} minimumValueLabel: {
            Text("Creative")
        } maximumValueLabel: {
            Text("Predictable")
        }.help(Text("Guidance factor; set to zero for random output"))
    }
}

struct PromptInputView: View {
    @Binding var text: String
    @Binding var count: Int
    var onSubmit: () -> Void
    
    private let submitButtonSize: CGFloat = 32
    private let inputPadding: CGFloat = 4
    
    var body: some View {
        let rect = RoundedRectangle(cornerRadius: (submitButtonSize + 1) / 2, style: .circular)
        let stroke = rect.strokeBorder(.tertiary)
        HStack(alignment: .bottom) {
            TextField(
                "Prompt",
                text: $text,
                axis: .vertical
            )
            .onSubmit(onSubmit)
            .textFieldStyle(.plain)
            .navigationTitle("Prompt")
            .fixedSize(horizontal: false, vertical: true)
            .padding([.top, .bottom], 4)
            
            accessory.frame(alignment: .bottomTrailing)
        }.padding(EdgeInsets(top: inputPadding, leading: submitButtonSize / 3, bottom: inputPadding, trailing: 2))
            .overlay(stroke)
            .frame(alignment: .bottom)
    }
    
    var accessory: some View {
        HStack(spacing: 3) {
            Picker("Batch size", selection: $count) {
                Text("1").tag(1)
                Text("4").tag(4)
                Text("9").tag(9)
            }.fixedSize().labelsHidden()
            
            Button(action: onSubmit) {
                Image(systemName: "brain.head.profile")
            }
            .padding(2)
            .buttonStyle(.plain)
            .background(.blue, in: Circle())
            .contentShape(Circle())
        }.padding(.trailing, 2)
    }
}

struct PromptView_Previews: PreviewProvider {
    @State static var doc = GaussDocument(prompts: [
        GaussPrompt()
    ])
    @State static var prompt = doc.prompts.first!
    
    static let shortPrompt = "Flamingos wearing plate armor"
    static let longPrompt = "Flamingos wearing plate armor, dancing with owls, dancing with owls, dancing with owls, dancing with owls, dancing with owls, dancing with owls, dancing with owls, dancing with owls!"
    
    static var previews: some View {
        PromptView(prompt: $prompt, images: .constant([:]), document: $doc).padding()
        
        PromptView(prompt: .constant(GaussPrompt(
            results: [GaussResult(promptId: UUID(), images: [GaussImageRef()])], text: longPrompt
        )), images: .constant([:]), document: $doc).padding().previewDisplayName("Prompt with result")

        PromptView(prompt: .constant(GaussPrompt(text: longPrompt)), images: .constant([:]), document: $doc).padding().previewDisplayName("Long prompt")
        
        PromptInputView(text: .constant(shortPrompt), count: .constant(4), onSubmit: {}).previewDisplayName("Input")
        
        PromptInputView(text: .constant(longPrompt), count: .constant(4), onSubmit: {}).previewDisplayName("Long input")
    }
}

struct BottomBarButtonLabel<Content: View>: View {
    var content: () -> Content
    
    var body: some View {
        VStack {
            Divider().opacity(0)
            HStack(spacing: 0) {
                Spacer()
                content()
                Spacer()
            }
            Divider().opacity(0)
        }.contentShape(Rectangle())
    }
}
