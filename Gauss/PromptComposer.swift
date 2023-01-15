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
    @ObservedObject var assets = AssetManager.inst
    @Environment(\.openWindow) var openWindow

    var submitAction: () -> Void
    var forceShow = false

    var currentModel: GaussModel {
        document.composer.model
    }

    var hasCurrentModel: Bool {
        assets.locateModel(model: currentModel) != nil
    }

    var body: some View {
        VStack {
            let group = Group {
                if hasCurrentModel {
                    PromptInputView(text: $document.composer.text, count: $count, onSubmit: onSubmit)
                        .task {
                            let model = document.composer.model
                            kernel.preloadPipeline(model)
                        }
                } else {
                    HStack {
                        Text("Model \"\(currentModel.description)\" (\(currentModel.shortDescription)) not available")
                        showModelsButton
                    }
                }
                PromptSettingsView(prompt: $document.composer)
            }

            if forceShow || assets.hasModel {
                group
            } else if !assets.loaded {
                group.hidden()
            } else {
                Text("Download models to start generating images").font(.title2).frame(maxWidth: .infinity)
                showModelsButton
            }
        }.padding().background(.regularMaterial)
    }

    @ViewBuilder
    var showModelsButton: some View {
        Button("Show models...") {
            openWindow(id: GaussApp.MODELS_WINDOW)
        }
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
