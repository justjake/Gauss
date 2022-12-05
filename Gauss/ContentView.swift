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

    var body: some View {
        ZStack(alignment: .top) {
            ScrollViewReader { scroller in
                ScrollView {
                    VStack {
                            ForEach($document.prompts, editActions: .move) { $prompt in
                                PromptView(
                                    prompt: $prompt,
                                    images: $document.images,
                                    document: $document
                                ).id(prompt.id).onAppear {
                                    withAnimation {
                                        scroller.scrollTo(prompt.id)
                                    }
                                }
                            }
                            .frame(alignment: .top)
                            
                            HStack {
                                Spacer()
                                AddPromptButton(document: $document)
                                    .padding()
                                    .frame(minWidth: 600, alignment: .trailing)
                            }
                    }.frame(maxWidth: .infinity)
                }
            }

            
            VStack {
                HStack {
                    KernelStatusView().padding()
                    Spacer()
                }
                Spacer()
            }
        }.background(Rectangle().fill(.background))
    }
}

extension DropInfo {
    
}

struct PromptDropDelegate: DropDelegate {
    var dropTarget: GaussPrompt
    @Binding var dragging: GaussPrompt?
    @Binding var document: GaussDocument
        
    func dropEntered(info: DropInfo) {
        if (!info.hasItemsConforming(to: [.gaussPromptId])) {
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
