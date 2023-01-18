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
    @State var dragging: GaussPrompt? = nil
    private let bottomViewId = UUID()

    var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    ScrollView {
                        LazyVStack {
                            PromptListView(document: $document, images: $document.images, prompts: $document.prompts)

                            // Occupy space
                            PromptComposer(
                                document: $document,
                                submitAction: {}
                            ).disabled(true).opacity(0).id(bottomViewId)
                        }.frame(maxWidth: .infinity)
                    }
                }

                VStack {
                    Spacer()
                    PromptComposer(document: $document, submitAction: { withAnimation { proxy.scrollTo(bottomViewId) } })
                        .onAppear {
                            Task {
                                await AssetManager.inst.refreshAvailableModels()
                            }
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

struct PromptDropDelegate: DropDelegate {
    var dropTarget: GaussPrompt
    @Binding var dragging: GaussPrompt?
    @Binding var document: GaussDocument

    func dropEntered(info: DropInfo) {
        if !info.hasItemsConforming(to: [.gaussPromptId]) {
            return
        }

        guard let draggingOwnItem = dragging else {
            return
        }

        if draggingOwnItem.id == dropTarget.id {
            return
        }

        let from = document.prompts.firstIndex { $0.id == dropTarget.id }
        let to = document.prompts.firstIndex { $0.id == dropTarget.id }
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return false
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
