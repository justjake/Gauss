//
//  PromptComposer.swift
//  Gauss
//
//  Created by Jake Teton-Landis on 12/5/22.
//

import SwiftUI

struct PromptComposer: View {
    @Binding var document: GaussDocument
    @State var count = 1
    @EnvironmentObject var kernel: GaussKernel
    var submitAction: () -> Void

    var body: some View {
        VStack {
            PromptInputView(text: $document.composer.text, count: $count, onSubmit: onSubmit)
                .task {
                    let model = document.composer.model
                    kernel.preloadPipeline(model)
                }
            PromptSettingsView(prompt: $document.composer)
        }.padding().background(.regularMaterial)
    }

    func onSubmit() {
        let prompt = document.composer.clone()
        document.prompts.append(prompt)
        submitAction()
        let job = kernel.startGenerateImageJob(forPrompt: prompt, count: count).onSuccess { images in
            saveResults(promptId: prompt.id, images: images)
        }
        
        print("Start job \(job.id) for promtp \(job.prompt.id) <==> \(prompt.id)")
    }

    func saveResults(promptId: UUID, images: [NSImage?]) {
        guard let promptIndex = document.prompts.firstIndex(where: { $0.id == promptId }) else {
            return
        }
        var prompt = document.prompts[promptIndex]
        var imageRefs: [GaussImageRef] = []
        for image in images {
            var ref = GaussImageRef()
            guard let nsImage = image else {
                ref.unsafe = true
                imageRefs.append(ref)
                continue
            }
            document.images.addImage(ref: ref, nsImage)
            imageRefs.append(ref)
        }
        let result = GaussResult(promptId: prompt.id, images: imageRefs)
        prompt.results.append(result)
        document.prompts[promptIndex] = prompt
    }
}

struct PromptComposer_Previews: PreviewProvider {
    static var previews: some View {
        let document = GaussDocument(
            prompts: [],
            images: [:],
            composer: GaussPrompt(
                text: PromptView_Previews.longPrompt
            )
        )

        PromptComposer(document: .constant(document), submitAction: {})
    }
}
