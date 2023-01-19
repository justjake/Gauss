//
//  ContentView.swift
//  Gauss
//
//  Created by Jake Teton-Landis on 12/3/22.
//

import SwiftUI

let SINGLE_SELECTION = true

struct ContentView: View {
    @Binding var document: GaussDocument
    @State var bottomViewId = UUID()

    var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .top) {
                ScrollView {
                    VStack {
                        // WARNING: using LazyVStack here appears to cause fatal errors:
                        // Swift/ContiguousArrayBuffer.swift:600: Fatal error: Index out of range
                        // VStack seems fine?
                        // Stack Overflow is not helpful.
                        VStack {
                            PromptListView(document: $document, images: $document.images, prompts: $document.prompts)
                        }

                        // Occupy space
                        PromptComposer(
                            document: $document,
                            submitAction: {}
                        )
                        .disabled(true)
                        .opacity(0)
                        .id(bottomViewId)
                    }.frame(maxWidth: .infinity)
                }

                VStack {
                    Spacer()

                    let scrollToBottom = {
                        withAnimation {
                            proxy.scrollTo(bottomViewId)
                        }
                    }

                    PromptComposer(document: $document, submitAction: scrollToBottom)
                        .task {
                            await AssetManager.inst.refreshAvailableModels()
                        }
                }
            }.background(Rectangle().fill(.background))
        }
    }
}

// Keep getting IndexOutOfBounds panics
// Internet suggests MORE VIEWS https://stackoverflow.com/questions/72932427/swiftui-throwing-fatal-error-index-out-of-range-when-adding-element-for-app-w
struct PromptListView: View {
    @Binding var document: GaussDocument
    @Binding var images: GaussImages
    @Binding var prompts: [GaussPrompt]

    var body: some View {
        ForEach($prompts) { $prompt in
            PromptWithResultsView(document: $document, images: $images, prompt: $prompt)
        }
        .frame(alignment: .top)
    }
}

struct PromptWithResultsView: View {
    @Binding var document: GaussDocument
    @Binding var images: GaussImages
    @Binding var prompt: GaussPrompt

    var body: some View {
        PromptView(
            prompt: $prompt,
            images: $images,
            document: $document
        )
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding()

        ResultsView(prompt: $prompt, images: $document.images)
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

    static var selected = Set([document.prompts.first?.id ?? UUID()])

    static var previews: some View {
        ContentView(
            document: .constant(document)
        ).environmentObject(kernel)
    }
}
