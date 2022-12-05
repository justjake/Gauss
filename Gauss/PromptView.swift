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
    var selected: Bool = false
    var canGenerate: Bool = true
    var canDuplicate: Bool = true
    @State private var count = 1
    @EnvironmentObject private var kernel: GaussKernel
    @FocusState private var focused
    
    var jobs: [GenerateImageJob] {
        kernel.getJobs(for: prompt)
    }
    
    var locked: Bool {
        return prompt.results.count > 0 || jobs.count > 0
    }
    
    var canDelete: Bool {
        return locked
    }
    
    var hasResults: Bool {
        return (jobs.count + prompt.results.count) > 0
    }
        
    var shouldFocusOnReveal: Bool {
        let newestPrompt = document.prompts.max(by: { $0.createdAt < $1.createdAt })
        return newestPrompt?.id == prompt.id
    }
    
    var body: some View {
        VStack {
            HStack {
                Spacer()
                card.padding()
            }
            if hasResults {
                results
            }
        }
    }
    
    var card: some View {
        Group {
        VStack {
            /// Section for editing the prompt
            Group {
                HStack(alignment: .top, spacing: 20) {
                    if locked {
                        Text(prompt.text).frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        promptTextField.disabled(locked)
                    }
                    if canDelete {
                        deleteButton
                    }
                }.padding([.horizontal, .top])
                
                PromptSettingsView(prompt: $prompt).disabled(locked)
            }
            
            /// Section for generating & reviewing images
            if locked {
                VStack(spacing: 0) {
                    Divider()
                    HStack(spacing: 0) {
                        if canGenerate {
                            BottomBarButtonLabel {
                                HStack(spacing: 12) {
                                    Label("Generate", systemImage: "brain").padding(.trailing, 6)
                                    
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
                        }
                        
                        if canGenerate && canDuplicate {
                            Divider()
                        }
                        
                        if canDuplicate {
                            Button {
                                self.remix()
                                self.insertDuplicateAfterSelf()
                            } label: {
                                BottomBarButtonLabel {
                                    Label("Remix", systemImage: "shuffle")
                                        .labelStyle(.titleAndIcon)
                                        .help("Edit this prompt in the composer")
                                }
                            }
                        }
                    }.fixedSize(horizontal: false, vertical: true)
                        .buttonStyle(.borderless)
                    Divider().opacity(0)
                }
            } else {
                Rectangle().frame(height: 8).foregroundColor(.clear)
            }
        }
        }.background(.quaternary, in: GaussStyle.rectLarge).frame(maxWidth: 600)
    }
    
    var promptTextField: some View {
        PromptInputView(text: $prompt.text, count: $count) {
            generateImage(count)
        }
    }
    
    
    
    var results: some View {
        ScrollViewReader { scroller in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 1) {
                    ForEach($prompt.results) { $result in
                        ResultView(result: $result, images: $images)
                            .id(result.id)
                            .aspectRatio(CGSize(width: prompt.width, height: prompt.height), contentMode: .fit)
                            .frame(height: .resultSize)
                    }
                    
                    ForEach(jobs) { job in
                        GaussProgressView(job: job)
                            .id(job.id)
                            .aspectRatio(CGSize(width: prompt.width, height: prompt.height), contentMode: .fit)
                            .frame(height: .resultSize)
                    }
                }
            }
        }
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
        _ = kernel.startGenerateImageJob(forPrompt: prompt, count: count) { results, job in
            if !job.cancelled {
                saveResults(results)
            }
            kernel.jobs.removeValue(forKey: job.id)
        }
    }
    
    func insertDuplicateAfterSelf() {
        let copy = self.prompt.clone()
        
        let position = self.document.prompts.firstIndex(where: { $0.id == self.prompt.id })
        withAnimation(.default) {
            self.document.prompts.insert(copy, at: (position ?? 0) + 1)
        }
    }
    
    func remix() {
        self.document.composer = self.prompt.clone()
    }
    
    func saveResults(_ images: [CGImage?]) {
        var imageRefs: [GaussImageRef] = []
        for image in images {
            var ref = GaussImageRef()
            guard let nsImage = image?.asNSImage() else {
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
        if (document.prompts.count == 1) {
            document.prompts.append(GaussPrompt())
        }
        
        let ownPrompt = self.prompt
        document.prompts.removeAll(where: { $0.id == ownPrompt.id })
        document.images.removePrompt(ownPrompt)
    }
}

struct PromptSettingsView: View {
    @Binding var prompt: GaussPrompt
    @EnvironmentObject var kernel: GaussKernel
    
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
            Text("SD 2.0").tag(GaussModel.sd2).help(Text("Stable Diffusion 2.0 Base"))
            Text("SD 1.5").tag(GaussModel.sd1_5).help(Text("Stable Diffusion 1.5"))
            Text("SD 1.4").tag(GaussModel.sd1_4).help(Text("Stable Diffusion 1.4"))
            // TODO: support custom models
        }
        .fixedSize()
            .onChange(of: prompt.model) { model in
                kernel.preloadPipeline(prompt.model)
            }
    }
    
    var safetyToggle: some View {
        Toggle("Safe", isOn: $prompt.safety)
            .toggleStyle(.switch)
            .help(Text("If enabled, try to hide images that contain unsafe content. Often removes progress results."))
    }
    
    var stepsSlider: some View {
        Slider(value: $prompt.steps, in: 1...75, step: 5) {
        } minimumValueLabel: {
            Text("Speed")
        } maximumValueLabel: {
            Text("Quality")
        }.help(Text("Number of diffusion steps to perform"))
    }
    
    var guidanceSlider: some View {
        Slider(value: $prompt.guidance, in: 0...20) {
        } minimumValueLabel: {
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
        VStack{
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
