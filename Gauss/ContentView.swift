//
//  ContentView.swift
//  Gauss
//
//  Created by Jake Teton-Landis on 12/3/22.
//

import SwiftUI

struct ContentView: View {
    @Binding var document: GaussDocument
    @Binding var dragging: GaussPrompt?

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView([.vertical]) {
//                List(content: $document.prompts, editActions: .all) { $prompt in
//
//                }
                VStack(spacing: 0) {
                    ForEach($document.prompts) { $prompt in
                            .onDrag {
                                let item = NSItemProvider()
                                dragging = $prompt.wrappedValue
                                item.register($prompt.wrappedValue)
                                return item
                            }
                    }
                    
                    if (document.prompts.isEmpty) {
                        AddPromptButton(document: $document)
                    }
                }.padding([.vertical])
                    .frame(alignment: .top)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            
            
            VStack {
                HStack {
                    Spacer()
                    KernelStatusView().padding().opacity(0.5)
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
    
    static var previews: some View {
        ContentView(document: .constant(document)).environmentObject(kernel)
    }
}
